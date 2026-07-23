const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const asyncHandler = require('../utils/asyncHandler');

// GET /api/users/me/full -> profile + all onboarding data, handy for the app's home screen
const getFullProfile = asyncHandler(async (req, res) => {
  const userId = req.user.id;

  const [{ rows: userRows }, { rows: basicRows }, { rows: injuryRows }, { rows: goalRows }, { rows: historyRows }] =
    await Promise.all([
      db.query(`SELECT * FROM users WHERE id = $1`, [userId]),
      db.query(`SELECT * FROM user_basic_info WHERE user_id = $1`, [userId]),
      db.query(
        `SELECT s.has_injury_history,
                COALESCE(json_agg(i.*) FILTER (WHERE i.id IS NOT NULL), '[]') AS injuries
         FROM user_injury_summary s
         LEFT JOIN user_injuries i ON i.user_id = s.user_id
         WHERE s.user_id = $1
         GROUP BY s.has_injury_history`,
        [userId]
      ),
      db.query(`SELECT * FROM user_goals WHERE user_id = $1 ORDER BY is_primary DESC, created_at`, [userId]),
      db.query(`SELECT * FROM user_running_history WHERE user_id = $1`, [userId]),
    ]);

  if (userRows.length === 0) throw new ApiError(404, 'ไม่พบผู้ใช้งาน');

  const user = userRows[0];

  res.status(200).json({
    success: true,
    data: {
      user: {
        id: user.id,
        email: user.email,
        displayName: user.display_name,
        avatarUrl: user.avatar_url,
        role: user.role,
        onboardingCompleted: user.onboarding_completed,
        onboardingStep: user.onboarding_step,
      },
      basicInfo: basicRows[0] || null,
      injury: injuryRows[0] || { has_injury_history: false, injuries: [] },
      goals: goalRows,
      runningHistory: historyRows[0] || null,
    },
  });
});


// DELETE /api/users/me -> soft delete บัญชีตัวเอง
const deleteUser = asyncHandler(async (req, res) => {
  const userId = req.user.id;

  // กันกรณีลบซ้ำ / user ไม่มีอยู่จริง / ถูกลบไปแล้ว
  const { rows: existingRows } = await db.query(
    `SELECT id, status FROM users WHERE id = $1`,
    [userId]
  );

  if (existingRows.length === 0) {
    throw new ApiError(404, 'ไม่พบผู้ใช้งาน');
  }

  if (existingRows[0].status === 'deleted' ) {
    throw new ApiError(400, 'บัญชีนี้ถูกลบไปแล้ว');
  }

  // เปลี่ยน email ให้ไม่ชนกับ unique constraint เวลามีคนสมัครใหม่ด้วย email เดิม
  // เก็บ email เดิมไว้แบบ mark ไม่ให้ query ปกติเจอ (ไม่กระทบข้อมูลจริง)
  const { rows } = await db.query(
    `UPDATE users
     SET status = 'deleted',
         email = email || '::deleted::' || id::text
     WHERE id = $1
     RETURNING id, status`,
    [userId]
  );

  // TODO: ถ้ามี refresh_tokens / sessions table ให้ revoke ตรงนี้ด้วย เช่น
  // await db.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [userId]);

  res.status(200).json({
    success: true,
    message: 'ลบบัญชีเรียบร้อยแล้ว',
    data: { id: rows[0].id, status: rows[0].status },
  });
});

module.exports = { getFullProfile, deleteUser };

