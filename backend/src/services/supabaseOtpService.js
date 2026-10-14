const { createClient } = require('@supabase/supabase-js');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');

let client;

function getClient() {
  if (!env.supabase.url || !env.supabase.anonKey) {
    throw new ApiError(503, 'ยังไม่ได้ตั้งค่า Supabase Auth สำหรับส่ง OTP');
  }
  if (!client) {
    client = createClient(env.supabase.url, env.supabase.anonKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    });
  }
  return client;
}

function providerError(error, fallbackMessage, invalidCode = false) {
  if (error.status === 429) return new ApiError(429, 'ขอรหัส OTP บ่อยเกินไป กรุณาลองใหม่ภายหลัง');
  if (invalidCode && error.status >= 400 && error.status < 500) {
    return new ApiError(400, fallbackMessage);
  }
  return new ApiError(502, fallbackMessage);
}

async function sendOtp(email) {
  const { error } = await getClient().auth.signInWithOtp({
    email,
    // The app decides whether registration is allowed before this call.
    // Existing app users might not have a matching Supabase Auth user yet.
    options: { shouldCreateUser: true },
  });
  if (error) throw providerError(error, 'Supabase ส่งรหัส OTP ไม่สำเร็จ');
}

async function verifyOtp(email, otp) {
  const { data, error } = await getClient().auth.verifyOtp({
    email,
    token: otp,
    type: 'email',
  });
  if (error) throw providerError(error, 'รหัส OTP ไม่ถูกต้องหรือหมดอายุ', true);
  if (!data?.user || data.user.email?.toLowerCase() !== email.toLowerCase()) {
    throw new ApiError(400, 'ยืนยันอีเมลไม่สำเร็จ');
  }
}

module.exports = { sendOtp, verifyOtp };
