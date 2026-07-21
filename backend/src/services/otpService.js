const bcrypt = require('bcryptjs');
const db = require('../config/db');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');
const { sendOtpEmail } = require('./emailService');

function generateOtpCode(length) {
  const digits = '0123456789';
  let code = '';
  for (let i = 0; i < length; i += 1) {
    code += digits[Math.floor(Math.random() * digits.length)];
  }
  return code;
}

// Generates a short reference code (e.g. "A1B2C3") shown to the user
// alongside the OTP email, so they can confirm which request is which.
function generateOtpRef(length = 6) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I to avoid confusion
  let ref = '';
  for (let i = 0; i < length; i += 1) {
    ref += chars[Math.floor(Math.random() * chars.length)];
  }
  return ref;
}

/**
 * Creates a new OTP for the given email, stores its hash, and emails it.
 * Enforces a resend cooldown to prevent spamming the mailbox.
 */
async function requestOtp(email, purpose = 'login') {
  const cooldown = env.otp.resendCooldownSeconds;

  const { rows: recent } = await db.query(
    `SELECT created_at FROM otp_codes
     WHERE email = $1
     ORDER BY created_at DESC
     LIMIT 1`,
    [email]
  );

  if (recent.length > 0) {
    const secondsSinceLast = (Date.now() - new Date(recent[0].created_at).getTime()) / 1000;
    if (secondsSinceLast < cooldown) {
      throw new ApiError(
        429,
        `กรุณารอ ${Math.ceil(cooldown - secondsSinceLast)} วินาทีก่อนขอรหัส OTP ใหม่`
      );
    }
  }

  const otp = generateOtpCode(env.otp.length);
  const otpRef = generateOtpRef();
  const otpHash = await bcrypt.hash(otp, 10);
  const expiresAt = new Date(Date.now() + env.otp.expiresMinutes * 60 * 1000);

  await db.query(
    `INSERT INTO otp_codes (email, otp_hash, otp_ref, purpose, max_attempts, expires_at)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [email, otpHash, otpRef, purpose, env.otp.maxAttempts, expiresAt]
  );

  await sendOtpEmail(email, otp, purpose, otpRef);

  return { expiresAt, expiresInMinutes: env.otp.expiresMinutes, otpRef };
}

/**
 * Verifies the OTP for the given email + otpRef. Throws ApiError on failure.
 * Marks the code as used on success so it cannot be replayed.
 */
async function verifyOtp(email, otp, otpRef) {
  const { rows } = await db.query(
    `SELECT id, otp_hash, attempts, max_attempts, is_used, expires_at
     FROM otp_codes
     WHERE email = $1 AND otp_ref = $2 AND is_used = FALSE
     ORDER BY created_at DESC
     LIMIT 1`,
    [email, otpRef]
  );

  if (rows.length === 0) {
    throw new ApiError(400, 'ไม่พบคำขอ OTP กรุณาขอรหัสใหม่');
  }

  const record = rows[0];

  if (new Date(record.expires_at).getTime() < Date.now()) {
    throw new ApiError(400, 'รหัส OTP หมดอายุแล้ว กรุณาขอรหัสใหม่');
  }

  if (record.attempts >= record.max_attempts) {
    throw new ApiError(429, 'กรอกรหัสผิดเกินจำนวนครั้งที่กำหนด กรุณาขอรหัสใหม่');
  }

  const isMatch = await bcrypt.compare(otp, record.otp_hash);

  if (!isMatch) {
    await db.query(`UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1`, [record.id]);
    throw new ApiError(400, 'รหัส OTP ไม่ถูกต้อง');
  }

  await db.query(`UPDATE otp_codes SET is_used = TRUE WHERE id = $1`, [record.id]);

  return true;
}

module.exports = { requestOtp, verifyOtp };