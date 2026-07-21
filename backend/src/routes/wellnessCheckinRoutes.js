// ============================================================
// wellnessCheckinRoutes.js
// วางที่: src/routes/wellnessCheckinRoutes.js
// อ้างอิง pattern จาก src/routes/onboardingRoutes.js (ยืนยันแล้ว)
// mount ผ่าน src/routes/index.js: router.use('/wellness-checkin', wellnessCheckinRoutes)
// ============================================================

const express = require('express');
const wellnessCheckinController = require('../controllers/wellnessCheckinController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

router.use(requireAuth);

router.get('/today', wellnessCheckinController.getTodayStatus);
router.post('/', wellnessCheckinController.createCheckin);
router.put('/', wellnessCheckinController.updateCheckin);
router.get('/history', wellnessCheckinController.getHistory);

module.exports = router;