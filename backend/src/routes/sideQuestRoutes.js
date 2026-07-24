const express = require('express');
const router = express.Router();
const sideQuestController = require('../controllers/sideQuestController');
const { requireAuth } = require('../middleware/Auth');

router.use(requireAuth);

router.get('/side', sideQuestController.getSideQuests);

module.exports = router;