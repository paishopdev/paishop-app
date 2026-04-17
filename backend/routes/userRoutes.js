const express = require('express');
const router = express.Router();

const {
  getUserProfile,
  updateUserProfile,
} = require('../controllers/userController');

router.get('/:userId', getUserProfile);
router.put('/:userId', updateUserProfile);

module.exports = router;