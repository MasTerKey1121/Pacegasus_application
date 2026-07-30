const db = require('../config/db');
const ApiError = require('../utils/ApiError');

const NUM_QUESTS_TO_RETURN = 3;
const MAX_ACTIVE_QUESTS_PER_SESSION = 3;

/**
 * คำนวณ target_count ต่อ template:a
 * - collect_distance (Easy/Long Run): ใช้ planned distance ของ main quest วันนี้
 *   (ถ้ามี และ unit=km) มาคิด floor(distance/km_per) แล้ว cap ด้วย cap_count
 *   ถ้าไม่มีข้อมูล distance เลย fallback เป็น cap_count เต็ม (สมมติฐานที่ยัง
 *   ไม่ confirm — ดู comment ในบทสนทนา)
 * - pace_trigger / sprint_marker (Tempo/Interval): ใช้ fixed_count ตรงๆ
 */
function computeTargetCount(template, plannedDistanceKm) {
  if (template.mechanic_type === 'collect_distance') {
    if (plannedDistanceKm != null && template.km_per) {
      const raw = Math.floor(plannedDistanceKm / Number(template.km_per));
      return Math.max(1, Math.min(raw, template.cap_count));
    }
    return template.cap_count; // fallback: ยังไม่รู้ระยะ ใช้ค่าสูงสุดไปก่อน
  }
  // pace_trigger, sprint_marker
  return template.fixed_count;
}

function buildInstancePayload(row) {
  return {
    id: row.id,
    runningSessionId: row.running_session_id,
    userId: row.user_id,
    sideQuestTemplateId: row.side_quest_template_id,
    targetCount: row.target_count,
    foundCount: row.found_count,
    status: row.status,
    coinAwarded: row.coin_awarded,
    startedAt: row.started_at,
    completedAt: row.completed_at,
  };
}

/**
 * GET /api/v1/quests/side?environment=park&trainingType=easy
 * คืน 3 side quest แบบสุ่ม พร้อมสร้าง instance ผูกกับ user (running_session_id
 * ยังเป็น NULL ไปก่อน — จะผูกทีหลังตอนเริ่ม running session จริง)
 */
async function getTodaySideQuests(userId, environment, trainingType) {
  const { rows: mainQuestRows } = await db.query(
    `SELECT planned_value FROM main_quest_instances mq
     JOIN user_programs up ON up.id = mq.user_program_id
     WHERE up.user_id = $1
       AND up.status = 'active'
       AND mq.scheduled_date = CURRENT_DATE
       AND mq.session_type = $2
       AND mq.unit = 'km'
     LIMIT 1`,
    [userId, trainingType]
  );
  const plannedDistanceKm = mainQuestRows.length > 0 ? Number(mainQuestRows[0].planned_value) : null;

  const { rows: templates } = await db.query(
    `SELECT id, title, description, target_object, mechanic_type,
            km_per, cap_count, fixed_count, coin_reward_base
     FROM side_quest_templates
     WHERE environment = $1 AND training_type = $2 AND is_active = true
     ORDER BY random()
     LIMIT $3`,
    [environment, trainingType, NUM_QUESTS_TO_RETURN]
  );

  if (templates.length === 0) {
    throw new ApiError(404, `ไม่พบ side quest สำหรับ ${environment} x ${trainingType}`);
  }

  const instances = [];
  for (const t of templates) {
    const targetCount = computeTargetCount(t, plannedDistanceKm);

    const { rows } = await db.query(
      `INSERT INTO user_side_quest_instances
         (user_id, side_quest_template_id, target_count)
       VALUES ($1, $2, $3)
       RETURNING id, running_session_id, user_id, side_quest_template_id, target_count, found_count, status, coin_awarded, started_at, completed_at`,
      [userId, t.id, targetCount]
    );

    instances.push({
      instanceId: rows[0].id,
      title: t.title,
      description: t.description,
      targetObject: t.target_object,
      mechanicType: t.mechanic_type,
      targetCount: rows[0].target_count,
      foundCount: rows[0].found_count,
      status: rows[0].status,
      coinRewardBase: t.coin_reward_base,
    });
  }

  return { environment, trainingType, plannedDistanceKm, quests: instances };
}
/**
 * เริ่มหลาย side quest พร้อมกันใน 1 running session แบบ atomic
 * ถ้ามีตัวใดตัวหนึ่ง fail จะ rollback ทั้งหมด
 *
 * instancesPayload: Array<{ instanceId?: number, sideQuestTemplateId?: number }>
 */
