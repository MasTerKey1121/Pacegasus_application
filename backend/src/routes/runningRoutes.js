const express = require('express');
const router = express.Router();
const runningController = require('../controllers/runningController');
const { requireAuth } = require('../middleware/Auth');

router.use(requireAuth);

router.post('/', runningController.startSession);
router.get('/history', runningController.getSessionHistory);
router.patch('/:id/complete', runningController.completeSession);
router.patch('/:id/abandon', runningController.abandonSession);
router.get('/:id', runningController.getSessionDetail);

module.exports = router;
