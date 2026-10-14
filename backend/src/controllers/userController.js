const db = require('../config/db');
const accountDeletionService = require('../services/accountDeletionService');
const ApiError = require('../utils/ApiError');
const asyncHandler = require('../utils/asyncHandler');
const gameProgressService = require('../services/gameProgressService');
const profileService = require('../services/profileService');
const { uidSchema } = require('../utils/friendValidators');
const env = require('../config/env');
const userService = require('../services/userService');
const { updateProfileSchema } = require('../utils/validators');

// GET /api/users/me/full -> profile + all onboarding data, handy for the app's home screen
const getFullProfile = asyncHandler(async (req, res) => {
  const userId = req.user.id;

  const [{ rows: userRows }, { rows: basicRows }, { rows: injuryRows }, { rows: goalRows }, { rows: historyRows }, { rows: gameRows }] =
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
      db.query(`SELECT coin_balance, level, exp, exp_to_next FROM user_game_progress WHERE user_id = $1`, [userId]),
    ]);

  if (userRows.length === 0) throw new ApiError(404, 'ไม่พบผู้ใช้งาน');

  const user = userRows[0];

  res.status(200).json({
    success: true,
    data: {
      user: {
        id: user.id,
        uid: user.uid,
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
      gameProgress: gameRows[0]
        ? { coinBalance: gameRows[0].coin_balance, level: gameRows[0].level, exp: gameRows[0].exp, expToNext: gameRows[0].exp_to_next }
        : { coinBalance: 0, level: 1, exp: 0, expToNext: 200 },
    },
  });
});

const getGameProgress = asyncHandler(async (req, res) => {
  const progress = await gameProgressService.getProgress(req.user.id);
  res.status(200).json({ success: true, data: progress });
});


// DELETE /api/users/me -> permanently delete the account and its owned data.
const deleteUser = asyncHandler(async (req, res) => {
  await accountDeletionService.deleteAccount(req.user.id);
  res.status(200).json({
    success: true,
    message: 'ลบบัญชีเรียบร้อยแล้ว',
    data: { id: req.user.id, status: 'deleted' },
  });
});

// GET /api/users/profile/:uid — โปรไฟล์ผู้ใช้ใดก็ได้จาก UID (เพื่อน/คนอื่น/ตัวเอง)
const getProfileByUid = asyncHandler(async (req, res) => {
  const { value: uid, error } = uidSchema.validate(req.params.uid);
  if (error) throw new ApiError(400, 'UID ไม่ถูกต้อง', error.details.map(({ message }) => message));
  const profile = await profileService.getProfileByUid(req.user.id, uid);
  res.status(200).json({ success: true, data: profile });
});

// GET /api/users/me
const getMe = asyncHandler(async (req, res) => {
  const user = await userService.getProfile(req.user.id);
  res.status(200).json({ success: true, data: { user } });
});

// PATCH /api/users/me -> partial update of display name and basic info
const updateMe = asyncHandler(async (req, res) => {
  const { value, error } = updateProfileSchema.validate(req.body, { abortEarly: false });
  if (error) throw new ApiError(400, 'ข้อมูลไม่ถูกต้อง', error.details.map((d) => d.message));

  const user = await userService.updateProfile(req.user.id, value);
  res.status(200).json({ success: true, message: 'อัปเดตโปรไฟล์สำเร็จ', data: { user } });
});

// PUT /api/users/me/avatar (multipart/form-data, field "avatar") -> add or replace the profile picture
const uploadAvatar = asyncHandler(async (req, res) => {
  if (!req.file) throw new ApiError(400, 'กรุณาแนบไฟล์รูปใน field "avatar"');

  const baseUrl = (env.publicBaseUrl || `${req.protocol}://${req.get('host')}`).replace(/\/$/, '');
  const user = await userService.setAvatar(req.user.id, `${baseUrl}${userService.AVATAR_URL_PREFIX}${req.file.filename}`);
  res.status(200).json({ success: true, message: 'อัปโหลดรูปโปรไฟล์สำเร็จ', data: { user } });
});

// DELETE /api/users/me/avatar
const deleteAvatar = asyncHandler(async (req, res) => {
  const user = await userService.deleteAvatar(req.user.id);
  res.status(200).json({ success: true, message: 'ลบรูปโปรไฟล์สำเร็จ', data: { user } });
});

module.exports = {
  getProfileByUid,
  getFullProfile,
  getGameProgress,
  deleteUser,
  getMe,
  updateMe,
  uploadAvatar,
  deleteAvatar,
};
