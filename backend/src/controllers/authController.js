const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const asyncHandler = require('../utils/asyncHandler');
const otpService = require('../services/otpService');
const tokenService = require('../services/tokenService');
const googleAuthService = require('../services/googleAuthService');
const {
  requestOtpSchema,
  verifyOtpSchema,
  googleAuthSchema,
  refreshSchema,
} = require('../utils/validators');

function serializeUser(user) {
  return {
    id: user.id,
    email: user.email,
    emailVerified: user.email_verified,
    displayName: user.display_name,
    avatarUrl: user.avatar_url,
    role: user.role,
    onboardingCompleted: user.onboarding_completed,
    onboardingStep: user.onboarding_step,
    createdAt: user.created_at,
  };
}

async function findUserByEmail(email) {
  const { rows } = await db.query(`SELECT * FROM users WHERE email = $1`, [email]);
  return rows[0] || null;
}

async function findUserById(id) {
  const { rows } = await db.query(`SELECT * FROM users WHERE id = $1`, [id]);
  return rows[0] || null;
}

async function createUser(email, extra = {}) {
  const { rows } = await db.query(
    `INSERT INTO users (email, email_verified, display_name, avatar_url)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [email, extra.emailVerified || false, extra.displayName || null, extra.avatarUrl || null]
  );
  return rows[0];
}

async function linkProvider(userId, provider, providerUserId = null) {
  await db.query(
    `INSERT INTO user_auth_providers (user_id, provider, provider_user_id)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, provider) DO NOTHING`,
    [userId, provider, providerUserId]
  );
}

async function issueSession(user, req) {
  const accessToken = tokenService.signAccessToken(user);
  const refreshToken = await tokenService.issueRefreshToken(user.id, {
    deviceInfo: req.headers['user-agent'],
    ipAddress: req.ip,
  });
  await db.query(`UPDATE users SET last_login_at = now() WHERE id = $1`, [user.id]);
  return { accessToken, refreshToken };
}

// POST /api/auth/otp/request
const requestOtp = asyncHandler(async (req, res) => {
  const { value, error } = requestOtpSchema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const { email, purpose } = value;

  const existingUser = await findUserByEmail(email);
  if (purpose === 'register' && existingUser && existingUser.email_verified) {
    throw new ApiError(409, 'อีเมลนี้มีผู้ใช้งานแล้ว กรุณาเข้าสู่ระบบแทน');
  }
  if (purpose === 'login' && !existingUser) {
    throw new ApiError(404, 'ไม่พบบัญชีผู้ใช้สำหรับอีเมลนี้ กรุณาสมัครสมาชิกก่อน');
  }

  // Ensure a (possibly unverified) user row exists so the profile can be attached
  if (!existingUser) {
    await createUser(email);
  }

  const result = await otpService.requestOtp(email, purpose);

  res.status(200).json({
    success: true,
    message: 'ส่งรหัส OTP ไปยังอีเมลของคุณแล้ว',
    data: { email, expiresInMinutes: result.expiresInMinutes },
  });
});

// POST /api/auth/otp/verify
const verifyOtp = asyncHandler(async (req, res) => {
  const { value, error } = verifyOtpSchema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const { email, otp, displayName } = value;

  await otpService.verifyOtp(email, otp);

  let user = await findUserByEmail(email);
  if (!user) {
    user = await createUser(email, { emailVerified: true, displayName });
  }

  if (!user.email_verified || (displayName && !user.display_name)) {
    const { rows } = await db.query(
      `UPDATE users
       SET email_verified = TRUE,
           display_name = COALESCE($2, display_name)
       WHERE id = $1
       RETURNING *`,
      [user.id, displayName || null]
    );
    user = rows[0];
  }

  await linkProvider(user.id, 'email', null);

  const { accessToken, refreshToken } = await issueSession(user, req);

  res.status(200).json({
    success: true,
    message: 'เข้าสู่ระบบสำเร็จ',
    data: { user: serializeUser(user), accessToken, refreshToken },
  });
});

// POST /api/auth/google
const googleAuth = asyncHandler(async (req, res) => {
  const { value, error } = googleAuthSchema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const profile = await googleAuthService.verifyGoogleIdToken(value.idToken);

  let user = await findUserByEmail(profile.email);
  if (!user) {
    user = await createUser(profile.email, {
      emailVerified: profile.emailVerified,
      displayName: profile.displayName,
      avatarUrl: profile.avatarUrl,
    });
  } else if (!user.avatar_url && profile.avatarUrl) {
    const { rows } = await db.query(
      `UPDATE users SET avatar_url = $2, email_verified = TRUE WHERE id = $1 RETURNING *`,
      [user.id, profile.avatarUrl]
    );
    user = rows[0];
  }

  await linkProvider(user.id, 'google', profile.googleId);

  const { accessToken, refreshToken } = await issueSession(user, req);

  res.status(200).json({
    success: true,
    message: 'เข้าสู่ระบบด้วย Google สำเร็จ',
    data: { user: serializeUser(user), accessToken, refreshToken },
  });
});

// POST /api/auth/refresh
const refresh = asyncHandler(async (req, res) => {
  const { value, error } = refreshSchema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const rotated = await tokenService.rotateRefreshToken(value.refreshToken, {
    deviceInfo: req.headers['user-agent'],
    ipAddress: req.ip,
  });

  if (!rotated) throw new ApiError(401, 'Refresh token ไม่ถูกต้องหรือหมดอายุ');

  const user = await findUserById(rotated.userId);
  if (!user) throw new ApiError(401, 'ไม่พบผู้ใช้งาน');

  const accessToken = tokenService.signAccessToken(user);

  res.status(200).json({
    success: true,
    data: { accessToken, refreshToken: rotated.refreshToken },
  });
});

// POST /api/auth/logout
const logout = asyncHandler(async (req, res) => {
  const { value, error } = refreshSchema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  await tokenService.revokeRefreshToken(value.refreshToken);

  res.status(200).json({ success: true, message: 'ออกจากระบบสำเร็จ' });
});

// GET /api/auth/me
const me = asyncHandler(async (req, res) => {
  const user = await findUserById(req.user.id);
  if (!user) throw new ApiError(404, 'ไม่พบผู้ใช้งาน');

  res.status(200).json({ success: true, data: { user: serializeUser(user) } });
});

module.exports = { requestOtp, verifyOtp, googleAuth, refresh, logout, me, serializeUser, findUserById };
