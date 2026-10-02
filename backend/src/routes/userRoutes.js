const express = require('express');
const userController = require('../controllers/userController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

router.use(requireAuth);
router.get('/me/full', userController.getFullProfile);
router.get('/me/progress', userController.getGameProgress);
router.get('/:identifier/profile', require('../utils/asyncHandler')(async (req, res) => {
  const data = await require('../services/publicProfileService').getProfile(req.user.id, req.params.identifier);
  res.json({ success: true, data });
}));
router.delete('/me', userController.deleteUser);

module.exports = router;
