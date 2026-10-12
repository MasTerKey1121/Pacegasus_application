const express = require('express');
const Joi = require('joi');
const { requireAuth } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const service = require('../services/leaderboardService');
const router = express.Router();
const filters = Joi.object({ scope: Joi.string().valid('individual', 'guild').default('individual') });
router.use(requireAuth);
router.get('/', asyncHandler(async (req, res) => {
  const { value, error } = filters.validate(req.query);
  if (error) throw new ApiError(400, 'ประเภทการจัดอันดับไม่ถูกต้อง');
  res.json({ success: true, data: await service.weeklyDistance(req.user.id, value.scope) });
}));
module.exports = router;
