const express = require('express');
const userController = require('../controllers/userController');
const { requireAuth } = require('../middleware/auth');
const { uploadAvatar } = require('../middleware/uploadAvatar');

const router = express.Router();

router.use(requireAuth);
router.get('/me/full', userController.getFullProfile);
router.get('/me', userController.getMe);
router.patch('/me', userController.updateMe);
router.delete('/me', userController.deleteMe);
router.put('/me/avatar', uploadAvatar, userController.uploadAvatar);
router.delete('/me/avatar', userController.deleteAvatar);

module.exports = router;
