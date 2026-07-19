const express = require('express');
const authRoutes = require('./authRoutes');
const onboardingRoutes = require('./onboardingRoutes');
const userRoutes = require('./userRoutes');

const router = express.Router();

router.get('/health', (req, res) => res.json({ success: true, message: 'Pacegasus API is running' }));

router.use('/auth', authRoutes);
router.use('/onboarding', onboardingRoutes);
router.use('/users', userRoutes);

module.exports = router;
