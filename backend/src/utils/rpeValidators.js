const Joi = require('joi');

const moodValues = ['exhausted', 'bad', 'neutral', 'good', 'great'];

const logRpeSchema = Joi.object({
  runningSessionId: Joi.string().uuid().allow(null).optional(),
  durationMinutes: Joi.number().integer().min(1).max(1440).required(),
  rpeScore: Joi.number().integer().min(1).max(10).required(),
  stressLevel: Joi.number().integer().min(1).max(10).required(),
  mood: Joi.string().valid(...moodValues).required(),
  hasPain: Joi.boolean().required(),
  painNote: Joi.string().trim().max(1000).allow('', null).when('hasPain', {
    is: true,
    then: Joi.required().custom((value, helpers) => value && value.trim()
      ? value.trim()
      : helpers.error('any.invalid')).messages({ 'any.invalid': 'painNote ต้องระบุเมื่อ hasPain เป็น true' }),
    otherwise: Joi.valid(null, '').default(null),
  }),
  loggedAt: Joi.date().iso().optional(),
}).options({ abortEarly: false, stripUnknown: true });

const rpeHistoryFiltersSchema = Joi.object({
  startDate: Joi.date().iso().optional(),
  endDate: Joi.date().iso().min(Joi.ref('startDate')).optional(),
  mood: Joi.string().valid(...moodValues).optional(),
  hasPain: Joi.boolean().optional(),
  limit: Joi.number().integer().min(1).max(100).default(30),
  offset: Joi.number().integer().min(0).default(0),
}).options({ abortEarly: false, stripUnknown: true });

module.exports = { logRpeSchema, rpeHistoryFiltersSchema };
