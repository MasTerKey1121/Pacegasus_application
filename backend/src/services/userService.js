const fs = require('fs/promises');
const path = require('path');
const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const { AVATAR_DIR } = require('../middleware/uploadAvatar');

const AVATAR_URL_PREFIX = '/uploads/avatars/';

function serializeUser(user) {
  return {
    id: user.id,
    uid: user.uid,
    email: user.email,
    emailVerified: user.email_verified,
    displayName: user.display_name,
    avatarUrl: user.avatar_url,
    role: user.role,
    onboardingCompleted: user.onboarding_completed,
    onboardingStep: user.onboarding_step,
    createdAt: user.created_at,
    updatedAt: user.updated_at,
  };
}

async function findActiveUser(userId) {
  const { rows } = await db.query(`SELECT * FROM users WHERE id = $1 AND status = 'active'`, [userId]);
  if (rows.length === 0) throw new ApiError(404, 'ไม่พบผู้ใช้งาน');
  return rows[0];
}

// Deletes the file behind a locally-hosted avatar URL; external URLs (e.g. Google) are left alone.
async function removeLocalAvatarFile(avatarUrl) {
  if (!avatarUrl) return;
  let pathname;
  try {
    pathname = new URL(avatarUrl, 'http://placeholder').pathname;
  } catch (e) {
    return;
  }
  if (!pathname.startsWith(AVATAR_URL_PREFIX)) return;
  const file = path.join(AVATAR_DIR, path.basename(pathname));
  await fs.unlink(file).catch(() => {});
}

async function getProfile(userId) {
  return serializeUser(await findActiveUser(userId));
}

const BASIC_INFO_COLUMNS = {
  dateOfBirth: 'date_of_birth',
  gender: 'gender',
  heightCm: 'height_cm',
  weightKg: 'weight_kg',
  timezone: 'timezone',
};

// Partial update: only fields present in `changes` are touched.
async function updateProfile(userId, changes) {
  await findActiveUser(userId);

  const basicSets = [];
  const basicValues = [];
  Object.entries(BASIC_INFO_COLUMNS).forEach(([key, column]) => {
    if (changes[key] !== undefined) {
      basicValues.push(changes[key]);
      basicSets.push(`${column} = $${basicValues.length + 1}`);
    }
  });

  if (basicSets.length > 0) {
    const { rowCount } = await db.query(
      `UPDATE user_basic_info SET ${basicSets.join(', ')} WHERE user_id = $1`,
      [userId, ...basicValues]
    );
    if (rowCount === 0) throw new ApiError(409, 'กรุณากรอกข้อมูลพื้นฐาน (onboarding ขั้นตอนที่ 1) ก่อน');
  }

  if (changes.displayName !== undefined) {
    await db.query(`UPDATE users SET display_name = $2 WHERE id = $1`, [userId, changes.displayName]);
  }

  return getProfile(userId);
}

async function setAvatar(userId, avatarUrl) {
  const user = await findActiveUser(userId);
  const { rows } = await db.query(`UPDATE users SET avatar_url = $2 WHERE id = $1 RETURNING *`, [userId, avatarUrl]);
  await removeLocalAvatarFile(user.avatar_url);
  return serializeUser(rows[0]);
}

async function deleteAvatar(userId) {
  const user = await findActiveUser(userId);
  const { rows } = await db.query(`UPDATE users SET avatar_url = NULL WHERE id = $1 RETURNING *`, [userId]);
  await removeLocalAvatarFile(user.avatar_url);
  return serializeUser(rows[0]);
}

module.exports = {
  AVATAR_URL_PREFIX,
  serializeUser,
  getProfile,
  updateProfile,
  setAvatar,
  deleteAvatar,
};
