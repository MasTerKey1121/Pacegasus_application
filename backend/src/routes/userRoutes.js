const express = require('express');
const userController = require('../controllers/userController');
const { requireAuth } = require('../middleware/auth');
const { uploadAvatar } = require('../middleware/uploadAvatar');

const router = express.Router();

router.use(requireAuth);
router.get('/me/full', userController.getFullProfile);
router.get('/me/progress', userController.getGameProgress);
router.get('/profile/:uid', userController.getProfileByUid);
router.delete('/me', userController.deleteUser);
router.get('/me', userController.getMe);
router.patch('/me', userController.updateMe);
router.put('/me/avatar', uploadAvatar, userController.uploadAvatar);
router.delete('/me/avatar', userController.deleteAvatar);

module.exports = router;
