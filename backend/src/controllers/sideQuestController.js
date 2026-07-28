const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const {
  getSideQuestsSchema,
  startSideQuestSchema,
  updateProgressSchema,
  questIdParamSchema,
} = require('../utils/questValidators');
const sideQuestService = require('../services/sideQuestService');

// GET /api/v1/quests/side?environment=park&trainingType=easy
const getSideQuests = asyncHandler(async (req, res) => {
  const { value, error } = getSideQuestsSchema.validate(req.query);
  if (error) throw new ApiError(400, error.message);

  const result = await sideQuestService.getTodaySideQuests(
    req.user.id,
    value.environment,
    value.trainingType
  );

  res.status(200).json({
    success: true,
    data: result,
  });
});

// POST /api/quests/running-sessions/:id/side-quests
const startSideQuest = asyncHandler(async (req, res) => {
  const { value, error } = startSideQuestSchema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const instance = await sideQuestService.startSideQuest(req.user.id, req.params.id, value);

  res.status(201).json({
    success: true,
    data: instance,
  });
});

// PATCH /api/quests/side-quests/:id/progress
const updateProgress = asyncHandler(async (req, res) => {
  const { value, error } = questIdParamSchema.validate({ questId: req.params.id });
  if (error) throw new ApiError(400, error.message);

  const progressPayload = updateProgressSchema.validate(req.body);
  if (progressPayload.error) throw new ApiError(400, progressPayload.error.message);

  const instance = await sideQuestService.updateProgress(
    req.user.id,
    value.questId,
    progressPayload.value
  );

  res.status(200).json({
    success: true,
    data: instance,
  });
});

// PATCH /api/quests/side-quests/:id/finish
const finishSideQuest = asyncHandler(async (req, res) => {
  const { value, error } = questIdParamSchema.validate({ questId: req.params.id });
  if (error) throw new ApiError(400, error.message);

  const instance = await sideQuestService.finishSideQuest(req.user.id, value.questId);

  res.status(200).json({
    success: true,
    data: instance,
  });
});

// GET /api/quests/side-quests/:id/album
const getQuestAlbum = asyncHandler(async (req, res) => {
  const { value, error } = questIdParamSchema.validate({ questId: req.params.id });
  if (error) throw new ApiError(400, error.message);

  const photos = await sideQuestService.getQuestAlbum(req.user.id, value.questId);

  res.status(200).json({
    success: true,
    data: photos,
  });
});

module.exports = {
  getSideQuests,
  startSideQuest,
  updateProgress,
  finishSideQuest,
  getQuestAlbum,
};
