const mongoose = require('mongoose');

const favoriteSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    product: {
      index: Number,
      name: String,
      price: String,
      platform: String,
      image: String,
      link: String,
      rating: Number,
      reviews: Number,
      short_reason: String,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model('Favorite', favoriteSchema);