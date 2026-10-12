const { Joi, slotCodeSchema, raritySchema, paging } = require('./avatarValidators');

const SHOP_SORTS = ['featured', 'newest', 'price_asc', 'price_desc', 'rarity_asc', 'rarity_desc', 'ending_soon'];

const listingIdSchema = Joi.string().uuid().required();

const shopItemFiltersSchema = Joi.object({
  slot: Joi.csvArray().items(slotCodeSchema).max(30).unique(),
  rarity: Joi.csvArray().items(raritySchema).unique(),
  q: Joi.string().trim().max(60).allow(''),
  minPrice: Joi.number().integer().min(0),
  maxPrice: Joi.number().integer().min(0),
  owned: Joi.boolean(),
  featured: Joi.boolean(),
  sort: Joi.string().valid(...SHOP_SORTS).default('featured'),
  ...paging(30),
}).options({ abortEarly: false, stripUnknown: true });

const purchaseFiltersSchema = Joi.object(paging(50)).options({ abortEarly: false, stripUnknown: true });

module.exports = {
  SHOP_SORTS,
  listingIdSchema,
  shopItemFiltersSchema,
  purchaseFiltersSchema,
};
