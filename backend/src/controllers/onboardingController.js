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

// PUT /api/onboarding/step1  (basic info)
const saveStep1 = asyncHandler(async (req, res) => {
  const { value, error } = step1Schema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const userId = req.user.id;

  await db.query(
    `INSERT INTO user_basic_info
       (user_id, date_of_birth, gender, height_cm, weight_kg,
        running_experience_level, weekly_distance_km, running_days_per_week, timezone)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     ON CONFLICT (user_id) DO UPDATE SET
       date_of_birth = EXCLUDED.date_of_birth,
       gender = EXCLUDED.gender,
       height_cm = EXCLUDED.height_cm,
       weight_kg = EXCLUDED.weight_kg,
       running_experience_level = EXCLUDED.running_experience_level,
       weekly_distance_km = EXCLUDED.weekly_distance_km,
       running_days_per_week = EXCLUDED.running_days_per_week,
       timezone = EXCLUDED.timezone`,
    [
      userId,
      value.dateOfBirth,
      value.gender,
      value.heightCm,
      value.weightKg,
      value.runningExperienceLevel,
      value.weeklyDistanceKm,
      value.runningDaysPerWeek,
      value.timezone ?? 'Asia/Bangkok',
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
  const client = await db.getClient();

  try {
    await client.query('BEGIN');

    await client.query(
      `INSERT INTO user_injury_summary (user_id, has_injury_history)
       VALUES ($1, $2)
       ON CONFLICT (user_id) DO UPDATE SET has_injury_history = EXCLUDED.has_injury_history`,
      [userId, value.hasInjuryHistory]
    );

    // Replace the injury list with what was submitted (simple + predictable for onboarding)
    await client.query(`DELETE FROM user_injuries WHERE user_id = $1`, [userId]);

    if (value.hasInjuryHistory && value.injuries.length > 0) {
      for (const injury of value.injuries) {
        await client.query(
          `INSERT INTO user_injuries
             (user_id, body_part, injury_type, severity, is_current, occurred_at, notes)
           VALUES ($1,$2,$3,$4,$5,$6,$7)`,
          [
            userId,
            injury.bodyPart,
            injury.injuryType || null,
            injury.severity ?? null,
            injury.isCurrent,
            injury.occurredAt || null,
            injury.notes || null,
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
  const client = await db.getClient();

  try {
    await client.query('BEGIN');
    await client.query(`DELETE FROM user_goals WHERE user_id = $1`, [userId]);

    for (const goal of value.goals) {
      await client.query(
        `INSERT INTO user_goals
           (user_id, goal_type, target_distance_km, target_date, target_pace_sec_per_km, is_primary)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [
          userId,
          goal.goalType,
          goal.targetDistanceKm ?? null,
          goal.targetDate || null,
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

// PUT /api/onboarding/step4  (running history) -> marks onboarding complete
const saveStep4 = asyncHandler(async (req, res) => {
  const { value, error } = step4Schema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const userId = req.user.id;

  await db.query(
    `INSERT INTO user_running_history
       (user_id, has_run_before, years_running, best_5k_seconds, best_10k_seconds,
        best_half_marathon_seconds, best_marathon_seconds, preferred_environment,
        typical_training_time, connected_strava)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
     ON CONFLICT (user_id) DO UPDATE SET
       has_run_before = EXCLUDED.has_run_before,
       years_running = EXCLUDED.years_running,
       best_5k_seconds = EXCLUDED.best_5k_seconds,
       best_10k_seconds = EXCLUDED.best_10k_seconds,
       best_half_marathon_seconds = EXCLUDED.best_half_marathon_seconds,
       best_marathon_seconds = EXCLUDED.best_marathon_seconds,
       preferred_environment = EXCLUDED.preferred_environment,
       typical_training_time = EXCLUDED.typical_training_time,
       connected_strava = EXCLUDED.connected_strava`,
    [
      userId,
      value.hasRunBefore,
      value.yearsRunning ?? null,
      value.best5kSeconds ?? null,
      value.best10kSeconds ?? null,
      value.bestHalfMarathonSeconds ?? null,
      value.bestMarathonSeconds ?? null,
      value.preferredEnvironment || null,
      value.typicalTrainingTime || null,
      value.connectedStrava,
    ]
  );

  await advanceStep(userId, 4, true);

  res.status(200).json({
    success: true,
    message: 'บันทึกประวัติการวิ่งสำเร็จ — Onboarding เสร็จสมบูรณ์',
    data: { step: 4, onboardingCompleted: true },
  });
});

module.exports = { getStatus, saveStep1, saveStep2, saveStep3, saveStep4 };
