const axios = require('axios');

function isValidHttpUrl(value) {
  return typeof value === 'string' && value.startsWith('http');
}

function extractSerperImage(item = {}) {
  const candidates = [
    item.image,
    item.thumbnail,
    item.imageUrl,
    item.image_url,
    item.productImage,
    item.product_image,
    item.serpapi_thumbnail,
    ...(Array.isArray(item.images) ? item.images : []),
    ...(Array.isArray(item.thumbnails) ? item.thumbnails : []),
  ].filter(Boolean);

  for (const img of candidates) {
    if (isValidHttpUrl(img)) return img;
  }

  return '';
}

function parseReviewCount(value) {
  if (!value) return null;

  const text = String(value).toLowerCase().trim();

  if (text.includes('k')) {
    const num = parseFloat(text.replace(/[^\d.,]/g, '').replace(',', '.'));
    return isNaN(num) ? null : Math.round(num * 1000);
  }

  if (text.includes('m')) {
    const num = parseFloat(text.replace(/[^\d.,]/g, '').replace(',', '.'));
    return isNaN(num) ? null : Math.round(num * 1000000);
  }

  const cleaned = text.replace(/[^\d]/g, '');
  return cleaned ? parseInt(cleaned, 10) : null;
}

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
        'Content-Type': 'application/json',
      },
      timeout: 20000,
    }
  );

  const results =
    response.data.shopping ||
    response.data.shopping_results ||
    response.data.results ||
    [];

  console.log('FIRST SERPER SHOPPING RESULT:', JSON.stringify(results[0], null, 2));

  return results.slice(0, 40).map((item) => ({
    name: item.title || item.name || 'Unknown product',
    price: item.price || item.extracted_price?.toString() || 'Fiyat yok',
    platform: item.source || item.seller || item.merchant || 'Unknown store',
    image: extractSerperImage(item),
    link: item.link || item.product_link || item.url || '',
    rating: item.rating || null,
    reviews: parseReviewCount(item.reviewCount || item.reviews),
    short_reason: '',
  }));
}

module.exports = { searchSerperShopping };