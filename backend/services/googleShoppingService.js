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

function isValidHttpImage(value) {
  return (
    typeof value === 'string' &&
    value.startsWith('http') &&
    !value.includes('gstatic.com/shopping?q=tbn:') &&
    !value.includes('encrypted-tbn') &&
    !value.endsWith('.svg')
  );
}

function extractImage(item) {
  if (!item || typeof item !== 'object') return '';

  if (Array.isArray(item.serpapi_thumbnails) && item.serpapi_thumbnails.length > 0) {
    const valid = item.serpapi_thumbnails.find((img) => isValidHttpImage(img));
    if (valid) return valid;
  }

  if (isValidHttpImage(item.serpapi_thumbnail)) {
    return item.serpapi_thumbnail;
  }

  if (isValidHttpImage(item.thumbnail)) {
    return item.thumbnail;
  }

  if (Array.isArray(item.thumbnails) && item.thumbnails.length > 0) {
    const valid = item.thumbnails.find((img) => isValidHttpImage(img));
    if (valid) return valid;
  }

  if (Array.isArray(item.rich_snippet?.top?.detected_extensions?.images)) {
    const valid = item.rich_snippet.top.detected_extensions.images.find((img) =>
      isValidHttpImage(img)
    );
    if (valid) return valid;
  }

  if (isValidHttpImage(item.image)) {
    return item.image;
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
    const image = extractImage(item);

    return {
      name: item.title || 'Unknown product',
      price:
        item.price ||
        item.extracted_price?.toString() ||
        'Fiyat yok',
      platform: item.source || 'Unknown store',
      image,
      link: item.product_link || item.link || '',
      rating: item.rating || null,
      reviews: parseReviewCount(item.reviews),
      short_reason: '',
    };
  });
}

module.exports = { searchGoogleShopping };