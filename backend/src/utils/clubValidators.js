const Joi = require('joi');
const { uidSchema } = require('./friendValidators');

// ตัวอักษรทุกภาษา (รวมสระ/วรรณยุกต์ไทยที่เป็น mark) ตัวเลข _ และ -
const TAG_PATTERN = /^[\p{L}\p{M}\p{N}_-]{1,20}$/u;
const MANAGEABLE_ROLES = ['sub_leader', 'member'];

const idSchema = Joi.string().uuid().required();
const tagSchema = Joi.string().trim().lowercase().pattern(TAG_PATTERN).messages({
  'string.pattern.base': 'tag ต้องเป็นตัวอักษรหรือตัวเลข ไม่เกิน 20 ตัว และไม่มีช่องว่าง',
});

const clubInfo = {
  name: Joi.string().trim().min(3).max(40),
  description: Joi.string().trim().max(500).allow('', null),
  imageUrl: Joi.string().trim().uri({ scheme: ['https', 'http'] }).max(2048).allow(null),
  tags: Joi.array().items(tagSchema).max(5).unique(),
};

const paging = (defaultLimit) => ({
  limit: Joi.number().integer().min(1).max(100).default(defaultLimit),
  offset: Joi.number().integer().min(0).default(0),
});

const createClubSchema = Joi.object({
  ...clubInfo,
  name: clubInfo.name.required(),
  tags: clubInfo.tags.default([]),
}).options({ abortEarly: false, stripUnknown: true });

const updateClubSchema = Joi.object(clubInfo).min(1).options({ abortEarly: false, stripUnknown: true });

const searchClubsSchema = Joi.object({
  q: Joi.string().trim().max(40).allow(''),
  tag: tagSchema,
  hasSlot: Joi.boolean().default(false),
  ...paging(20),
}).options({ abortEarly: false, stripUnknown: true });

const changeMemberRoleSchema = Joi.object({
  role: Joi.string().valid(...MANAGEABLE_ROLES).required(),
}).options({ abortEarly: false, stripUnknown: true });

const transferLeadershipSchema = Joi.object({
  userId: idSchema,
}).options({ abortEarly: false, stripUnknown: true });

const permissionRoleSchema = Joi.string().valid(...MANAGEABLE_ROLES).required();

const updatePermissionsSchema = Joi.object({
  canApproveRequests: Joi.boolean(),
  canInvite: Joi.boolean(),
  canKick: Joi.boolean(),
  canEditInfo: Joi.boolean(),
})
  .min(1)
  .options({ abortEarly: false, stripUnknown: true });

const joinRequestSchema = Joi.object({
  message: Joi.string().trim().max(200).allow(''),
}).options({ abortEarly: false, stripUnknown: true });

const inviteSchema = Joi.object({
  uid: uidSchema,
  message: Joi.string().trim().max(200).allow(''),
}).options({ abortEarly: false, stripUnknown: true });

// staff ดูคำขอของคลับ: request = คนขอเข้า, invite = คำเชิญที่ส่งออกไปแล้ว
const clubJoinRequestFiltersSchema = Joi.object({
  kind: Joi.string().valid('request', 'invite').default('request'),
  ...paging(50),
}).options({ abortEarly: false, stripUnknown: true });

// ผู้ใช้ดูของตัวเอง: invite = คำเชิญที่ได้รับ, request = คำขอที่ส่งไป
const myJoinRequestFiltersSchema = clubJoinRequestFiltersSchema.keys({
  kind: Joi.string().valid('request', 'invite').default('invite'),
});

module.exports = {
  idSchema,
  createClubSchema,
  updateClubSchema,
  searchClubsSchema,
  changeMemberRoleSchema,
  transferLeadershipSchema,
  permissionRoleSchema,
  updatePermissionsSchema,
  joinRequestSchema,
  inviteSchema,
  clubJoinRequestFiltersSchema,
  myJoinRequestFiltersSchema,
};
