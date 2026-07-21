// ============================================================
// wellnessCheckinService.js
// วางที่: src/services/wellnessCheckinService.js (สมมติฐาน — ยังไม่ยืนยันว่ามีโฟลเดอร์นี้จริง)
// สถานะ: informational only — ไม่ gate flow ใดๆ ในระบบ (ตามข้อสรุปที่ยืนยันแล้ว)
// ============================================================

const { pool } = require('../config/db'); // ตาม convention เดียวกับ migrate.js

/**
 * ตรวจสอบสถานะ check-in ของ "วันนี้" ว่าทำแล้วหรือยัง
 * @param {string} userId
 * @returns {{ status: 'done'|'not_done', record: object|null }}
 */
async function getTodayStatus(userId) {
    const { rows } = await pool.query(
        `SELECT checkin_id, checkin_date, sleep_quality, energy_level,
                muscle_soreness, stress_level, motivation, wellness_score,
                note, created_at, updated_at
         FROM daily_wellness_checkins
         WHERE user_id = $1 AND checkin_date = CURRENT_DATE`,
        [userId]
    );

    if (rows.length === 0) {
        return { status: 'not_done', record: null };
    }
    return { status: 'done', record: rows[0] };
}

/**
 * สร้าง record check-in ใหม่ของวันนี้ (ทำได้ 1 record/วัน)
 * @param {string} userId
 * @param {{sleepQuality:number, energyLevel:number, muscleSoreness:number, stressLevel:number, motivation:number, note?:string}} data
 */
async function createCheckin(userId, data) {
    const { sleepQuality, energyLevel, muscleSoreness, stressLevel, motivation, note } = data;

    try {
        const { rows } = await pool.query(
            `INSERT INTO daily_wellness_checkins
                (user_id, sleep_quality, energy_level, muscle_soreness, stress_level, motivation, note)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             RETURNING *`,
            [userId, sleepQuality, energyLevel, muscleSoreness, stressLevel, motivation, note || null]
        );
        return rows[0];
    } catch (err) {
        if (err.code === '23505') { // unique_violation: uq_wellness_checkin_user_date
            const dupError = new Error('ผู้ใช้ทำ Wellness Check-in ของวันนี้ไปแล้ว ใช้ updateCheckin แทน');
            dupError.code = 'ALREADY_CHECKED_IN';
            throw dupError;
        }
        throw err;
    }
}

/**
 * แก้ไข record check-in ของวันนี้ (ตามที่ผู้ใช้ระบุว่าต้อง "แก้ไขได้")
 * @param {string} userId
 * @param {{sleepQuality:number, energyLevel:number, muscleSoreness:number, stressLevel:number, motivation:number, note?:string}} data
 */
async function updateCheckin(userId, data) {
    const { sleepQuality, energyLevel, muscleSoreness, stressLevel, motivation, note } = data;

    const { rows } = await pool.query(
        `UPDATE daily_wellness_checkins
         SET sleep_quality   = $2,
             energy_level    = $3,
             muscle_soreness = $4,
             stress_level    = $5,
             motivation      = $6,
             note            = $7
         WHERE user_id = $1 AND checkin_date = CURRENT_DATE
         RETURNING *`,
        [userId, sleepQuality, energyLevel, muscleSoreness, stressLevel, motivation, note || null]
    );

    if (rows.length === 0) {
        const notFound = new Error('ยังไม่มี Check-in ของวันนี้ให้แก้ไข ใช้ createCheckin ก่อน');
        notFound.code = 'NOT_FOUND';
        throw notFound;
    }
    return rows[0];
}

/**
 * ดึงประวัติ check-in ย้อนหลัง N วัน (ใช้แสดงกราฟ/แนวโน้มใน Dashboard)
 * @param {string} userId
 * @param {number} days
 */
async function getHistory(userId, days = 30) {
    const { rows } = await pool.query(
        `SELECT * FROM daily_wellness_checkins
         WHERE user_id = $1 AND checkin_date >= CURRENT_DATE - $2::int
         ORDER BY checkin_date DESC`,
        [userId, days]
    );
    return rows;
}

module.exports = {
    getTodayStatus,
    createCheckin,
    updateCheckin,
    getHistory,
};