async function startSideQuests(userId, runningSessionId, instancesPayload) {
  const client = await db.pool.connect(); // ปรับตาม db module จริงถ้าจำเป็น

  try {
    await client.query('BEGIN');

    // 1) กันไม่ให้ session นี้มี active quest เกิน limit
    //    lock แถวของ session ไว้ก่อน (ถ้ามีตาราง running_sessions) กัน race
    //    ระหว่าง 2 request พร้อมกันมาชนกัน — ใช้ตรงนี้เพื่อ serialize
    const { rows: existingActiveRows } = await client.query(
      `SELECT id FROM user_side_quest_instances
       WHERE running_session_id = $1
         AND user_id = $2
         AND status IN ('in_progress', 'completed')
       FOR UPDATE`,
      [runningSessionId, userId]
    );

    if (existingActiveRows.length + instancesPayload.length > MAX_ACTIVE_QUESTS_PER_SESSION) {
      throw new ApiError(
        400,
        `running session นี้มี quest ผูกอยู่แล้ว ${existingActiveRows.length} ตัว ` +
        `เกิน limit ${MAX_ACTIVE_QUESTS_PER_SESSION} ตัวต่อ session`
      );
    }

    const results = [];
    for (const item of instancesPayload) {
      const instance = await startSingleSideQuest(client, userId, runningSessionId, item);
      results.push(instance);
    }

    await client.query('COMMIT');
    return results;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * helper: เริ่ม quest เดียว ใช้ client เดียวกับ transaction ข้างนอก
 * ต้องรับ client เข้ามาแทนที่จะเรียก db.query ตรงๆ เพื่อให้อยู่ transaction เดียวกัน
 */
async function startSingleSideQuest(client, userId, runningSessionId, item) {
  const { instanceId, sideQuestTemplateId } = item;

  if (!instanceId && !sideQuestTemplateId) {
    throw new ApiError(400, 'แต่ละ instance ต้องระบุ instanceId หรือ sideQuestTemplateId');
  }

  if (instanceId) {
    const { rows } = await client.query(
      `SELECT id, running_session_id, user_id, side_quest_template_id, target_count,
              found_count, status, coin_awarded, started_at, completed_at
       FROM user_side_quest_instances
       WHERE id = $1 AND user_id = $2
       FOR UPDATE`,
      [instanceId, userId]
    );

    if (rows.length === 0) {
      throw new ApiError(404, `ไม่พบ side quest instance id=${instanceId}`);
    }

    const current = rows[0];

    // กัน reassign quest ที่ completed ไปแล้ว
    if (current.status === 'completed') {
      throw new ApiError(409, `instance id=${instanceId} เสร็จสิ้นไปแล้ว ไม่สามารถเริ่มใหม่ได้`);
    }

    // กัน overwrite quest ที่ผูกกับ session อื่นอยู่แล้ว (ที่ไม่ใช่ session นี้)
    if (
      current.running_session_id != null &&
      String(current.running_session_id) !== String(runningSessionId)
    ) {
      throw new ApiError(
        409,
        `instance id=${instanceId} ถูกผูกกับ running session อื่นอยู่แล้ว`
      );
    }

    const { rows: updatedRows } = await client.query(
      `UPDATE user_side_quest_instances
       SET running_session_id = $3,
           status = 'in_progress',
           started_at = COALESCE(started_at, now())
       WHERE id = $1 AND user_id = $2
       RETURNING id, running_session_id, user_id, side_quest_template_id, target_count,
                 found_count, status, coin_awarded, started_at, completed_at`,
      [instanceId, userId, runningSessionId]
    );

    return buildInstancePayload(updatedRows[0]);
  }

  // สร้างใหม่จาก template
  const { rows: templateRows } = await client.query(
    `SELECT id, mechanic_type, km_per, cap_count, fixed_count
     FROM side_quest_templates
     WHERE id = $1 AND is_active = true`,
    [sideQuestTemplateId]
  );

  if (templateRows.length === 0) {
    throw new ApiError(404, `ไม่พบ side quest template id=${sideQuestTemplateId}`);
  }

  // กัน insert quest template เดิมซ้ำในระหว่าง session เดียวกัน
  const { rows: dupRows } = await client.query(
    `SELECT id FROM user_side_quest_instances
     WHERE running_session_id = $1
       AND user_id = $2
       AND side_quest_template_id = $3
       AND status IN ('in_progress', 'completed')`,
    [runningSessionId, userId, sideQuestTemplateId]
  );

  if (dupRows.length > 0) {
    throw new ApiError(
      409,
      `template id=${sideQuestTemplateId} ถูกเริ่มไปแล้วใน session นี้`
    );
  }

  const targetCount = computeTargetCount(templateRows[0], null);
  const { rows: insertedRows } = await client.query(
    `INSERT INTO user_side_quest_instances
       (user_id, side_quest_template_id, running_session_id, target_count)
     VALUES ($1, $2, $3, $4)
     RETURNING id, running_session_id, user_id, side_quest_template_id, target_count,
               found_count, status, coin_awarded, started_at, completed_at`,
    [userId, sideQuestTemplateId, runningSessionId, targetCount]
  );

  return buildInstancePayload(insertedRows[0]);
}

// ... updateProgress, finishSideQuest, getQuestAlbum เหมือนเดิม ...

async function updateProgress(userId, questId, payload) {
  const { rows: currentRows } = await db.query(
    `SELECT id, running_session_id, user_id, side_quest_template_id, target_count, found_count, status, coin_awarded, started_at, completed_at
     FROM user_side_quest_instances
     WHERE id = $1 AND user_id = $2`,
    [questId, userId]
  );

  if (currentRows.length === 0) {
    throw new ApiError(404, 'ไม่พบ side quest instance ที่ต้องการ');
  }

  const current = currentRows[0];
  const nextFoundCount = payload.foundCount != null
    ? payload.foundCount
    : (current.found_count + (payload.increment || 0));

  const boundedFoundCount = Math.max(0, Math.min(nextFoundCount, current.target_count));
  const nextStatus = boundedFoundCount >= current.target_count ? 'completed' : current.status;

  const { rows: updatedRows } = await db.query(
    `UPDATE user_side_quest_instances
     SET found_count = $3,
         status = $4,
         completed_at = CASE WHEN $4 = 'completed' AND status <> 'completed' THEN now() ELSE completed_at END
     WHERE id = $1 AND user_id = $2
     RETURNING id, running_session_id, user_id, side_quest_template_id, target_count, found_count, status, coin_awarded, started_at, completed_at`,
    [questId, userId, boundedFoundCount, nextStatus]
  );

  if (payload.photoUrl) {
    await db.query(
      `INSERT INTO quest_album_photos (user_side_quest_instance_id, photo_url, gps_lat, gps_lng)
       VALUES ($1, $2, $3, $4)`,
      [questId, payload.photoUrl, payload.gpsLat ?? null, payload.gpsLng ?? null]
    );
  }

  return buildInstancePayload(updatedRows[0]);
}

async function finishSideQuest(userId, questId) {
  const { rows } = await db.query(
    `UPDATE user_side_quest_instances
     SET status = 'completed',
         found_count = GREATEST(found_count, target_count),
         completed_at = COALESCE(completed_at, now())
     WHERE id = $1 AND user_id = $2
     RETURNING id, running_session_id, user_id, side_quest_template_id, target_count, found_count, status, coin_awarded, started_at, completed_at`,
    [questId, userId]
  );

  if (rows.length === 0) {
    throw new ApiError(404, 'ไม่พบ side quest instance ที่ต้องการ');
  }

  return buildInstancePayload(rows[0]);
}

async function getQuestAlbum(userId, questId) {
  const { rows } = await db.query(
    `SELECT p.id, p.user_side_quest_instance_id, p.photo_url, p.gps_lat, p.gps_lng, p.captured_at
     FROM quest_album_photos p
     JOIN user_side_quest_instances u ON u.id = p.user_side_quest_instance_id
     WHERE p.user_side_quest_instance_id = $1 AND u.user_id = $2
     ORDER BY p.captured_at DESC`,
    [questId, userId]
  );

  return rows;
}

module.exports = {
  getTodaySideQuests,
  startSideQuests,
  updateProgress,
  finishSideQuest,
  getQuestAlbum,
};


