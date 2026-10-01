const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const clubService = require('../services/clubService');
const {
  idSchema,
  createClubSchema,
  updateClubSchema,
  searchClubsSchema,
  changeMemberRoleSchema,
  transferLeadershipSchema,
  permissionRoleSchema,
  updatePermissionsSchema,
  joinRequestSchema,
  inviteSchema,
  clubJoinRequestFiltersSchema,
  myJoinRequestFiltersSchema,
} = require('../utils/clubValidators');

function validate(schema, input, message) {
  const { value, error } = schema.validate(input);
  if (error) throw new ApiError(400, message, error.details.map(({ message: detail }) => detail));
  return value;
}

const clubIdOf = (req) => validate(idSchema, req.params.clubId, 'clubId ไม่ถูกต้อง');
const userIdOf = (req) => validate(idSchema, req.params.userId, 'userId ไม่ถูกต้อง');
const requestIdOf = (req) => validate(idSchema, req.params.requestId, 'requestId ไม่ถูกต้อง');

// GET /api/clubs?q=&tag=&hasSlot=&limit=&offset=
const searchClubs = asyncHandler(async (req, res) => {
  const filters = validate(searchClubsSchema, req.query, 'ตัวกรองไม่ถูกต้อง');
  const result = await clubService.searchClubs(req.user.id, filters);
  res.status(200).json({ success: true, data: { ...result, limit: filters.limit, offset: filters.offset } });
});

// POST /api/clubs { name, description?, imageUrl?, tags? }
const createClub = asyncHandler(async (req, res) => {
  const info = validate(createClubSchema, req.body, 'ข้อมูลคลับไม่ถูกต้อง');
  const club = await clubService.createClub(req.user.id, info);
  res.status(201).json({ success: true, message: 'สร้างคลับแล้ว', data: club });
});

// GET /api/clubs/me
const getMyClub = asyncHandler(async (req, res) => {
  const club = await clubService.getMyClub(req.user.id);
  res.status(200).json({ success: true, data: club });
});

// GET /api/clubs/:clubId
const getClub = asyncHandler(async (req, res) => {
  const club = await clubService.getClub(req.user.id, clubIdOf(req));
  res.status(200).json({ success: true, data: club });
});

// PATCH /api/clubs/:clubId { name?, description?, imageUrl?, tags? }
const updateClub = asyncHandler(async (req, res) => {
  const clubId = clubIdOf(req);
  const patch = validate(updateClubSchema, req.body, 'ข้อมูลคลับไม่ถูกต้อง');
  const club = await clubService.updateClub(req.user.id, clubId, patch);
  res.status(200).json({ success: true, message: 'แก้ไขข้อมูลคลับแล้ว', data: club });
});

// DELETE /api/clubs/:clubId
const disbandClub = asyncHandler(async (req, res) => {
  const result = await clubService.disbandClub(req.user.id, clubIdOf(req));
  res.status(200).json({ success: true, message: 'ยุบคลับแล้ว', data: result });
});

// POST /api/clubs/:clubId/leave
const leaveClub = asyncHandler(async (req, res) => {
  const result = await clubService.leaveClub(req.user.id, clubIdOf(req));
  res.status(200).json({
    success: true,
    message: result.action === 'disbanded' ? 'ออกจากคลับแล้ว คลับถูกยุบเพราะไม่มีสมาชิกเหลือ' : 'ออกจากคลับแล้ว',
    data: result,
  });
});

// POST /api/clubs/:clubId/transfer-leadership { userId }
const transferLeadership = asyncHandler(async (req, res) => {
  const clubId = clubIdOf(req);
  const { userId } = validate(transferLeadershipSchema, req.body, 'ข้อมูลไม่ถูกต้อง');
  const result = await clubService.transferLeadership(req.user.id, clubId, userId);
  res.status(200).json({ success: true, message: 'โอนตำแหน่งหัวหน้าคลับแล้ว', data: result });
});

// PATCH /api/clubs/:clubId/members/:userId/role { role }
const changeMemberRole = asyncHandler(async (req, res) => {
  const clubId = clubIdOf(req);
  const userId = userIdOf(req);
  const { role } = validate(changeMemberRoleSchema, req.body, 'ยศไม่ถูกต้อง');
  const result = await clubService.changeMemberRole(req.user.id, clubId, userId, role);
  res.status(200).json({ success: true, message: 'เปลี่ยนยศสมาชิกแล้ว', data: result });
});

// DELETE /api/clubs/:clubId/members/:userId
const kickMember = asyncHandler(async (req, res) => {
  const result = await clubService.kickMember(req.user.id, clubIdOf(req), userIdOf(req));
  res.status(200).json({ success: true, message: 'เตะสมาชิกออกจากคลับแล้ว', data: result });
});

// GET /api/clubs/:clubId/permissions
const getPermissions = asyncHandler(async (req, res) => {
  const permissions = await clubService.getPermissions(req.user.id, clubIdOf(req));
  res.status(200).json({ success: true, data: permissions });
});

