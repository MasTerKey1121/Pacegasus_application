const express = require('express');
const userController = require('../controllers/userController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

router.use(requireAuth);
router.get('/me/full', userController.getFullProfile);
router.get('/me/progress', userController.getGameProgress);
router.delete('/me', userController.deleteUser);

module.exports = router;
