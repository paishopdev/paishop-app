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
  if (!item) return '';

  // ❌ serpapi proxy linkleri tamamen ignore et
  if (
    item.thumbnail &&
    item.thumbnail.startsWith('http') &&
    !item.thumbnail.includes('serpapi.com')
  ) {
    return item.thumbnail;
  }

  if (
    item.serpapi_thumbnail &&
    item.serpapi_thumbnail.startsWith('http') &&
    !item.serpapi_thumbnail.includes('serpapi.com')
  ) {
    return item.serpapi_thumbnail;
  }

  if (Array.isArray(item.thumbnails)) {
    const valid = item.thumbnails.find(
      (img) => img.startsWith('http') && !img.includes('serpapi.com')
    );
    if (valid) return valid;
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

    return Promise.all(
      results.slice(0, 40).map(async (item) => {
        let image = extractImage(item);
    
        // ❗ eğer serpapi linkiyse veya boşsa → gerçek sayfadan çek
        if (!image || image.includes('serpapi.com')) {
          const fallback = await fetchImageFromProductPage(
            item.product_link || item.link
          );
          if (fallback) image = fallback;
        }
    
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
      })
    );
  }   );
  const cheerio = require('cheerio');

async function fetchImageFromProductPage(url) {
  try {
    const { data } = await axios.get(url, { timeout: 8000 });
    const $ = cheerio.load(data);

    // og:image en güvenilir
    const og = $('meta[property="og:image"]').attr('content');
    if (og && og.startsWith('http')) return og;

    // fallback img
    const img = $('img').first().attr('src');
    if (img && img.startsWith('http')) return img;

    return '';
  } catch (e) {
    return '';
  }
}
}

module.exports = { searchGoogleShopping };