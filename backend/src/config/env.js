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
  clientUrl: process.env.CLIENT_URL || '*',

  databaseUrl: required('DATABASE_URL'),
  dbSsl: process.env.DB_SSL === 'true',

  jwt: {
    accessSecret: required('JWT_ACCESS_SECRET'),
    refreshSecret: required('JWT_REFRESH_SECRET'),
    accessExpiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '15m',
    refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',
  },

  otp: {
    length: parseInt(process.env.OTP_LENGTH || '6', 10),
    expiresMinutes: parseInt(process.env.OTP_EXPIRES_MINUTES || '5', 10),
    maxAttempts: parseInt(process.env.OTP_MAX_ATTEMPTS || '5', 10),
    resendCooldownSeconds: parseInt(process.env.OTP_RESEND_COOLDOWN_SECONDS || '60', 10),
  },

  smtp: {
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT || '587', 10),
    secure: process.env.SMTP_SECURE === 'true',
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
    fromName: process.env.SMTP_FROM_NAME || 'Pacegasus',
    fromEmail: process.env.SMTP_FROM_EMAIL,
  },

  google: {
    clientId: process.env.GOOGLE_CLIENT_ID,
  },
};
