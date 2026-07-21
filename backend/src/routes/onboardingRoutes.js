const express = require('express');
const onboardingController = require('../controllers/onboardingController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

router.use(requireAuth);

router.get('/status', onboardingController.getStatus);
router.put('/step1', onboardingController.saveStep1); // basic info
router.put('/step2', onboardingController.saveStep2); // injury history
router.put('/step3', onboardingController.saveStep3); // goals
router.put('/step4', onboardingController.saveStep4); // running history

module.exports = router;
