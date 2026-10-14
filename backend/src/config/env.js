require('dotenv').config();

function required(name, fallback = undefined) {
  const value = process.env[name] ?? fallback;
  if (value === undefined) {
    // eslint-disable-next-line no-console
    console.warn(`[env] Warning: ${name} is not set`);
  }
  return value;
}

module.exports = {
  port: parseInt(process.env.PORT || '4000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  // Public origin used to build absolute URLs for uploaded files (defaults to the request host)
  publicBaseUrl: process.env.PUBLIC_BASE_URL,
  clientUrl: process.env.CLIENT_URL || '*',

  databaseUrl: required('DATABASE_URL'),
  dbSsl: process.env.DB_SSL === 'true',
  supabase: {
    url: process.env.SUPABASE_URL,
    anonKey: process.env.SUPABASE_ANON_KEY,
  },

  jwt: {
    accessSecret: required('JWT_ACCESS_SECRET'),
    refreshSecret: required('JWT_REFRESH_SECRET'),
    accessExpiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '15m',
    refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',
  },

  otp: {
    expiresMinutes: parseInt(process.env.OTP_EXPIRES_MINUTES || '5', 10),
    maxAttempts: parseInt(process.env.OTP_MAX_ATTEMPTS || '5', 10),
    resendCooldownSeconds: parseInt(process.env.OTP_RESEND_COOLDOWN_SECONDS || '60', 10),
  },

  google: {
    clientId: process.env.GOOGLE_CLIENT_ID,
    // Web/Android/iOS ใช้ client id คนละตัว — ใส่เพิ่มได้คั่นด้วย comma
    clientIds: [process.env.GOOGLE_CLIENT_ID, ...(process.env.GOOGLE_CLIENT_IDS || '').split(',')]
      .map((id) => (id || '').trim())
      .filter(Boolean),
  },
};
