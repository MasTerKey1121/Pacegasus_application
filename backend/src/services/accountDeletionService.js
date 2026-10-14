const db = require('../config/db');
const ApiError = require('../utils/ApiError');

// Remove identity and email-based OTPs together so old codes cannot be used
// against a new account registered with the same email.
async function deleteAccount(userId) {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query('SELECT email FROM users WHERE id = $1 FOR UPDATE', [userId]);
    if (!rows.length) throw new ApiError(404, 'ไม่พบผู้ใช้งาน');
    const email = rows[0].email.split('::deleted::')[0];
    await client.query('DELETE FROM otp_codes WHERE LOWER(email) = LOWER($1)', [email]);
    await client.query('DELETE FROM refresh_tokens WHERE user_id = $1', [userId]);
    await client.query('DELETE FROM user_auth_providers WHERE user_id = $1', [userId]);
    // User-owned profiles, running history and game data use ON DELETE CASCADE.
    await client.query('DELETE FROM users WHERE id = $1', [userId]);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = { deleteAccount };
