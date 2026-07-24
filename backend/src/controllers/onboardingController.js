const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const asyncHandler = require('../utils/asyncHandler');
const { step1Schema, step2Schema, step3Schema, step4Schema } = require('../utils/validators');

// GET /api/onboarding/status
const getStatus = asyncHandler(async (req, res) => {
  const { rows } = await db.query(
    `SELECT onboarding_step, onboarding_completed FROM users WHERE id = $1`,
    [req.user.id]
  );
  if (rows.length === 0) throw new ApiError(404, 'ไม่พบผู้ใช้งาน');

  res.status(200).json({
    success: true,
    data: {
      currentStep: rows[0].onboarding_step,
      completed: rows[0].onboarding_completed,
    },
  });
});

async function advanceStep(userId, stepNumber, isFinal = false) {
  await db.query(
    `UPDATE users
     SET onboarding_step = GREATEST(onboarding_step, $2),
         onboarding_completed = onboarding_completed OR $3
     WHERE id = $1`,
    [userId, stepNumber, isFinal]
  );
}

// เช็คว่า user ทำ step ก่อนหน้ามาแล้วหรือยัง (กัน skip step)
async function ensureStepUnlocked(userId, requiredStep) {
  const { rows } = await db.query(
    `SELECT onboarding_step FROM users WHERE id = $1`,
    [userId]
  );
  if (rows.length === 0) throw new ApiError(404, 'ไม่พบผู้ใช้งาน');
  if (rows[0].onboarding_step < requiredStep) {
    throw new ApiError(400, `กรุณาทำ Step ${requiredStep} ให้เสร็จก่อน`);
  }
}

function deriveExperienceLevel(value) {
  if (!value.hasRunBefore || !value.isCurrentlyRunning) return 'beginner';

  const weeks = value.weeksRunning ?? 0;
  const longest = value.longestDistanceKm ?? 0;

  // Beginner: ยังฝึกไม่ถึง ~8 เดือน หรือวิ่งไกลสุดยังไม่ถึง 5 กม.
  if (weeks < 34 || longest < 5) return 'beginner';

  // Upper Intermediate: ฝึกต่อเนื่อง >= 1 ปี และเคยวิ่งไกลสุด >= 15 กม.
  // (ใกล้ระยะ Half Marathon แล้ว พร้อมขยับไปคอร์ส 21k)
  if (weeks >= 52 && longest >= 15) return 'upper_intermediate';

  // Lower Intermediate: อยู่ระหว่างกลาง (ฝึกมาสักพัก วิ่งไกลสุดอยู่ในช่วง 10k)
  return 'lower_intermediate';
}

// PUT /api/onboarding/step1  (basic info)
const saveStep1 = asyncHandler(async (req, res) => {
  const { value, error } = step1Schema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const userId = req.user.id;

  await db.query(
    `INSERT INTO user_basic_info
       (user_id, date_of_birth, gender, height_cm, weight_kg, running_days_per_week)
     VALUES ($1,$2,$3,$4,$5,$6)
     ON CONFLICT (user_id) DO UPDATE SET
       date_of_birth = EXCLUDED.date_of_birth,
       gender = EXCLUDED.gender,
       height_cm = EXCLUDED.height_cm,
       weight_kg = EXCLUDED.weight_kg,
       running_days_per_week = EXCLUDED.running_days_per_week`,
    [
      userId,
      value.dateOfBirth,
      value.gender,
      value.heightCm,
      value.weightKg,
      value.runningDaysPerWeek,
    ]
  );

  await advanceStep(userId, 1);

  res.status(200).json({ success: true, message: 'บันทึกข้อมูลพื้นฐานสำเร็จ', data: { step: 1 } });
});

