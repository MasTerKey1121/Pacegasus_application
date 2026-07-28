const express = require('express');
const router = express.Router();
const sideQuestController = require('../controllers/sideQuestController');
const { requireAuth } = require('../middleware/Auth');

router.use(requireAuth);

router.get('/side', sideQuestController.getSideQuests);
router.get('/quests/side', sideQuestController.getSideQuests);

router.post('/running-sessions/:id/side-quests', sideQuestController.startSideQuest);
router.post('/quests/running-sessions/:id/side-quests', sideQuestController.startSideQuest);

router.patch('/side-quests/:id/progress', sideQuestController.updateProgress);
router.patch('/quests/side-quests/:id/progress', sideQuestController.updateProgress);

router.patch('/side-quests/:id/finish', sideQuestController.finishSideQuest);
router.patch('/quests/side-quests/:id/finish', sideQuestController.finishSideQuest);

router.get('/side-quests/:id/album', sideQuestController.getQuestAlbum);
router.get('/quests/side-quests/:id/album', sideQuestController.getQuestAlbum);

module.exports = router;