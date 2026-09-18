const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const friendService = require('../services/friendService');
const {
  uidSchema,
  friendshipIdSchema,
  sendFriendRequestSchema,
  friendListFiltersSchema,
  friendRequestFiltersSchema,
} = require('../utils/friendValidators');

function validate(schema, input, message) {
  const { value, error } = schema.validate(input);
  if (error) throw new ApiError(400, message, error.details.map(({ message: detail }) => detail));
  return value;
}

// GET /api/friends
const listFriends = asyncHandler(async (req, res) => {
  const filters = validate(friendListFiltersSchema, req.query, 'ตัวกรองไม่ถูกต้อง');
  const friends = await friendService.listFriends(req.user.id, filters);
  res.status(200).json({ success: true, data: { friends, limit: filters.limit, offset: filters.offset } });
});

// GET /api/friends/lookup/:uid
const lookupUser = asyncHandler(async (req, res) => {
  const uid = validate(uidSchema, req.params.uid, 'UID ไม่ถูกต้อง');
  const result = await friendService.lookupByUid(req.user.id, uid);
  res.status(200).json({ success: true, data: result });
});

// GET /api/friends/requests?direction=incoming|outgoing
const listFriendRequests = asyncHandler(async (req, res) => {
  const filters = validate(friendRequestFiltersSchema, req.query, 'ตัวกรองไม่ถูกต้อง');
  const requests = await friendService.listFriendRequests(req.user.id, filters);
  res.status(200).json({
    success: true,
    data: { requests, direction: filters.direction, limit: filters.limit, offset: filters.offset },
  });
});

// POST /api/friends/requests { uid }
const sendFriendRequest = asyncHandler(async (req, res) => {
  const { uid } = validate(sendFriendRequestSchema, req.body, 'ข้อมูลคำขอเป็นเพื่อนไม่ถูกต้อง');
  const friendship = await friendService.sendFriendRequest(req.user.id, uid);
  res.status(friendship.autoAccepted ? 200 : 201).json({
    success: true,
    message: friendship.autoAccepted ? 'ผู้ใช้นี้ส่งคำขอมาก่อนแล้ว เป็นเพื่อนกันเรียบร้อย' : 'ส่งคำขอเป็นเพื่อนแล้ว',
    data: friendship,
  });
});

// PATCH /api/friends/requests/:friendshipId/accept
const acceptFriendRequest = asyncHandler(async (req, res) => {
  const friendshipId = validate(friendshipIdSchema, req.params.friendshipId, 'friendshipId ไม่ถูกต้อง');
  const friendship = await friendService.acceptFriendRequest(req.user.id, friendshipId);
  res.status(200).json({ success: true, message: 'ตอบรับคำขอเป็นเพื่อนแล้ว', data: friendship });
});

// DELETE /api/friends/requests/:friendshipId (ผู้รับ = ปฏิเสธ, ผู้ส่ง = ยกเลิก)
const removeFriendRequest = asyncHandler(async (req, res) => {
  const friendshipId = validate(friendshipIdSchema, req.params.friendshipId, 'friendshipId ไม่ถูกต้อง');
  const result = await friendService.removeFriendRequest(req.user.id, friendshipId);
  res.status(200).json({
    success: true,
    message: result.action === 'declined' ? 'ปฏิเสธคำขอเป็นเพื่อนแล้ว' : 'ยกเลิกคำขอเป็นเพื่อนแล้ว',
    data: result,
  });
});

// DELETE /api/friends/:friendshipId
const removeFriend = asyncHandler(async (req, res) => {
  const friendshipId = validate(friendshipIdSchema, req.params.friendshipId, 'friendshipId ไม่ถูกต้อง');
  const result = await friendService.removeFriend(req.user.id, friendshipId);
  res.status(200).json({ success: true, message: 'ลบเพื่อนแล้ว', data: result });
});

module.exports = {
  listFriends,
  lookupUser,
  listFriendRequests,
  sendFriendRequest,
  acceptFriendRequest,
  removeFriendRequest,
  removeFriend,
};
