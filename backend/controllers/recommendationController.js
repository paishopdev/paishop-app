const { getRecommendations } = require('../services/aiRecommendationService');

const recommend = async (req, res) => {
  try {
    const { query } = req.body;

    if (!query || typeof query !== 'string') {
      return res.status(400).json({
        error: 'Query is required and must be a string',
      });
    }

    const products = await getRecommendations(query);

    return res.json({ products });
  } catch (error) {
    console.error('Recommendation controller error:', error);

    return res.status(500).json({
      error: 'Failed to get recommendations',
      details: error.message,
    });
  }
};

module.exports = { recommend };
