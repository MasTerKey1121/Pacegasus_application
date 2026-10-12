const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const shopService = require('../services/shopService');
const { listingIdSchema, shopItemFiltersSchema, purchaseFiltersSchema } = require('../utils/shopValidators');

function validate(schema, input, message) {
  const { value, error } = schema.validate(input);
  if (error) throw new ApiError(400, message, error.details.map(({ message: detail }) => detail));
  return value;
}

// GET /api/shop/items?slot=&rarity=&q=&minPrice=&maxPrice=&owned=&featured=&sort=&limit=&offset=
const listItems = asyncHandler(async (req, res) => {
  const filters = validate(shopItemFiltersSchema, req.query, 'ตัวกรองไม่ถูกต้อง');
  const result = await shopService.listItems(req.user.id, filters);
  res.status(200).json({ success: true, data: { ...result, limit: filters.limit, offset: filters.offset } });
});

// GET /api/shop/items/:listingId
const getItem = asyncHandler(async (req, res) => {
  const listingId = validate(listingIdSchema, req.params.listingId, 'listingId ไม่ถูกต้อง');
  const listing = await shopService.getItem(req.user.id, listingId);
  res.status(200).json({ success: true, data: listing });
});

// POST /api/shop/items/:listingId/purchase
const purchase = asyncHandler(async (req, res) => {
  const listingId = validate(listingIdSchema, req.params.listingId, 'listingId ไม่ถูกต้อง');
  const result = await shopService.purchase(req.user.id, listingId);
  res.status(201).json({ success: true, message: 'ซื้อไอเท็มแล้ว', data: result });
});

// GET /api/shop/purchases
const listPurchases = asyncHandler(async (req, res) => {
  const filters = validate(purchaseFiltersSchema, req.query, 'ตัวกรองไม่ถูกต้อง');
  const purchases = await shopService.listPurchases(req.user.id, filters);
  res.status(200).json({ success: true, data: { purchases, ...filters } });
});

module.exports = { listItems, getItem, purchase, listPurchases };
