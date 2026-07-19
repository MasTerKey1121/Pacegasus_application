const express = require('express');
const rateLimit = require('express-rate-limit');
const authController = require('../controllers/authController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

// Basic brute-force protection on OTP endpoints
const otpRequestLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'ขอ OTP บ่อยเกินไป กรุณาลองใหม่ภายหลัง' },
});

const otpVerifyLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'พยายามยืนยัน OTP บ่อยเกินไป กรุณาลองใหม่ภายหลัง' },
});

router.post('/otp/request', otpRequestLimiter, authController.requestOtp);
router.post('/otp/verify', otpVerifyLimiter, authController.verifyOtp);
router.post('/google', authController.googleAuth);
router.post('/refresh', authController.refresh);
router.post('/logout', authController.logout);
router.get('/me', requireAuth, authController.me);

module.exports = router;
