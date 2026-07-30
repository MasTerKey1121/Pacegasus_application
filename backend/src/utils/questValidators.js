const Joi = require('joi');

// รวมตรงนี้แล้วค่อย merge เข้า ../utils/validators.js เดิม (ที่มี step1-4Schema อยู่แล้ว)

const startProgramSchema = Joi.object({
  level: Joi.string()
    .valid('beginner', 'lower_intermediate', 'upper_intermediate')
    .required(),
  scheduleMode: Joi.string()
    .valid('auto', 'manual')
    .required(),
});

const getSideQuestsSchema = Joi.object({
  environment: Joi.string()
    .valid('park', 'road', 'city', 'treadmill', 'trail')
    .required(),
  trainingType: Joi.string()
    .valid('easy', 'long_run', 'tempo', 'interval')
    .required(),
});

const startSideQuestItemSchema = Joi.object({
  instanceId: Joi.string().uuid(),
  sideQuestTemplateId: Joi.string().uuid(),
})
  .xor('instanceId', 'sideQuestTemplateId')
  .messages({
    'object.xor': 'แต่ละ instance ต้องระบุ instanceId หรือ sideQuestTemplateId อย่างใดอย่างหนึ่งเท่านั้น',
  });

const startSideQuestSchema = Joi.object({
  instances: Joi.array()
    .items(startSideQuestItemSchema)
    .min(1)
    .max(3)
    .required()
    .messages({
      'array.min': 'ต้องระบุ side quest อย่างน้อย 1 รายการ',
      'array.max': 'ส่ง side quest ได้ไม่เกิน 3 รายการต่อครั้ง',
      'any.required': 'ต้องระบุ instances',
    }),
});

const updateProgressSchema = Joi.object({
  increment: Joi.number().integer().min(1).max(100).optional(),
  foundCount: Joi.number().integer().min(0).optional(),
  photoUrl: Joi.string().uri().allow('').optional(),
  gpsLat: Joi.number().min(-90).max(90).optional(),
  gpsLng: Joi.number().min(-180).max(180).optional(),
});

// ----------------------------------------------------------------------------
// เพิ่มใหม่: รองรับ controller ที่ยังไม่มี schema มาก่อน
// (addManualQuest / deleteManualQuest / getQuestsInRange ใน programController.js)
// ----------------------------------------------------------------------------

// session_type ของ main_quest_instances — ต้องตรงกับ AUTO_TEMPLATES ใน
// programService.js (คนละ enum กับ trainingType ของ side quest ด้านบน)
const MAIN_QUEST_SESSION_TYPES = ['easy', 'tempo', 'vo2max', 'long_run'];

const addManualQuestSchema = Joi.object({
  scheduledDate: Joi.date().iso().required().messages({
    'date.base': '"scheduledDate" ต้องเป็นวันที่รูปแบบ ISO ที่ถูกต้อง',
    'any.required': 'ต้องระบุ scheduledDate',
  }),
  sessionType: Joi.string()
    .valid(...MAIN_QUEST_SESSION_TYPES)
    .required()
    .messages({
      'any.only': `"sessionType" ต้องเป็นหนึ่งใน [${MAIN_QUEST_SESSION_TYPES.join(', ')}]`,
      'any.required': 'ต้องระบุ sessionType',
    }),
});

const questIdParamSchema = Joi.object({
  questId: Joi.string().uuid().required().messages({
    'string.guid': '"questId" ต้องเป็น UUID ที่ถูกต้อง',
    'any.required': 'ต้องระบุ questId',
  }),
});

const getQuestsInRangeSchema = Joi.object({
  from: Joi.date().iso().optional(),
  to: Joi.date().iso().optional().greater(Joi.ref('from')).messages({
    'date.greater': '"to" ต้องเป็นวันที่หลัง "from"',
  }),
}).and('from', 'to'); 

module.exports = {
  startProgramSchema,
  getSideQuestsSchema,
  startSideQuestSchema,
  updateProgressSchema,
  addManualQuestSchema,
  questIdParamSchema,
  getQuestsInRangeSchema,
};