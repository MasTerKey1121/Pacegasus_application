// ============================================================
// wellnessCheckinController.js
// วางที่: src/controllers/wellnessCheckinController.js
// สมมติฐาน: req.user.id คือ user_id ของผู้ใช้ที่ login (ตั้งโดย requireAuth เหมือน onboardingController)
// ============================================================

const wellnessCheckinService = require('../services/wellnessCheckinService');
const { wellnessCheckinSchema } = require('../utils/wellnessCheckinValidator');

/**
 * GET /wellness-checkin/today
 * เช็คสถานะว่าวันนี้ทำ check-in แล้วหรือยัง
 */
async function getTodayStatus(req, res) {
    try {
        const result = await wellnessCheckinService.getTodayStatus(req.user.id);
        return res.status(200).json({ success: true, data: result });
    } catch (err) {
        console.error('[wellnessCheckin] getTodayStatus error:', err);
        return res.status(500).json({ success: false, message: 'ไม่สามารถดึงสถานะ Wellness Check-in ได้' });
    }
}

/**
 * POST /wellness-checkin
 * สร้าง record ใหม่ของวันนี้
 */
async function createCheckin(req, res) {
    const { error, value } = wellnessCheckinSchema.validate(req.body, { abortEarly: false });
    if (error) {
        return res.status(400).json({
            success: false,
            message: 'ข้อมูลไม่ถูกต้อง',
            errors: error.details.map((d) => d.message),
        });
    }

    try {
        const record = await wellnessCheckinService.createCheckin(req.user.id, value);
        return res.status(201).json({ success: true, data: { status: 'done', record } });
    } catch (err) {
        if (err.code === 'ALREADY_CHECKED_IN') {
            return res.status(409).json({ success: false, message: err.message });
        }
        console.error('[wellnessCheckin] createCheckin error:', err);
        return res.status(500).json({ success: false, message: 'ไม่สามารถบันทึก Wellness Check-in ได้' });
    }
}

/**
 * PUT /wellness-checkin
 * แก้ไข record ของวันนี้
 */
async function updateCheckin(req, res) {
    const { error, value } = wellnessCheckinSchema.validate(req.body, { abortEarly: false });
    if (error) {
        return res.status(400).json({
            success: false,
            message: 'ข้อมูลไม่ถูกต้อง',
            errors: error.details.map((d) => d.message),
        });
    }

    try {
        const record = await wellnessCheckinService.updateCheckin(req.user.id, value);
        return res.status(200).json({ success: true, data: { status: 'done', record } });
    } catch (err) {
        if (err.code === 'NOT_FOUND') {
            return res.status(404).json({ success: false, message: err.message });
        }
        console.error('[wellnessCheckin] updateCheckin error:', err);
        return res.status(500).json({ success: false, message: 'ไม่สามารถแก้ไข Wellness Check-in ได้' });
    }
}

/**
 * GET /wellness-checkin/history?days=30
 * ดึงประวัติย้อนหลัง
 */
async function getHistory(req, res) {
    const days = Number.parseInt(req.query.days, 10) || 30;

    try {
        const records = await wellnessCheckinService.getHistory(req.user.id, days);
        return res.status(200).json({ success: true, data: { records } });
    } catch (err) {
        console.error('[wellnessCheckin] getHistory error:', err);
        return res.status(500).json({ success: false, message: 'ไม่สามารถดึงประวัติ Wellness Check-in ได้' });
    }
}

module.exports = { getTodayStatus, createCheckin, updateCheckin, getHistory };