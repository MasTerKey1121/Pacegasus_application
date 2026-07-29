const Joi = require('joi');

const emailSchema = Joi.string().trim().lowercase().email().required();
const otpSchema = Joi.string().trim().length(6).pattern(/^\d+$/).required();
const otpRefSchema = Joi.string().trim().uppercase().length(6).pattern(/^[A-Z0-9]+$/).required();

// ==========================================
// Auth Schemas
// ==========================================

const requestOtpSchema = Joi.object({
  email: emailSchema,
  purpose: Joi.string().valid('register', 'login').default('login'),

  // บังคับเฉพาะกรณี purpose === 'register'
  policyAccepted: Joi.boolean()
    .when('purpose', {
      is: 'register',
      then: Joi.boolean().valid(true).required().messages({
        'any.only': 'คุณต้องยอมรับนโยบายความเป็นส่วนตัวและเงื่อนไขการใช้งานก่อนสมัครสมาชิก',
        'any.required': 'กรุณายอมรับนโยบายความเป็นส่วนตัวและเงื่อนไขการใช้งาน',
      }),
      otherwise: Joi.optional().allow(null),
    }),

  policyVersion: Joi.string()
    .trim()
    .max(20)
    .when('purpose', {
      is: 'register',
      then: Joi.string().required().messages({
        'any.required': 'กรุณาระบุเวอร์ชันของนโยบาย (policyVersion)',
      }),
      otherwise: Joi.optional().allow('', null),
    }),
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

// ==========================================
// Onboarding Schemas (Step 1 - Step 4)
// ==========================================

const step1Schema = Joi.object({
  dateOfBirth: Joi.date().iso().max('now').required(),
  gender: Joi.string().valid('male', 'female', 'other', 'prefer_not_to_say').required(),
  heightCm: Joi.number().min(80).max(250).required(),
  weightKg: Joi.number().min(20).max(300).required(),
  weeklyDistanceKm: Joi.number().min(0).max(1000).allow(null).optional(),
  runningDaysPerWeek: Joi.number().integer().min(0).max(7).required(),
  timezone: Joi.string().trim().default('Asia/Bangkok'),
});

const injurySchema = Joi.object({
  category: Joi.string().trim().optional(),
  bodyPart: Joi.string().trim().max(100).required(),
  injuryType: Joi.string().trim().max(150).allow('', null).optional(),
  severity: Joi.string().trim().max(50).allow('', null).optional(),
  isCurrent: Joi.boolean().default(false),
  occurredAt: Joi.date().iso().allow(null).optional(),
  notes: Joi.string().trim().allow('', null).optional(),
});

const chronicConditionSchema = Joi.object({
  category: Joi.string().trim().optional(),
  conditionName: Joi.string().trim().max(150).optional(),
  injuryType: Joi.string().trim().max(150).optional(),
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
      'build_muscle',
      'increase_speed',
      'increase_endurance',
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