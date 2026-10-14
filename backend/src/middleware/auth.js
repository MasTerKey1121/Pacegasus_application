const jwt = require('jsonwebtoken');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');
const db = require('../config/db');

// Verifies the "Authorization: Bearer <accessToken>" header and attaches req.user
async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return next(new ApiError(401, 'Missing or invalid Authorization header'));
  }

  let payload;
  try {
    payload = jwt.verify(token, env.jwt.accessSecret);
  } catch (err) {
    return next(new ApiError(401, 'Access token is invalid or expired'));
  }
  try {
    const { rows } = await db.query('SELECT id, status FROM users WHERE id = $1', [payload.sub]);
    if (!rows.length || rows[0].status !== 'active') {
      return next(new ApiError(401, 'บัญชีนี้ถูกลบหรือระงับการใช้งานแล้ว'));
    }
    req.user = { id: payload.sub, email: payload.email, role: payload.role };
    return next();
  } catch (err) {
    return next(err);
  }
}

module.exports = { requireAuth };
