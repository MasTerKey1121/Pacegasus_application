const { randomBytes } = require('node:crypto');
const db = require('../config/db');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');
const supabaseOtpService = require('./supabaseOtpService');

// Local reference returned to the app; Supabase's email contains only the OTP.
function generateOtpRef(length = 6) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I to avoid confusion
  let ref = '';
  for (let i = 0; i < length; i += 1) {
    ref += chars[Math.floor(Math.random() * chars.length)];
  }
  return ref;
}

/**
 * Requests a Supabase Auth OTP and tracks the request reference locally.
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

  const otpRef = generateOtpRef();
  const expiresAt = new Date(Date.now() + env.otp.expiresMinutes * 60 * 1000);

  // Keep the legacy non-null otp_hash column populated; Supabase owns the actual code.
  const { rows } = await db.query(
    `INSERT INTO otp_codes (email, otp_hash, otp_ref, purpose, max_attempts, expires_at)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id`,
    [email, randomBytes(32).toString('hex'), otpRef, purpose, env.otp.maxAttempts, expiresAt]
  );

  try {
    await supabaseOtpService.sendOtp(email);
  } catch (error) {
    await db.query(`DELETE FROM otp_codes WHERE id = $1`, [rows[0].id]);
    throw error;
  }

  await db.query(
    `UPDATE otp_codes SET is_used = TRUE WHERE email = $1 AND id <> $2 AND is_used = FALSE`,
    [email, rows[0].id]
  );

  return { expiresAt, expiresInMinutes: env.otp.expiresMinutes, otpRef };
}

/**
 * Checks the local request limits, then lets Supabase Auth verify the code.
 */
async function verifyOtp(email, otp, otpRef) {
  const { rows } = await db.query(
    `SELECT id, attempts, max_attempts, expires_at
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

  try {
    await supabaseOtpService.verifyOtp(email, otp);
  } catch (error) {
    if (error.statusCode === 400) {
      await db.query(`UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1`, [record.id]);
    }
    throw error;
  }

  await db.query(`UPDATE otp_codes SET is_used = TRUE WHERE id = $1`, [record.id]);

  return true;
}

module.exports = { requestOtp, verifyOtp };
