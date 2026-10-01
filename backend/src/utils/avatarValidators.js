const BaseJoi = require('joi');

// รับ query ได้ทั้ง ?slot=hair,beard และ ?slot=hair&slot=beard
const Joi = BaseJoi.extend((joi) => ({
  type: 'csvArray',
  base: joi.array(),
  coerce: {
    from: 'string',
    method: (value) => ({ value: value.split(',').map((part) => part.trim()).filter(Boolean) }),
  },
}));

// ต้องตรงกับ migration 015
const RARITIES = ['common', 'rare', 'epic', 'legendary'];
const HEX_COLOR = /^#[0-9A-F]{6}$/;

const slotCodeSchema = Joi.string().trim().lowercase().pattern(/^[a-z_]{1,30}$/);
const raritySchema = Joi.string().trim().lowercase().valid(...RARITIES);
const hexColorSchema = Joi.string().trim().uppercase().pattern(HEX_COLOR).messages({
  'string.pattern.base': 'สีต้องอยู่ในรูปแบบ #RRGGBB',
});

const paging = (defaultLimit) => ({
  limit: Joi.number().integer().min(1).max(100).default(defaultLimit),
  offset: Joi.number().integer().min(0).default(0),
});

const updateAvatarSchema = Joi.object({
  skinTone: hexColorSchema,
  // ส่งเฉพาะช่องที่เปลี่ยน: itemId = null คือถอดออก
  equipment: Joi.array()
    .items(
      Joi.object({
        slot: slotCodeSchema.required(),
        itemId: Joi.string().uuid().allow(null).required(),
        colorHex: hexColorSchema.allow(null),
      })
    )
    .max(30)
    .unique('slot'),
})
  .min(1)
  .options({ abortEarly: false, stripUnknown: true });

const inventoryFiltersSchema = Joi.object({
  slot: Joi.csvArray().items(slotCodeSchema).max(30).unique(),
  rarity: Joi.csvArray().items(raritySchema).unique(),
  ...paging(50),
}).options({ abortEarly: false, stripUnknown: true });

module.exports = {
  Joi,
  RARITIES,
  slotCodeSchema,
  raritySchema,
  paging,
  updateAvatarSchema,
  inventoryFiltersSchema,
};
