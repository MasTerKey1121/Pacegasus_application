const express = require('express');
const router = express.Router();
const programController = require('../controllers/programController');
const { requireAuth } = require('../middleware/Auth');

router.use(requireAuth);

router.post('/start', programController.startProgram);
router.get('/current/week', programController.getCurrentWeek);
router.post('/quests', programController.addManualQuest);
router.delete('/quests/:questId', programController.deleteManualQuest);
router.get('/quests', programController.getQuestsInRange);

module.exports = router;