const db = require('../config/db');
const ApiError = require('../utils/ApiError');

// ============================================================================
// สมมติฐานที่ยังไม่ได้ confirm — mark ไว้ชัดเจน:
// 1. Auto-schedule template ด้านล่างเป็น pattern ที่ผมออกแบบเอง (ยังไม่เคยคุยกัน)
//    ยึดตาม weekly_cap + sequencing_rules ที่ seed ไว้ ไม่ผิดกฎแน่นอน แต่ตัว
//    "ลำดับวันในสัปดาห์" เป็นการเดาที่สมเหตุสมผลที่สุดเท่านั้น
// 2. โปรแกรม auto จะ generate ครบทั้งโปรแกรมทันทีตอนสมัคร (ตาม duration_weeks_min)
// ============================================================================

const LEVELS_BLOCKED = ['advanced', 'elite'];

// ---- Weekly template: [day_offset (0=วันเริ่มสัปดาห์), session_type] ----
// day_offset 0-6 = จันทร์-อาทิตย์ (สัมพัทธ์กับ start_date ของ user_programs)
const AUTO_TEMPLATES = {
  // Beginner: ไม่มี phase (phase_id = NULL เสมอ)
  beginner: {
    default: [
      { day: 0, session_type: 'easy' },
      { day: 2, session_type: 'easy' },
      { day: 4, session_type: 'easy' },
      { day: 5, session_type: 'long_run' }, // day 4 (easy) อยู่ก่อนหน้า -> ผ่าน must_precede
    ],
  },
  // Lower/Upper Intermediate ใช้ template เดียวกัน (base/build/peak เท่านั้น
  // — taper/race ยังไม่ได้ออกแบบ pattern แยก ใช้ default นี้ไปก่อน)
  lower_intermediate: {
    default: [
      { day: 0, session_type: 'easy' },
      { day: 1, session_type: 'vo2max' },
      { day: 3, session_type: 'tempo' },
      { day: 4, session_type: 'easy' },
      { day: 6, session_type: 'long_run' },
    ],
  },
  upper_intermediate: {
    default: [
      { day: 0, session_type: 'easy' },
      { day: 1, session_type: 'vo2max' },
      { day: 3, session_type: 'tempo' },
      { day: 4, session_type: 'easy' },
      { day: 6, session_type: 'long_run' },
    ],
  },
};

/**
 * เช็ค require_exp_level ของ template เทียบกับ rank ปัจจุบันของ user
 * (ตัดสินใจ (A) ที่ล็อกไว้: เช็คแค่ rank ปัจจุบัน ไม่เช็คประวัติ completed program)
 */
async function assertLevelPrerequisite(userLevel, template) {
  if (LEVELS_BLOCKED.includes(userLevel)) {
    throw new ApiError(400, 'ระบบ Adaptive Program รองรับเฉพาะ beginner, lower_intermediate, upper_intermediate ในตอนนี้');
  }

  if (!template.require_exp_level) return; // ไม่มี prerequisite

  const { rows } = await db.query(
    `SELECT
       (SELECT rank FROM experience_level_ranks WHERE level = $1) AS user_rank,
       (SELECT rank FROM experience_level_ranks WHERE level = $2) AS required_rank`,
    [userLevel, template.require_exp_level]
  );

  const { user_rank, required_rank } = rows[0];
  if (user_rank == null || required_rank == null || user_rank < required_rank) {
    throw new ApiError(400, `ต้องมีระดับ ${template.require_exp_level} ก่อนถึงจะเริ่มโปรแกรมนี้ได้`);
  }
}

/**
 * ดึง program_template ตาม level ที่ผู้ใช้ขอ
 */
async function getTemplateByLevel(level) {
  const { rows } = await db.query(
    `SELECT * FROM program_templates WHERE level = $1`,
    [level]
  );
  if (rows.length === 0) throw new ApiError(404, `ไม่พบ program template สำหรับ level: ${level}`);
  return rows[0];
}

/**
 * สร้าง baseline เริ่มต้น = value_low ของ session_type_specs (ตัดสินใจ (C):
 * ไม่ derive จากข้อมูลผู้ใช้ ใช้ค่าเริ่มต้นตายตัวจาก template แล้วค่อยปรับทีหลัง)
 */
