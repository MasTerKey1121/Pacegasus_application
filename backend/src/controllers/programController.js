const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const {
  startProgramSchema,
  addManualQuestSchema,
  getQuestsInRangeSchema,
  questIdParamSchema,
} = require('../utils/questValidators');
const programService = require('../services/programService');

// POST /api/v1/programs/start
const startProgram = asyncHandler(async (req, res) => {
  const { value, error } = startProgramSchema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const result = await programService.startProgram(
    req.user.id,
    value.level,
    value.scheduleMode
  );

  res.status(201).json({
    success: true,
    message:
      value.scheduleMode === 'auto'
        ? 'สมัครโปรแกรมสำเร็จ — สร้างตารางฝึกทั้งโปรแกรมให้อัตโนมัติแล้ว'
        : 'สมัครโปรแกรมสำเร็จ — เริ่มลงตารางฝึกรายวันได้เลย',
    data: result,
  });
});

// GET /api/v1/programs/current/week
const getCurrentWeek = asyncHandler(async (req, res) => {
  const result = await programService.getCurrentWeek(req.user.id);

  res.status(200).json({
    success: true,
    data: result,
  });
});

// POST /api/v1/programs/quests — ลงเควสวันเดียวเอง (manual mode เท่านั้น)
const addManualQuest = asyncHandler(async (req, res) => {
  const { value, error } = addManualQuestSchema.validate(req.body);
  if (error) throw new ApiError(400, error.message);

  const result = await programService.addManualQuest(
    req.user.id,
    value.scheduledDate,
    value.sessionType
  );

  res.status(201).json({
    success: true,
    message: 'เพิ่มเควสสำเร็จ',
    data: result,
  });
});

// DELETE /api/v1/programs/quests/:questId — ลบเควสที่ยัง pending
const deleteManualQuest = asyncHandler(async (req, res) => {
  const { value, error } = questIdParamSchema.validate(req.params);
  if (error) throw new ApiError(400, error.message);

  const result = await programService.deleteManualQuest(
    req.user.id,
    value.questId
  );

  res.status(200).json({
    success: true,
    message: 'ลบเควสสำเร็จ',
    data: result,
  });
});

// GET /api/v1/programs/quests?from=&to= — ดูเควสตามช่วงวันที่ (fallback = สัปดาห์ปัจจุบัน)
const getQuestsInRange = asyncHandler(async (req, res) => {
  const { value, error } = getQuestsInRangeSchema.validate(req.query);
  if (error) throw new ApiError(400, error.message);

  const result = await programService.getQuestsInRange(
    req.user.id,
    value.from,
    value.to
  );

  res.status(200).json({
    success: true,
    data: result,
  });
});

module.exports = {
  startProgram,
  getCurrentWeek,
  addManualQuest,
  deleteManualQuest,
  getQuestsInRange,
};