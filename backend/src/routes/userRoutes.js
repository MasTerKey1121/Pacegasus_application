const express = require('express');
const userController = require('../controllers/userController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

router.use(requireAuth);
router.get('/me/full', userController.getFullProfile);
router.delete('/me', userController.deleteCurrentUser);

module.exports = router;
