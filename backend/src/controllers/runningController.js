const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const runningService = require('../services/runningService');
const { getSessionHistorySchema } = require('../utils/runningValidators');

// POST /api/running-sessions
const startSession = asyncHandler(async (req, res) => {
  const session = await runningService.startSession(req.user.id, req.body);
  res.status(201).json({ success: true, data: session });
});

// PATCH /api/running-sessions/:id/complete
const completeSession = asyncHandler(async (req, res) => {
  const result = await runningService.completeSession(req.user.id, req.params.id, req.body);
  res.status(200).json({ success: true, data: result });
});

// PATCH /api/running-sessions/:id/abandon
const abandonSession = asyncHandler(async (req, res) => {
  const session = await runningService.abandonSession(req.user.id, req.params.id, req.body);
  res.status(200).json({ success: true, data: session });
});

// GET /api/running-sessions/:id
const getSessionDetail = asyncHandler(async (req, res) => {
  const detail = await runningService.getSessionDetail(req.user.id, req.params.id);
  res.status(200).json({ success: true, data: detail });
});

// GET /api/running-sessions/history?sortBy=date|month|year&order=asc|desc
const getSessionHistory = asyncHandler(async (req, res) => {
  const { value, error } = getSessionHistorySchema.validate(req.query);
  if (error) throw new ApiError(400, error.message);

  const history = await runningService.getSessionHistory(
    req.user.id,
    value.sortBy,
    value.order
  );
  res.status(200).json({ success: true, data: history });
});

module.exports = {
  startSession,
  completeSession,
  abandonSession,
  getSessionDetail,
  getSessionHistory,
};
