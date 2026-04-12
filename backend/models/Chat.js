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
    actions: [String],
    comparison: {
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