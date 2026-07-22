const Joi = require('joi');

const emailSchema = Joi.string().trim().lowercase().email().required();
const otpSchema = Joi.string().trim().length(6).pattern(/^\d+$/).required();
const otpRefSchema = Joi.string().trim().uppercase().length(6).pattern(/^[A-Z0-9]+$/).required();

const requestOtpSchema = Joi.object({
  email: emailSchema,
  purpose: Joi.string().valid('register', 'login').default('login'),
});

const verifyOtpSchema = Joi.object({
  email: emailSchema,
  otp: otpSchema,
  otpRef: otpRefSchema,
  displayName: Joi.string().trim().max(150).optional(),
});

const googleAuthSchema = Joi.object({
  idToken: Joi.string().required(),
});

const refreshSchema = Joi.object({
  refreshToken: Joi.string().required(),
});

// แก้ไข Step 1: เพิ่ม weeklyDistanceKm และ timezone ที่ต้องใช้ใน Controller
const step1Schema = Joi.object({
  dateOfBirth: Joi.date().iso().max('now').required(),
  gender: Joi.string().valid('male', 'female', 'other', 'prefer_not_to_say').required(),
  heightCm: Joi.number().min(80).max(250).required(),
  weightKg: Joi.number().min(20).max(300).required(),
  weeklyDistanceKm: Joi.number().min(0).max(1000).allow(null).optional(), //
  runningDaysPerWeek: Joi.number().integer().min(0).max(7).required(),
  timezone: Joi.string().trim().default('Asia/Bangkok'), // 
});

// แก้ไข injurySchema: เพิ่ม category, severity, occurredAt, notes ตาม Payload & DB Query
const injurySchema = Joi.object({
  category: Joi.string().trim().optional(), // 👈 แก้ปัญหานี้! รองรับ "category": "injury"
  bodyPart: Joi.string().trim().max(100).required(),
  injuryType: Joi.string().trim().max(150).allow('', null).optional(),
  severity: Joi.string().trim().max(50).allow('', null).optional(), // 
  isCurrent: Joi.boolean().default(false),
  occurredAt: Joi.date().iso().allow(null).optional(), // 
  notes: Joi.string().trim().allow('', null).optional(), // 
});

// แก้ไข chronicConditionSchema: เพิ่มรองรับ category และ field อื่นๆ
const chronicConditionSchema = Joi.object({
  category: Joi.string().trim().optional(), // 👈 เพิ่มรองรับ category
  conditionName: Joi.string().trim().max(150).optional(), // 
  injuryType: Joi.string().trim().max(150).optional(), //
  isCurrent: Joi.boolean().default(true),
  notes: Joi.string().trim().allow('', null).optional(),
});

const step2Schema = Joi.object({
  hasInjuryHistory: Joi.boolean().required(),
  injuries: Joi.array().items(injurySchema).default([]),
  hasChronicCondition: Joi.boolean().required(),
  chronicConditions: Joi.array().items(chronicConditionSchema).default([]),
});

const goalSchema = Joi.object({
  goalType: Joi.string()
    .valid(
      'lose_weight',
      'run_5k',
      'run_10k',
      'half_marathon',
      'marathon',
      'general_fitness',
      'improve_pace',
      'stay_consistent'
    )
    .required(),
  targetDistanceKm: Joi.number().min(0).max(500).allow(null),
  targetPaceSecPerKm: Joi.number().integer().min(120).max(1200).allow(null),
  isPrimary: Joi.boolean().default(false),
});

const step3Schema = Joi.object({
  goals: Joi.array().items(goalSchema).min(1).required(),
});

const step4Schema = Joi.object({
  hasRunBefore: Joi.boolean().required(),
  isCurrentlyRunning: Joi.boolean().required(),
  weeksRunning: Joi.number().integer().min(0).max(5200).allow(null),
  longestDistanceKm: Joi.number().min(0).max(500).allow(null),
});

module.exports = {
  requestOtpSchema,
  verifyOtpSchema,
  googleAuthSchema,
  refreshSchema,
  step1Schema,
  step2Schema,
  step3Schema,
  step4Schema,
};