// PATCH /api/clubs/:clubId/permissions/:role { canApproveRequests?, canInvite?, canKick?, canEditInfo? }
const updateRolePermissions = asyncHandler(async (req, res) => {
  const clubId = clubIdOf(req);
  const role = validate(permissionRoleSchema, req.params.role, 'ยศไม่ถูกต้อง');
  const changes = validate(updatePermissionsSchema, req.body, 'ข้อมูลสิทธิ์ไม่ถูกต้อง');
  const result = await clubService.updateRolePermissions(req.user.id, clubId, role, changes);
  res.status(200).json({ success: true, message: 'อัปเดตสิทธิ์แล้ว', data: result });
});

// POST /api/clubs/:clubId/join-requests { message? }
const requestToJoin = asyncHandler(async (req, res) => {
  const clubId = clubIdOf(req);
  const body = validate(joinRequestSchema, req.body, 'ข้อมูลคำขอไม่ถูกต้อง');
  const result = await clubService.requestToJoin(req.user.id, clubId, body);
  const joined = result.status === 'joined';
  res.status(joined ? 200 : 201).json({
    success: true,
    message: joined ? 'คุณได้รับคำเชิญจากคลับนี้อยู่แล้ว เข้าร่วมคลับเรียบร้อย' : 'ส่งคำขอเข้าคลับแล้ว',
    data: result,
  });
});

// POST /api/clubs/:clubId/invites { uid, message? }
const inviteUser = asyncHandler(async (req, res) => {
  const clubId = clubIdOf(req);
  const body = validate(inviteSchema, req.body, 'ข้อมูลคำเชิญไม่ถูกต้อง');
  const result = await clubService.inviteUser(req.user.id, clubId, body);
  const joined = result.status === 'joined';
  res.status(joined ? 200 : 201).json({
    success: true,
    message: joined ? 'ผู้ใช้นี้ขอเข้าคลับมาก่อนแล้ว อนุมัติเข้าคลับเรียบร้อย' : 'ส่งคำเชิญแล้ว',
    data: result,
  });
});

// GET /api/clubs/:clubId/join-requests?kind=request|invite
const listClubJoinRequests = asyncHandler(async (req, res) => {
  const clubId = clubIdOf(req);
  const filters = validate(clubJoinRequestFiltersSchema, req.query, 'ตัวกรองไม่ถูกต้อง');
  const requests = await clubService.listClubJoinRequests(req.user.id, clubId, filters);
  res.status(200).json({ success: true, data: { requests, ...filters } });
});

// PATCH /api/clubs/:clubId/join-requests/:requestId/approve
const approveJoinRequest = asyncHandler(async (req, res) => {
  const result = await clubService.approveJoinRequest(req.user.id, clubIdOf(req), requestIdOf(req));
  res.status(200).json({ success: true, message: 'อนุมัติคำขอเข้าคลับแล้ว', data: result });
});

// DELETE /api/clubs/:clubId/join-requests/:requestId (request = ปฏิเสธ, invite = ยกเลิกคำเชิญ)
const removeClubJoinRequest = asyncHandler(async (req, res) => {
  const result = await clubService.removeClubJoinRequest(req.user.id, clubIdOf(req), requestIdOf(req));
  res.status(200).json({
    success: true,
    message: result.action === 'rejected' ? 'ปฏิเสธคำขอเข้าคลับแล้ว' : 'ยกเลิกคำเชิญแล้ว',
    data: result,
  });
});

// GET /api/clubs/me/join-requests?kind=invite|request
const listMyJoinRequests = asyncHandler(async (req, res) => {
  const filters = validate(myJoinRequestFiltersSchema, req.query, 'ตัวกรองไม่ถูกต้อง');
  const requests = await clubService.listMyJoinRequests(req.user.id, filters);
  res.status(200).json({ success: true, data: { requests, ...filters } });
});

// PATCH /api/clubs/me/join-requests/:requestId/accept (ตอบรับคำเชิญ)
const acceptInvite = asyncHandler(async (req, res) => {
  const result = await clubService.acceptInvite(req.user.id, requestIdOf(req));
  res.status(200).json({ success: true, message: 'เข้าร่วมคลับแล้ว', data: result });
});

// DELETE /api/clubs/me/join-requests/:requestId (request = ยกเลิกคำขอ, invite = ปฏิเสธคำเชิญ)
const removeMyJoinRequest = asyncHandler(async (req, res) => {
  const result = await clubService.removeMyJoinRequest(req.user.id, requestIdOf(req));
  res.status(200).json({
    success: true,
    message: result.action === 'cancelled' ? 'ยกเลิกคำขอเข้าคลับแล้ว' : 'ปฏิเสธคำเชิญแล้ว',
    data: result,
  });
});

module.exports = {
  searchClubs,
  createClub,
  getMyClub,
  getClub,
  updateClub,
  disbandClub,
  leaveClub,
  transferLeadership,
  changeMemberRole,
  kickMember,
  getPermissions,
  updateRolePermissions,
  requestToJoin,
  inviteUser,
  listClubJoinRequests,
  approveJoinRequest,
  removeClubJoinRequest,
  listMyJoinRequests,
  acceptInvite,
  removeMyJoinRequest,
};
