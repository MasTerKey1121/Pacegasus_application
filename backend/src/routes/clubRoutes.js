const express = require('express');
const clubController = require('../controllers/clubController');
const { requireAuth } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');
const { saveImage } = require('../services/clubImageService');

const router = express.Router();
router.use(requireAuth);
router.post('/images', asyncHandler(async (req, res) => {
  const filename = await saveImage(req.body.imageBase64);
  const imageUrl = `${req.protocol}://${req.get('host')}/api/club-images/${filename}`;
  res.status(201).json({ success: true, data: { imageUrl } });
}));

router.get('/', clubController.searchClubs);
router.post('/', clubController.createClub);

// /me ต้องมาก่อน /:clubId
router.get('/me', clubController.getMyClub);
router.get('/me/join-requests', clubController.listMyJoinRequests);
router.patch('/me/join-requests/:requestId/accept', clubController.acceptInvite);
router.delete('/me/join-requests/:requestId', clubController.removeMyJoinRequest);

router.get('/:clubId', clubController.getClub);
router.patch('/:clubId', clubController.updateClub);
router.delete('/:clubId', clubController.disbandClub);
router.post('/:clubId/leave', clubController.leaveClub);
router.post('/:clubId/transfer-leadership', clubController.transferLeadership);

router.patch('/:clubId/members/:userId/role', clubController.changeMemberRole);
router.delete('/:clubId/members/:userId', clubController.kickMember);

router.get('/:clubId/permissions', clubController.getPermissions);
router.patch('/:clubId/permissions/:role', clubController.updateRolePermissions);

router.get('/:clubId/join-requests', clubController.listClubJoinRequests);
router.post('/:clubId/join-requests', clubController.requestToJoin);
router.patch('/:clubId/join-requests/:requestId/approve', clubController.approveJoinRequest);
router.delete('/:clubId/join-requests/:requestId', clubController.removeClubJoinRequest);
router.post('/:clubId/invites', clubController.inviteUser);

module.exports = router;
