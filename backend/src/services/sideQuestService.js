const db = require('../config/db');
const ApiError = require('../utils/ApiError');

const NUM_QUESTS_TO_RETURN = 3;

/**
 * คำนวณ target_count ต่อ template:
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

/**
 * GET /api/v1/quests/side?environment=park&trainingType=easy
 * คืน 3 side quest แบบสุ่ม พร้อมสร้าง instance ผูกกับ user (running_session_id
 * ยังเป็น NULL ไปก่อน — จะผูกทีหลังตอนเริ่ม running session จริง)
 */
async function getTodaySideQuests(userId, environment, trainingType) {
  // 1. หาระยะทางที่วางแผนไว้วันนี้ (ถ้ามี main quest ของวันนี้ที่ session_type
  //    ตรงกับ trainingType และ unit เป็น km)
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

  // 2. สุ่มเลือก template ที่ active ตาม environment + training_type
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

  // 3. สร้าง user_side_quest_instances ต่อ template ที่เลือก
  const instances = [];
  for (const t of templates) {
    const targetCount = computeTargetCount(t, plannedDistanceKm);

    const { rows } = await db.query(
      `INSERT INTO user_side_quest_instances
         (user_id, side_quest_template_id, target_count)
       VALUES ($1, $2, $3)
       RETURNING id, target_count, found_count, status, started_at`,
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

module.exports = {
  getTodaySideQuests,
};
