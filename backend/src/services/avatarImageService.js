const { randomUUID } = require('node:crypto');
const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const { MAX_SIZE_BYTES } = require('../middleware/uploadAvatar');
const { serializeUser } = require('./userService');

function validateImage(file) {
  const bytes = file?.buffer;
  if (!Buffer.isBuffer(bytes) || !bytes.length || bytes.length > MAX_SIZE_BYTES) {
    throw new ApiError(400, 'ไฟล์รูปไม่ถูกต้องหรือมีขนาดเกิน 5 MB');
  }
  const png = bytes.length >= 24 &&
    bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
    bytes.toString('ascii', 12, 16) === 'IHDR';
  const jpg = bytes.length >= 4 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  const webp = bytes.length >= 20 && bytes.toString('ascii', 0, 4) === 'RIFF' &&
    bytes.toString('ascii', 8, 12) === 'WEBP';
  const contentType = png ? 'image/png' : jpg ? 'image/jpeg' : webp ? 'image/webp' : null;
  if (!contentType || contentType !== file.mimetype) {
    throw new ApiError(400, 'รองรับเฉพาะไฟล์รูป JPEG, PNG หรือ WebP');
  }
  return contentType;
}

async function saveAvatar(userId, file, baseUrl) {
  const contentType = validateImage(file);
  const id = randomUUID();
  const avatarUrl = `${baseUrl}/api/user-avatars/${id}`;
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `UPDATE users SET avatar_url = $2 WHERE id = $1 AND status = 'active' RETURNING *`,
      [userId, avatarUrl]
    );
    if (!rows[0]) throw new ApiError(404, 'ไม่พบผู้ใช้งาน');
    await client.query(
      `INSERT INTO avatar_images (id, user_id, content_type, image_data)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id) DO UPDATE SET id = EXCLUDED.id,
         content_type = EXCLUDED.content_type, image_data = EXCLUDED.image_data,
         updated_at = now()`,
      [id, userId, contentType, file.buffer]
    );
    await client.query('COMMIT');
    return serializeUser(rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function deleteAvatar(userId) {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `UPDATE users SET avatar_url = NULL WHERE id = $1 AND status = 'active' RETURNING *`,
      [userId]
    );
    if (!rows[0]) throw new ApiError(404, 'ไม่พบผู้ใช้งาน');
    await client.query('DELETE FROM avatar_images WHERE user_id = $1', [userId]);
    await client.query('COMMIT');
    return serializeUser(rows[0]);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function getAvatar(id) {
  const { rows } = await db.query(
    'SELECT content_type, image_data FROM avatar_images WHERE id = $1', [id]
  );
  if (!rows[0]) throw new ApiError(404, 'ไม่พบรูปโปรไฟล์');
  return rows[0];
}

module.exports = { validateImage, saveAvatar, deleteAvatar, getAvatar };
