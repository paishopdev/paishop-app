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
  const number = cleaned ? parseInt(cleaned) : null;

  if (!number) return null;

  // 🚨 SAÇMA BÜYÜK SAYIYI KIRP
  if (number > 10000000) {
    return Math.round(number / 1000000);
  }

  return number;
}

const axios = require('axios');

function extractImage(item) {
  if (typeof item.thumbnail === 'string' && item.thumbnail.startsWith('http')) {
    return item.thumbnail;
  }

  if (typeof item.serpapi_thumbnail === 'string' && item.serpapi_thumbnail.startsWith('http')) {
    return item.serpapi_thumbnail;
  }

  if (Array.isArray(item.thumbnails) && item.thumbnails.length > 0) {
    const firstThumb = item.thumbnails.find(
      (thumb) => typeof thumb === 'string' && thumb.startsWith('http')
    );
    if (firstThumb) return firstThumb;
  }

  if (item.product_link && typeof item.product_link === 'string') {
    return '';
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
  });

  const results = response.data.shopping_results || [];

  console.log('FIRST SHOPPING RESULT:', JSON.stringify(results[0], null, 2));

  return results.slice(0, 40).map((item) => {
  
  
    return {
      name: item.title || 'Unknown product',
      price: item.price || item.extracted_price?.toString() || 'Fiyat yok',
      platform: item.source || 'Unknown store',
      image: item.serpapi_thumbnails?.[0] || item.serpapi_thumbnail || item.thumbnail || '',
      link: item.product_link || item.link || '',
      rating: item.rating || null,
      reviews: parseReviewCount(item.reviews),
    };
  });
}

module.exports = { searchGoogleShopping };