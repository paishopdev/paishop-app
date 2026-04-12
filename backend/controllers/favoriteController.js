const Favorite = require('../models/Favorite');

const getFavorites = async (req, res) => {
  try {
    const { userId } = req.params;

    const favorites = await Favorite.find({ userId }).sort({ createdAt: -1 });
    return res.json(favorites);
  } catch (error) {
    console.error('Get favorites error:', error.message);
    return res.status(500).json({ error: 'Favoriler alınamadı' });
  }
};

const addFavorite = async (req, res) => {
  try {
    const { userId, product } = req.body;

    if (!userId || !product || !product.link) {
      return res.status(400).json({ error: 'userId ve product zorunlu' });
    }

    const existing = await Favorite.findOne({
      userId,
      'product.link': product.link,
    });

    if (existing) {
      return res.status(400).json({ error: 'Bu ürün zaten favorilerde' });
    }

    const favorite = await Favorite.create({
      userId,
      product,
    });

    return res.status(201).json(favorite);
  } catch (error) {
    console.error('Add favorite error:', error.message);
    return res.status(500).json({ error: 'Favori eklenemedi' });
  }
};

const removeFavorite = async (req, res) => {
  try {
    const { favoriteId } = req.params;

    const deleted = await Favorite.findByIdAndDelete(favoriteId);

    if (!deleted) {
      return res.status(404).json({ error: 'Favori bulunamadı' });
    }

    return res.json({ message: 'Favori silindi' });
  } catch (error) {
    console.error('Remove favorite error:', error.message);
    return res.status(500).json({ error: 'Favori silinemedi' });
  }
};

module.exports = {
  getFavorites,
  addFavorite,
  removeFavorite,
};