const db = require('../config/db');
const rpeService = require('./rpeService');
const wellnessCheckinService = require('./wellnessCheckinService');

// ต้องมี rpe_logs ต่อเนื่องอย่างน้อย 14 วัน ก่อนที่ ACWR จะเชื่อถือได้พอจะใช้ตัดสิน
// (สูตร ACWR เทียบ acute 7 วัน กับ chronic เฉลี่ย 28 วัน หารด้วย 4 เสมอ ถ้าข้อมูล
// ยังไม่ครบ 28 วัน ค่าเฉลี่ยรายสัปดาห์จะถูกประเมินต่ำกว่าจริง ทำให้ ACWR พุ่งสูงเกิน
// จริงในช่วงแรกของโปรแกรม ไม่ใช่เพราะฝึกหนักเกินจริง)
const COLD_START_MIN_DAYS = 14;

const HARD_SESSION_TYPES = ['tempo', 'vo2max', 'threshold'];

async function getDaysSinceFirstLog(userId) {
  const { rows } = await db.query(
    `SELECT MIN(logged_at) AS first_logged_at FROM rpe_logs WHERE user_id = $1`,
    [userId]
  );
  const firstLoggedAt = rows[0]?.first_logged_at;
  if (!firstLoggedAt) return null;
  const diffMs = Date.now() - new Date(firstLoggedAt).getTime();
  return Math.floor(diffMs / (1000 * 60 * 60 * 24));
}

// Cold-start: ยังไม่มี ACWR ที่เชื่อถือได้ -> ให้ wellness ตัดสินเพียงลำพัง
// (ไม่มี force_rest ในโหมดนี้ เพราะ wellness ตัวเดียวไม่ควรมีน้ำหนักพอจะบังคับพัก
// force_rest สงวนไว้เฉพาะ ACWR แดงเท่านั้น ตามที่ตกลงกันไว้)
function decideFromWellnessOnly(wellnessScore) {
  if (wellnessScore == null) {
    return {
      action: 'as_planned',
      multiplier: 1.0,
      reason: 'ACWR ยังไม่พร้อมใช้งาน (ข้อมูลน้อยกว่า 14 วัน) และยังไม่มี Wellness Check-in วันนี้ — ทำตามแผนเดิม',
    };
  }
  if (wellnessScore <= 2.0) {
    return {
      action: 'reduce_load',
      multiplier: 0.6,
      reason: 'ACWR ยังไม่พร้อมใช้งาน ใช้ Wellness ตัดสินแทน: wellness ต่ำมาก ลดปริมาณ 40%',
    };
  }
  if (wellnessScore <= 3.0) {
    return {
      action: 'reduce_load',
      multiplier: 0.85,
      reason: 'ACWR ยังไม่พร้อมใช้งาน ใช้ Wellness ตัดสินแทน: wellness ต่ำกว่าเกณฑ์ ลดปริมาณ 15%',
    };
  }
  return {
    action: 'as_planned',
    multiplier: 1.0,
    reason: 'ACWR ยังไม่พร้อมใช้งาน ใช้ Wellness ตัดสินแทน: wellness ปกติ ทำตามแผนเดิม',
  };
}

// Gate เต็มรูปแบบ: ACWR ก่อน (ชั้น 1) แล้วค่อย Wellness (ชั้น 2)
// ไม่มี action 'progress' — progression เป็นหน้าที่ของ phase/week multiplier
// (011/012) ล้วนๆ ที่นี่มีหน้าที่แค่ "เบรก" เท่านั้น
function decideWithAcwr(riskLevel, wellnessScore, plannedSessionType) {
  if (riskLevel === 'red') {
    return {
      action: 'force_rest',
      multiplier: 0,
      reason: 'ACWR อยู่โซนอันตราย (>= 1.5): ความเสี่ยงบาดเจ็บสูง บังคับพัก',
    };
  }

  if (riskLevel === 'yellow' && HARD_SESSION_TYPES.includes(plannedSessionType)) {
    return {
      action: 'downgrade_to_easy',
      multiplier: 0.7,
      reason: 'ACWR อยู่โซนเสี่ยง (1.3-1.5): ลดจาก session หนักเป็น easy run',
    };
  }

  if (wellnessScore == null) {
    return {
      action: 'as_planned',
      multiplier: 1.0,
      reason: 'ยังไม่มี Wellness Check-in วันนี้ — ทำตามแผนเดิม',
    };
  }
  if (wellnessScore <= 2.0) {
    return {
      action: 'reduce_load',
      multiplier: 0.6,
      reason: 'wellness ต่ำมาก (นอนไม่พอ/ปวดกล้ามเนื้อ/เครียดสูง): ลดปริมาณ 40%',
    };
  }
  if (wellnessScore <= 3.0) {
    return {
      action: 'reduce_load',
      multiplier: 0.85,
      reason: 'wellness ต่ำกว่าเกณฑ์: ลดปริมาณเล็กน้อย 15%',
    };
  }

  return { action: 'as_planned', multiplier: 1.0, reason: 'ไม่มีปัจจัยเสี่ยง ทำตามแผนเดิม' };
}

/**
 * คำนวณการปรับแผนของ quest หนึ่งรายการ สำหรับผู้ใช้คนหนึ่ง ณ ตอนนี้
 * ไม่แก้ main_quest_instances.planned_value ในฐานข้อมูล — คืนค่า adjustedValue
 * แยกต่างหากให้ผู้เรียกตัดสินใจว่าจะแสดงผลหรือบันทึกต่ออย่างไร (non-destructive
 * ตามที่ตกลงกันไว้ตอนออกแบบ เพื่อไม่ทำลาย baseline ต้นฉบับ)
 */
async function computeAdjustment(userId, plannedSession) {
  const [daysSinceFirstLog, trainingLoad, wellnessToday] = await Promise.all([
    getDaysSinceFirstLog(userId),
    rpeService.calculateTrainingLoad(userId),
    wellnessCheckinService.getTodayStatus(userId),
  ]);

  const wellnessScore = wellnessToday.status === 'done'
    ? Number(wellnessToday.record.wellness_score)
    : null;

  const isColdStart = daysSinceFirstLog === null || daysSinceFirstLog < COLD_START_MIN_DAYS;

  const decision = isColdStart
    ? decideFromWellnessOnly(wellnessScore)
    : decideWithAcwr(trainingLoad.riskLevel, wellnessScore, plannedSession.session_type);

  const adjustedValue = plannedSession.planned_value != null
    ? Number((plannedSession.planned_value * decision.multiplier).toFixed(2))
    : null;

  return {
    action: decision.action,
    reason: decision.reason,
    multiplier: decision.multiplier,
    isColdStart,
    daysSinceFirstLog,
    acwr: trainingLoad.acwr,
    riskLevel: trainingLoad.riskLevel,
    wellnessScore,
    originalPlannedValue: plannedSession.planned_value,
    adjustedValue,
  };
}

module.exports = {
  computeAdjustment,
  decideFromWellnessOnly,
  decideWithAcwr,
  getDaysSinceFirstLog,
  COLD_START_MIN_DAYS,
};
