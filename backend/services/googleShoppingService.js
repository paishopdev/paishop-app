const axios = require('axios');

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
  const number = cleaned ? parseInt(cleaned, 10) : null;

  if (!number) return null;

  if (number > 10000000) {
    return Math.round(number / 1000000);
  }

  return number;
}

function isValidHttpUrl(value) {
  return typeof value === 'string' && value.startsWith('http');
}

function extractImage(item) {
  if (!item || typeof item !== 'object') return '';

  const candidates = [
    ...(Array.isArray(item.serpapi_thumbnails) ? item.serpapi_thumbnails : []),
    item.serpapi_thumbnail,
    item.thumbnail,
    ...(Array.isArray(item.thumbnails) ? item.thumbnails : []),
    item.image,
  ].filter(Boolean);

  for (const img of candidates) {
    if (isValidHttpUrl(img)) {
      return img;
    }
  }

  return '';
}

async function searchGoogleShopping(query) {
  const apiKey = process.env.SERPAPI_KEY;

  if (!apiKey) {
    throw new Error('SERPAPI_KEY is missing');
  }

  const url = 'https://serpapi.com/search.json';

  const response = await axios.get(url, {
    params: {
      engine: 'google',
      tbm: 'shop',
      q: query,
      hl: 'tr',
      gl: 'tr',
      api_key: apiKey,
    },
    timeout: 20000,
  });

  const results = response.data.shopping_results || [];

  console.log('FIRST SHOPPING RESULT:', JSON.stringify(results[0], null, 2));

  return results.slice(0, 40).map((item) => {
    const rawImage = extractImage(item);

    return {
      name: item.title || 'Unknown product',
      price: item.price || item.extracted_price?.toString() || 'Fiyat yok',
      platform: item.source || 'Unknown store',
      image: rawImage || '',
      link: item.product_link || item.link || '',
      rating: item.rating || null,
      reviews: parseReviewCount(item.reviews),
      short_reason: '',
    };
  });
}

module.exports = { searchGoogleShopping };