const nodemailer = require('nodemailer');
const env = require('../config/env');

let transporter = null;

function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: env.smtp.host,
      port: env.smtp.port,
      secure: env.smtp.secure, // true for port 465, false for 587/25
      auth: env.smtp.user
        ? {
            user: env.smtp.user,
            pass: env.smtp.pass,
          }
        : undefined,
    });
  }
  return transporter;
}

/**
 * Sends a 6-digit OTP code to the given email address.
 */
async function sendOtpEmail(email, otp, purpose = 'login') {
  const subject =
    purpose === 'register'
      ? 'ยืนยันการสมัครสมาชิก Pacegasus'
      : 'รหัสยืนยันการเข้าสู่ระบบ Pacegasus';

  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 420px; margin: 0 auto;">
      <h2 style="color:#2563eb;">Pacegasus</h2>
      <p>รหัส OTP ของคุณคือ:</p>
      <p style="font-size: 32px; font-weight: bold; letter-spacing: 8px;">${otp}</p>
      <p>รหัสนี้จะหมดอายุใน ${env.otp.expiresMinutes} นาที</p>
      <p style="color:#6b7280; font-size: 12px;">หากคุณไม่ได้ทำรายการนี้ กรุณาเพิกเฉยต่ออีเมลฉบับนี้</p>
    </div>
  `;

  await getTransporter().sendMail({
    from: `"${env.smtp.fromName}" <${env.smtp.fromEmail}>`,
    to: email,
    subject,
    html,
    text: `รหัส OTP ของคุณคือ ${otp} (หมดอายุใน ${env.otp.expiresMinutes} นาที)`,
  });
}

module.exports = { sendOtpEmail, getTransporter };
