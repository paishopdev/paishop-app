const axios = require('axios');

async function searchSerperShopping(query) {
  const apiKey = process.env.SERPER_API_KEY;

  if (!apiKey) {
    throw new Error('SERPER_API_KEY missing');
  }

  const response = await axios.post(
    'https://google.serper.dev/shopping',
    { q: query, gl: 'tr', hl: 'tr' },
    {
      headers: {
        'X-API-KEY': apiKey,
        'Content-Type': 'application/json'
      },
      timeout: 20000
    }
  );

  const results =
  response.data.shopping ||
  response.data.shopping_results ||
  response.data.results ||
  [];

  return results.map((item) => ({
    name: item.title || 'Unknown product',
    price: item.price || 'Fiyat yok',
    platform: item.source || 'Unknown store',
    image: item.image || '',
    link: item.link || '',
    rating: item.rating || null,
    reviews: item.reviewCount || null,
    short_reason: '',
  }));
}

module.exports = { searchSerperShopping };