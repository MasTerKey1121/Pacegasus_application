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

const step1Schema = Joi.object({
  dateOfBirth: Joi.date().iso().max('now').required(),
  gender: Joi.string().valid('male', 'female', 'other', 'prefer_not_to_say').required(),
  heightCm: Joi.number().min(80).max(250).required(),
  weightKg: Joi.number().min(20).max(300).required(),
  runningExperienceLevel: Joi.string().valid('beginner', 'intermediate', 'advanced', 'elite').required(),
  weeklyDistanceKm: Joi.number().min(0).max(500).required(),
  runningDaysPerWeek: Joi.number().integer().min(0).max(7).required(),
  timezone: Joi.string().default('Asia/Bangkok'),
});

const injurySchema = Joi.object({
  bodyPart: Joi.string().trim().max(100).required(),
  injuryType: Joi.string().trim().max(150).allow('', null),
  severity: Joi.number().integer().min(1).max(10).allow(null),
  isCurrent: Joi.boolean().default(false),
  occurredAt: Joi.date().iso().allow(null),
  notes: Joi.string().allow('', null),
});

const step2Schema = Joi.object({
  hasInjuryHistory: Joi.boolean().required(),
  injuries: Joi.array().items(injurySchema).default([]),
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
  targetDate: Joi.date().iso().allow(null),
  targetPaceSecPerKm: Joi.number().integer().min(120).max(1200).allow(null),
  isPrimary: Joi.boolean().default(false),
});

const step3Schema = Joi.object({
  goals: Joi.array().items(goalSchema).min(1).required(),
});

const step4Schema = Joi.object({
  hasRunBefore: Joi.boolean().required(),
  yearsRunning: Joi.number().min(0).max(80).allow(null),
  best5kSeconds: Joi.number().integer().min(0).allow(null),
  best10kSeconds: Joi.number().integer().min(0).allow(null),
  bestHalfMarathonSeconds: Joi.number().integer().min(0).allow(null),
  bestMarathonSeconds: Joi.number().integer().min(0).allow(null),
  preferredEnvironment: Joi.string().valid('park', 'road', 'city', 'treadmill', 'trail').allow(null),
  typicalTrainingTime: Joi.string()
    .valid('early_morning', 'morning', 'afternoon', 'evening', 'night')
    .allow(null),
  connectedStrava: Joi.boolean().default(false),
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