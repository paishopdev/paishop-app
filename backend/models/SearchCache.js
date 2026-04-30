const mongoose = require('mongoose');

const searchCacheSchema = new mongoose.Schema({
  query: { type: String, required: true, index: true },
  type: { type: String, default: 'search' },
  data: { type: Array, default: [] },
  createdAt: { type: Date, default: Date.now },
  expireAt: { type: Date, required: true }
});

searchCacheSchema.index({ expireAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('SearchCache', searchCacheSchema);