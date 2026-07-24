const express = require('express');
const authRoutes = require('./authRoutes');
const onboardingRoutes = require('./onboardingRoutes');
const userRoutes = require('./userRoutes');
const wellnessCheckinRoutes = require('./wellnessCheckinRoutes');
const programRoutes = require('./programRoutes');
const sideQuestRoutes = require('./sideQuestRoutes');

const router = express.Router();

router.get('/health', (req, res) => res.json({ success: true, message: 'Pacegasus API is running' }));

router.use('/auth', authRoutes);
router.use('/onboarding', onboardingRoutes);
router.use('/users', userRoutes);
router.use('/wellness-checkin', wellnessCheckinRoutes);
router.use('/programs', programRoutes);
router.use('/quests', sideQuestRoutes);

module.exports = router;
