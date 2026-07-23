const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const { getSideQuestsSchema } = require('../utils/questValidators');
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

module.exports = { getSideQuests };
