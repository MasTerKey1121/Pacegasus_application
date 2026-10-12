const express = require('express');
const userController = require('../controllers/userController');
const { requireAuth } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');
const ownProfile = require('../services/ownProfileService');

const router = express.Router();

router.use(requireAuth);
router.get('/me/profile', asyncHandler(async (req, res) => {
  res.json({ success: true, data: await ownProfile.get(req.user.id) });
}));
router.patch('/me/profile', asyncHandler(async (req, res) => {
  res.json({ success: true, data: await ownProfile.update(req.user.id, req.body) });
}));
router.get('/me/full', userController.getFullProfile);
router.get('/me/progress', userController.getGameProgress);
router.get('/profile/:uid', userController.getProfileByUid);
router.delete('/me', userController.deleteUser);

module.exports = router;
