const express = require('express');
const avatarController = require('../controllers/avatarController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();
router.use(requireAuth);

router.get('/slots', avatarController.listSlots);
router.get('/me', avatarController.getMyAvatar);
router.put('/me', avatarController.updateMyAvatar);
router.get('/inventory', avatarController.listInventory);
router.get('/users/:uid', avatarController.getAvatarByUid);

module.exports = router;