async function createBaselines(client, userProgramId, programTemplateId) {
  const { rows: specs } = await client.query(
    `SELECT DISTINCT ON (session_type) session_type, value_low, unit
     FROM session_type_specs
     WHERE program_template_id = $1
     ORDER BY session_type, phase_id NULLS FIRST`,
    [programTemplateId]
  );

  for (const spec of specs) {
    await client.query(
      `INSERT INTO user_program_baselines (user_program_id, session_type, base_value, unit)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_program_id, session_type) DO NOTHING`,
      [userProgramId, spec.session_type, spec.value_low, spec.unit]
    );
  }
}

/**
 * เตรียม user_program_completion ล่วงหน้า (target_count จาก program_total_target)
 */
async function initProgramCompletion(client, userProgramId, programTemplateId) {
  const { rows: targets } = await client.query(
    `SELECT DISTINCT ON (session_type) session_type, program_total_target
     FROM session_type_specs
     WHERE program_template_id = $1 AND program_total_target IS NOT NULL
     ORDER BY session_type, phase_id NULLS FIRST`,
    [programTemplateId]
  );

  for (const t of targets) {
    await client.query(
      `INSERT INTO user_program_completion (user_program_id, session_type, completed_count, target_count)
       VALUES ($1, $2, 0, $3)
       ON CONFLICT (user_program_id, session_type) DO NOTHING`,
      [userProgramId, t.session_type, t.program_total_target]
    );
  }
}

/**
 * Generate ตารางทั้งโปรแกรมล่วงหน้าสำหรับโหมด auto (prototype)
 * ใช้ template ง่ายๆ วนซ้ำทุกสัปดาห์ตาม duration_weeks_min ของ template
 * (ยังไม่แยก pattern ตาม phase — ใช้ default เดียวทั้งโปรแกรม เป็น known gap)
 */
async function generateAutoSchedule(client, userProgramId, level, startDate, durationWeeksMin) {
  const template = AUTO_TEMPLATES[level]?.default;
  if (!template) {
    throw new ApiError(500, `ไม่มี auto-schedule template สำหรับ level: ${level}`);
  }

  const rows = [];
  for (let week = 0; week < durationWeeksMin; week++) {
    for (const item of template) {
      const scheduledDate = new Date(startDate);
      scheduledDate.setDate(scheduledDate.getDate() + week * 7 + item.day);
      rows.push({ scheduledDate, sessionType: item.session_type });
    }
  }

  // insert ทีละแถว (trigger fn_main_quest_before_insert / weekly_cap /
  // sequencing rules ที่ migrate ไว้แล้วจะทำงานอัตโนมัติต่อแถว)
  for (const r of rows) {
    await client.query(
      `INSERT INTO main_quest_instances (user_program_id, scheduled_date, session_type)
       VALUES ($1, $2, $3)`,
      [userProgramId, r.scheduledDate.toISOString().slice(0, 10), r.sessionType]
    );
  }
}

/**
 * POST /api/v1/programs/start
 */
