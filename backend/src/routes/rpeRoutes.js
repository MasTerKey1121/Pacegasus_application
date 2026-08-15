const express = require('express');
const rpeController = require('../controllers/rpeController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();
router.use(requireAuth);

router.post('/', rpeController.logRpe);
router.get('/history', rpeController.getRpeHistory);
router.get('/risk-index', rpeController.getRiskIndex);

module.exports = router;
