const express = require('express');
const friendController = require('../controllers/friendController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();
router.use(requireAuth);

router.get('/', friendController.listFriends);
router.get('/lookup/:uid', friendController.lookupUser);
router.get('/requests', friendController.listFriendRequests);
router.post('/requests', friendController.sendFriendRequest);
router.patch('/requests/:friendshipId/accept', friendController.acceptFriendRequest);
router.delete('/requests/:friendshipId', friendController.removeFriendRequest);
router.delete('/:friendshipId', friendController.removeFriend);

module.exports = router;