async function startProgram(userId, level, scheduleMode) {
  // 1. ดึง running_experience_level ปัจจุบันของผู้ใช้
  const { rows: userRows } = await db.query(
    `SELECT running_experience_level FROM user_basic_info WHERE user_id = $1`,
    [userId]
  );
  if (userRows.length === 0) {
    throw new ApiError(400, 'กรุณาทำ Onboarding Step 1 ให้เสร็จก่อน');
  }
  const userLevel = userRows[0].running_experience_level;

  // 2. เช็คว่ามีโปรแกรม active อยู่แล้วหรือไม่ (1 คน active ได้แค่ 1 โปรแกรม)
  const { rows: activeRows } = await db.query(
    `SELECT id FROM user_programs WHERE user_id = $1 AND status = 'active'`,
    [userId]
  );
  if (activeRows.length > 0) {
    throw new ApiError(400, 'คุณมีโปรแกรมที่กำลังดำเนินการอยู่แล้ว ต้องจบ/หยุดโปรแกรมเดิมก่อน');
  }

  // 3. ดึง template + เช็ค prerequisite
  const template = await getTemplateByLevel(level);
  await assertLevelPrerequisite(userLevel, template);

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const startDate = new Date().toISOString().slice(0, 10);

    const { rows: programRows } = await client.query(
      `INSERT INTO user_programs (user_id, program_template_id, start_date, schedule_mode)
       VALUES ($1, $2, $3, $4)
       RETURNING id, start_date, current_week, status, schedule_mode`,
      [userId, template.id, startDate, scheduleMode]
    );
    const userProgram = programRows[0];

    await createBaselines(client, userProgram.id, template.id);
    await initProgramCompletion(client, userProgram.id, template.id);

    if (scheduleMode === 'auto') {
      await generateAutoSchedule(
        client,
        userProgram.id,
        level,
        userProgram.start_date,
        template.duration_weeks_min
      );
    }
    // scheduleMode === 'manual' -> ไม่ generate อะไร ผู้ใช้จะลงเองทีละวัน
    // ผ่าน endpoint main_quest_instances (ยังไม่ได้ทำในรอบนี้)

    await client.query('COMMIT');

    return {
      userProgramId: userProgram.id,
      programLevel: level,
      scheduleMode: userProgram.schedule_mode,
      startDate: userProgram.start_date,
      currentWeek: userProgram.current_week,
      status: userProgram.status,
    };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * GET /api/v1/programs/current/week
 * ดึง main_quest_instances ของ "สัปดาห์นี้" (เทียบจาก start_date ของโปรแกรม active)
 */
async function getCurrentWeek(userId) {
  const { rows: programRows } = await db.query(
    `SELECT id, start_date, schedule_mode, program_template_id
     FROM user_programs WHERE user_id = $1 AND status = 'active'`,
    [userId]
  );
  if (programRows.length === 0) {
    throw new ApiError(404, 'ไม่พบโปรแกรมที่กำลังดำเนินการอยู่ กรุณาสมัครโปรแกรมก่อน');
  }
  const program = programRows[0];

  const { rows: weekRows } = await db.query(
    `SELECT
       FLOOR((CURRENT_DATE - $1::date) / 7)::integer AS week_number,
       ($1::date + (FLOOR((CURRENT_DATE - $1::date) / 7)::integer * 7))::date AS week_start,
       ($1::date + (FLOOR((CURRENT_DATE - $1::date) / 7)::integer * 7) + 6)::date AS week_end`,
    [program.start_date]
  );

  //  ดึงค่าจาก weekRows[0] เพื่อให้ใช้งานใน SQL ถัดไปและ return ได้
  const { week_number, week_start, week_end } = weekRows[0];

  const { rows: quests } = await db.query(
    `SELECT id, scheduled_date, session_type, planned_value, unit, status,
            actual_value, rpe_reported, is_bonus, running_session_id
     FROM main_quest_instances
     WHERE user_program_id = $1
       AND scheduled_date BETWEEN $2 AND $3
     ORDER BY scheduled_date ASC`,
    [program.id, week_start, week_end]
  );

  return {
    userProgramId: program.id,
    scheduleMode: program.schedule_mode,
    weekNumber: Number(week_number) + 1, // แสดงเป็น 1-indexed ให้ user
    weekStart: week_start,
    weekEnd: week_end,
    quests,
  };
}

/**
 * แปลง error จาก Postgres trigger (RAISE EXCEPTION ใน fn_check_weekly_cap /
 * fn_check_sequencing_rules) ให้เป็น ApiError ที่อ่านรู้เรื่อง แทนที่จะเป็น
 * 500 ดิบๆ — Postgres ใช้ SQLSTATE 'P0001' สำหรับ RAISE EXCEPTION แบบไม่ระบุ code
 */
function translateDbError(err) {
  if (err.code === 'P0001') {
    return new ApiError(400, err.message);
  }
  if (err.code === '23503') { // foreign_key_violation
    return new ApiError(400, 'ข้อมูลอ้างอิงไม่ถูกต้อง (เช่น program_id ไม่มีอยู่จริง)');
  }
  if (err.code === '22P02') { // invalid_text_representation (เช่น enum ไม่ตรง)
    return new ApiError(400, 'ค่าที่ส่งมาไม่ตรงกับ enum ที่ระบบรองรับ');
  }
  return err; // ปล่อยผ่านให้ asyncHandler/global error handler จัดการเป็น 500 ตามปกติ
}

/**
 * ตรวจว่า user มีโปรแกร active + เป็น manual mode จริง ก่อนให้ลงวันเอง
 */
async function assertManualModeActiveProgram(userId) {
  const { rows } = await db.query(
    `SELECT id, schedule_mode, status FROM user_programs
     WHERE user_id = $1 AND status = 'active'`,
    [userId]
  );
  if (rows.length === 0) {
    throw new ApiError(404, 'ไม่พบโปรแกรมที่กำลังดำเนินการอยู่ กรุณาสมัครโปรแกรมก่อน');
  }
  if (rows[0].schedule_mode !== 'manual') {
    throw new ApiError(400, 'โปรแกรมนี้เป็นโหมด auto ไม่รองรับการลงวันเอง');
  }
  return rows[0];
}

/**
 * POST /api/v1/programs/quests — ลงเควสวันเดียวเอง (manual mode เท่านั้น)
 * ไม่ต้องคำนวณ phase_id / planned_value เอง — trigger fn_main_quest_before_insert
 * จัดการให้อัตโนมัติ, weekly_cap และ sequencing rules ก็เช็คโดย trigger เช่นกัน
 */
async function addManualQuest(userId, scheduledDate, sessionType) {
  const program = await assertManualModeActiveProgram(userId);

  try {
    const { rows } = await db.query(
      `INSERT INTO main_quest_instances (user_program_id, scheduled_date, session_type)
       VALUES ($1, $2, $3)
       RETURNING id, scheduled_date, session_type, planned_value, unit, status, phase_id`,
      [program.id, scheduledDate, sessionType]
    );
    return rows[0];
  } catch (err) {
    throw translateDbError(err);
  }
}

/**
 * DELETE /api/v1/programs/quests/:questId — ลบเควสที่ลงผิด (แก้เฉพาะที่ยัง
 * pending เท่านั้น กันลบของที่ทำไปแล้ว/กระทบ user_program_completion)
 */
async function deleteManualQuest(userId, questId) {
  const program = await assertManualModeActiveProgram(userId);

  const { rows } = await db.query(
    `DELETE FROM main_quest_instances
     WHERE id = $1 AND user_program_id = $2 AND status = 'pending'
     RETURNING id`,
    [questId, program.id]
  );

  if (rows.length === 0) {
    throw new ApiError(404, 'ไม่พบเควสนี้ หรือเควสนี้ไม่ใช่สถานะ pending (ลบได้เฉพาะที่ยังไม่เริ่มทำ)');
  }
  return { deletedId: rows[0].id };
}

/**
 * GET /api/v1/programs/quests?from=&to= — ดูช่วงวันที่เอง (manual mode
 * มักต้องดูล่วงหน้าหลายสัปดาห์ ไม่ใช่แค่สัปดาห์ปัจจุบันเหมือน auto)
 * ถ้าไม่ส่ง from/to มา -> fallback เป็นสัปดาห์ปัจจุบัน (เหมือน getCurrentWeek)
 */
async function getQuestsInRange(userId, from, to) {
  const { rows: programRows } = await db.query(
    `SELECT id, start_date, schedule_mode FROM user_programs
     WHERE user_id = $1 AND status = 'active'`,
    [userId]
  );
  if (programRows.length === 0) {
    throw new ApiError(404, 'ไม่พบโปรแกรมที่กำลังดำเนินการอยู่ กรุณาสมัครโปรแกรมก่อน');
  }
  const program = programRows[0];

  let rangeFrom = from;
  let rangeTo = to;
  if (!rangeFrom || !rangeTo) {
    const { rows: weekRows } = await db.query(
      `SELECT
         ($1::date + FLOOR((CURRENT_DATE - $1::date) / 7) * 7)::date AS week_start,
         ($1::date + FLOOR((CURRENT_DATE - $1::date) / 7) * 7 + 6)::date AS week_end`,
      [program.start_date]
    );
    rangeFrom = rangeFrom || weekRows[0].week_start;
    rangeTo = rangeTo || weekRows[0].week_end;
  }

  const { rows: quests } = await db.query(
    `SELECT id, scheduled_date, session_type, planned_value, unit, status,
            actual_value, rpe_reported, is_bonus, running_session_id
     FROM main_quest_instances
     WHERE user_program_id = $1
       AND scheduled_date BETWEEN $2 AND $3
     ORDER BY scheduled_date ASC`,
    [program.id, rangeFrom, rangeTo]
  );

  return {
    userProgramId: program.id,
    scheduleMode: program.schedule_mode,
    from: rangeFrom,
    to: rangeTo,
    quests,
  };
}

module.exports = {
  startProgram,
  getCurrentWeek,
  addManualQuest,
  deleteManualQuest,
  getQuestsInRange,
};