const mongoose = require('mongoose');

const UserMemorySchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      unique: true,
    },

    favoriteBrands: {
      type: [String],
      default: [],
    },

    favoriteCategories: {
      type: [String],
      default: [],
    },

    preferredColors: {
      type: [String],
      default: [],
    },

    preferredFeatures: {
      type: [String],
      default: [],
    },

    budgetRange: {
      type: String,
      default: '',
    },

    shoppingStyle: {
      type: String,
      default: '',
    },

    lastSignals: {
      type: [String],
      default: [],
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model('UserMemory', UserMemorySchema);