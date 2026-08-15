const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const Joi = require('joi');
const rpeService = require('../services/rpeService');
const { logRpeSchema, rpeHistoryFiltersSchema } = require('../utils/rpeValidators');

const logRpe = asyncHandler(async (req, res) => {
  const { value, error } = logRpeSchema.validate(req.body);
  if (error) throw new ApiError(400, 'ข้อมูล RPE ไม่ถูกต้อง', error.details.map(({ message }) => message));
  const log = await rpeService.logRpe(req.user.id, value);
  res.status(201).json({ success: true, data: log });
});

const getRpeHistory = asyncHandler(async (req, res) => {
  const { value, error } = rpeHistoryFiltersSchema.validate(req.query);
  if (error) throw new ApiError(400, 'ตัวกรองไม่ถูกต้อง', error.details.map(({ message }) => message));
  const logs = await rpeService.getRpeHistory(req.user.id, value);
  res.status(200).json({ success: true, data: { logs, limit: value.limit, offset: value.offset } });
});

const getRpeDetail = asyncHandler(async (req, res) => {
  const { value, error } = Joi.string().uuid().validate(req.params.id);
  if (error) throw new ApiError(400, 'RPE log id ไม่ถูกต้อง');
  const log = await rpeService.getRpeDetail(req.user.id, value);
  res.status(200).json({ success: true, data: log });
});

const getRiskIndex = asyncHandler(async (req, res) => {
  const riskIndex = await rpeService.calculateTrainingLoad(req.user.id);
  res.status(200).json({ success: true, data: riskIndex });
});

module.exports = { logRpe, getRpeHistory, getRpeDetail, getRiskIndex };
