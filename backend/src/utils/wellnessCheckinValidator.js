// ============================================================
// wellnessCheckinValidator.js
// วางที่: src/utils/wellnessCheckinValidator.js
//
// หมายเหตุ: แยกเป็นไฟล์ของตัวเอง ไม่ inline ใน controller (ผิดโครงสร้าง)
// และยังไม่ merge เข้า src/utils/validators.js ตัวกลาง เพราะยังไม่เห็น
// export pattern ของไฟล์นั้น — ถ้าส่งเนื้อไฟล์ validators.js มาให้ดู
// จะย้าย schema นี้เข้าไปรวมให้ถูกจุดแทนได้
// ============================================================

const Joi = require('joi');

const wellnessCheckinSchema = Joi.object({
    sleepQuality: Joi.number().integer().min(1).max(5).required(),
    energyLevel: Joi.number().integer().min(1).max(5).required(),
    muscleSoreness: Joi.number().integer().min(1).max(5).required(),
    stressLevel: Joi.number().integer().min(1).max(5).required(),
    motivation: Joi.number().integer().min(1).max(5).required(),
    note: Joi.string().max(500).allow('', null),
});

module.exports = { wellnessCheckinSchema };