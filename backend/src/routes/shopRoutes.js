const express = require('express');
const shopController = require('../controllers/shopController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();
router.use(requireAuth);

router.get('/items', shopController.listItems);
router.get('/items/:listingId', shopController.getItem);
router.post('/items/:listingId/purchase', shopController.purchase);
router.get('/purchases', shopController.listPurchases);

module.exports = router;
