const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema(
  {
    role: {
      type: String,
      enum: ['user', 'assistant'],
      required: true,
    },
    text: {
      type: String,
      required: true,
    },
    products: [
      {
        name: String,
        price: String,
        platform: String,
        image: String,
        link: String,
        rating: Number,
        reviews: Number,
        short_reason: String,
      },
    ],
    actions: {
      type: [String],
      default: [],
    },
    comparison: {
      type: {
        summary: String,
        winner: String,
        highlights: [String],
        products: [
          {
            name: String,
            price: String,
            platform: String,
            image: String,
            link: String,
            short_reason: String,
          },
        ],
      },
      default: null,
    },
    detailCard: {
      type: {
        product: {
          name: String,
          price: String,
          platform: String,
          image: String,
          link: String,
        },
        title: String,
        bullets: [String],
      },
      default: null,
    },
  },
  { _id: false }
);

const chatSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    title: {
      type: String,
      default: 'Yeni Sohbet',
    },
    messages: {
      type: [messageSchema],
      default: [],
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model('Chat', chatSchema);