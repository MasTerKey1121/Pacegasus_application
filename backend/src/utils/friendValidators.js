const Joi = require('joi');

// ต้องตรงกับ alphabet ใน generate_user_uid() (migration 013)
const UID_PATTERN = /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{10}$/;

const uidSchema = Joi.string().trim().uppercase().pattern(UID_PATTERN).required().messages({
  'string.pattern.base': 'UID ต้องเป็นตัวอักษรหรือตัวเลข 10 ตัว',
  'any.required': 'กรุณาระบุ UID ของเพื่อน',
});

const friendshipIdSchema = Joi.string().uuid().required();

const sendFriendRequestSchema = Joi.object({
  uid: uidSchema,
}).options({ abortEarly: false, stripUnknown: true });

const friendListFiltersSchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).default(50),
  offset: Joi.number().integer().min(0).default(0),
}).options({ abortEarly: false, stripUnknown: true });

const friendRequestFiltersSchema = friendListFiltersSchema.keys({
  direction: Joi.string().valid('incoming', 'outgoing').default('incoming'),
});

module.exports = {
  uidSchema,
  friendshipIdSchema,
  sendFriendRequestSchema,
  friendListFiltersSchema,
  friendRequestFiltersSchema,
};