// PUT /api/onboarding/step2  (injury history)
const saveStep2 = asyncHandler(async (req, res) => {
  const { value, error } = step2Schema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const userId = req.user.id;
  await ensureStepUnlocked(userId, 1);

  const client = await db.getClient();

  try {
    await client.query('BEGIN');

    await client.query(
      `INSERT INTO user_injury_summary (user_id, has_injury_history)
       VALUES ($1, $2)
       ON CONFLICT (user_id) DO UPDATE SET has_injury_history = EXCLUDED.has_injury_history`,
      [userId, value.hasInjuryHistory]
    );

    await client.query(`DELETE FROM user_injuries WHERE user_id = $1`, [userId]);

    if (value.hasInjuryHistory && value.injuries.length > 0) {
      for (const injury of value.injuries) {
        await client.query(
          `INSERT INTO user_injuries
             (user_id, body_part, injury_type, is_current)
           VALUES ($1,$2,$3,$4)`,
          [
            userId,
            injury.bodyPart,
            injury.injuryType || null,
            injury.isCurrent,
          ]
        );
      }
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  await advanceStep(userId, 2);

  res.status(200).json({ success: true, message: 'บันทึกประวัติการบาดเจ็บสำเร็จ', data: { step: 2 } });
});

// PUT /api/onboarding/step3  (goals)
const saveStep3 = asyncHandler(async (req, res) => {
  const { value, error } = step3Schema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const userId = req.user.id;
  await ensureStepUnlocked(userId, 2);

  const client = await db.getClient();

  try {
    await client.query('BEGIN');
    await client.query(`DELETE FROM user_goals WHERE user_id = $1`, [userId]);

    for (const goal of value.goals) {
      await client.query(
        `INSERT INTO user_goals
           (user_id, goal_type, target_distance_km, target_pace_sec_per_km, is_primary)
         VALUES ($1,$2,$3,$4,$5)`,
        [
          userId,
          goal.goalType,
          goal.targetDistanceKm ?? null,
          goal.targetPaceSecPerKm ?? null,
          goal.isPrimary,
        ]
      );
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  await advanceStep(userId, 3);

  res.status(200).json({ success: true, message: 'บันทึกเป้าหมายสำเร็จ', data: { step: 3 } });
});

// PUT /api/onboarding/step4  (running history) -> derive experience level -> marks onboarding complete
const saveStep4 = asyncHandler(async (req, res) => {
  const { value, error } = step4Schema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const userId = req.user.id;
  await ensureStepUnlocked(userId, 3);

  const experienceLevel = deriveExperienceLevel(value);

  const client = await db.getClient();

  try {
    await client.query('BEGIN');

    // ✅ ปรับ SQL Query ให้ตรงกับ step4Schema ใหม่ (hasRunBefore, isCurrentlyRunning, weeksRunning, longestDistanceKm)
    await client.query(
      `INSERT INTO user_running_history
         (user_id, has_run_before, is_currently_running, weeks_running, longest_distance_km)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_id) DO UPDATE SET
         has_run_before = EXCLUDED.has_run_before,
         is_currently_running = EXCLUDED.is_currently_running,
         weeks_running = EXCLUDED.weeks_running,
         longest_distance_km = EXCLUDED.longest_distance_km`,
      [
        userId,
        value.hasRunBefore,
        value.isCurrentlyRunning,
        value.weeksRunning ?? null,
        value.longestDistanceKm ?? null,
      ]
    );

    // sync running_experience_level กลับไปที่ user_basic_info
    // ใช้ UPDATE ธรรมดา เพราะ ensureStepUnlocked การันตีแล้วว่า step1 ทำไปแล้ว จึงมี row แน่นอน
    const updateResult = await client.query(
      `UPDATE user_basic_info
         SET running_experience_level = $2
       WHERE user_id = $1`,
      [userId, experienceLevel]
    );

    if (updateResult.rowCount === 0) {
      // เผื่อกรณี edge case ที่ row หายไปจริงๆ
      throw new ApiError(400, 'ไม่พบข้อมูลพื้นฐานผู้ใช้ กรุณาทำ Step 1 ก่อน');
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  await advanceStep(userId, 4, true);

  res.status(200).json({
    success: true,
    message: 'บันทึกประวัติการวิ่งสำเร็จ — Onboarding เสร็จสมบูรณ์',
    data: { step: 4, onboardingCompleted: true, runningExperienceLevel: experienceLevel },
  });
});

module.exports = { getStatus, saveStep1, saveStep2, saveStep3, saveStep4 };