const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const avatarService = require('../services/avatarService');
const { uidSchema } = require('../utils/friendValidators');
const { updateAvatarSchema, inventoryFiltersSchema } = require('../utils/avatarValidators');

function validate(schema, input, message) {
  const { value, error } = schema.validate(input);
  if (error) throw new ApiError(400, message, error.details.map(({ message: detail }) => detail));
  return value;
}

// GET /api/avatar/slots
const listSlots = asyncHandler(async (req, res) => {
  const slots = await avatarService.listSlots();
  res.status(200).json({ success: true, data: slots });
});

// GET /api/avatar/me
const getMyAvatar = asyncHandler(async (req, res) => {
  const avatar = await avatarService.getMyAvatar(req.user.id);
  res.status(200).json({ success: true, data: avatar });
});

// PUT /api/avatar/me { skinTone?, equipment?: [{ slot, itemId | null, colorHex? }] }
const updateMyAvatar = asyncHandler(async (req, res) => {
  const body = validate(updateAvatarSchema, req.body, 'ข้อมูล avatar ไม่ถูกต้อง');
  const avatar = await avatarService.updateMyAvatar(req.user.id, body);
  res.status(200).json({ success: true, message: 'บันทึก avatar แล้ว', data: avatar });
});

// GET /api/avatar/inventory?slot=hair,beard&rarity=epic&limit=&offset=
const listInventory = asyncHandler(async (req, res) => {
  const filters = validate(inventoryFiltersSchema, req.query, 'ตัวกรองไม่ถูกต้อง');
  const result = await avatarService.listInventory(req.user.id, filters);
  res.status(200).json({ success: true, data: { ...result, limit: filters.limit, offset: filters.offset } });
});

// GET /api/avatar/users/:uid
const getAvatarByUid = asyncHandler(async (req, res) => {
  const uid = validate(uidSchema, req.params.uid, 'UID ไม่ถูกต้อง');
  const avatar = await avatarService.getAvatarByUid(uid);
  res.status(200).json({ success: true, data: avatar });
});

module.exports = { listSlots, getMyAvatar, updateMyAvatar, listInventory, getAvatarByUid };
