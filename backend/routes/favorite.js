const express = require('express');
const {
  getFavorites,
  addFavorite,
  removeFavorite,
} = require('../controllers/favoriteController');

const router = express.Router();

router.get('/:userId', getFavorites);
router.post('/', addFavorite);
router.delete('/:favoriteId', removeFavorite);

module.exports = router;