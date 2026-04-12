const express = require('express');
const { recommend } = require('../controllers/recommendationController');

const router = express.Router();
router.post('/recommend', recommend);

module.exports = router;
