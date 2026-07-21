const jwt = require('jsonwebtoken');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');

// Verifies the "Authorization: Bearer <accessToken>" header and attaches req.user
function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return next(new ApiError(401, 'Missing or invalid Authorization header'));
  }

  try {
    const payload = jwt.verify(token, env.jwt.accessSecret);
    req.user = { id: payload.sub, email: payload.email, role: payload.role };
    return next();
  } catch (err) {
    return next(new ApiError(401, 'Access token is invalid or expired'));
  }
}

module.exports = { requireAuth };
