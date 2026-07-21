const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const ms = require('./msParser');
const db = require('../config/db');
const env = require('../config/env');

function signAccessToken(user) {
  return jwt.sign(
    { sub: user.id, email: user.email, role: user.role },
    env.jwt.accessSecret,
    { expiresIn: env.jwt.accessExpiresIn }
  );
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Issues a new opaque refresh token, stores its hash in the DB, and returns
 * the raw token to send to the client (raw value is never stored).
 */
async function issueRefreshToken(userId, meta = {}) {
  const rawToken = crypto.randomBytes(48).toString('hex');
  const tokenHash = hashToken(rawToken);
  const expiresAt = new Date(Date.now() + ms(env.jwt.refreshExpiresIn));

  await db.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, device_info, ip_address, expires_at)
     VALUES ($1, $2, $3, $4, $5)`,
    [userId, tokenHash, meta.deviceInfo || null, meta.ipAddress || null, expiresAt]
  );

  return rawToken;
}

async function rotateRefreshToken(rawToken, meta = {}) {
  const tokenHash = hashToken(rawToken);

  const { rows } = await db.query(
    `SELECT id, user_id, revoked, expires_at FROM refresh_tokens WHERE token_hash = $1`,
    [tokenHash]
  );

  if (rows.length === 0) return null;
  const record = rows[0];

  if (record.revoked || new Date(record.expires_at).getTime() < Date.now()) {
    return null;
  }

  // Revoke the old token (rotation) and issue a new one
  await db.query(`UPDATE refresh_tokens SET revoked = TRUE WHERE id = $1`, [record.id]);
  const newToken = await issueRefreshToken(record.user_id, meta);

  return { userId: record.user_id, refreshToken: newToken };
}

async function revokeRefreshToken(rawToken) {
  const tokenHash = hashToken(rawToken);
  await db.query(`UPDATE refresh_tokens SET revoked = TRUE WHERE token_hash = $1`, [tokenHash]);
}

module.exports = {
  signAccessToken,
  issueRefreshToken,
  rotateRefreshToken,
  revokeRefreshToken,
};
