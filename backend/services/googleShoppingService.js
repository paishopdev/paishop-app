const axios = require('axios');
const cheerio = require('cheerio');

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

function isBlockedImageUrl(url) {
  if (!url || typeof url !== 'string') return true;

  const lower = url.toLowerCase();

  return (
    !lower.startsWith('http') ||
    lower.includes('encrypted-tbn') ||
    lower.includes('gstatic.com/shopping?q=tbn') ||
    lower.includes('serpapi.com')
  );
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
    if (!isBlockedImageUrl(img)) {
      return img;
    }
  }

  return '';
}

async function fetchImageFromProductPage(url) {
  try {
    if (!url || typeof url !== 'string' || !url.startsWith('http')) {
      return '';
    }

    const response = await axios.get(url, {
      timeout: 12000,
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        Accept:
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      },
    });

    const $ = cheerio.load(response.data);

    const ogImage = $('meta[property="og:image"]').attr('content');
    if (ogImage && !isBlockedImageUrl(ogImage)) {
      return ogImage;
    }

    const twitterImage = $('meta[name="twitter:image"]').attr('content');
    if (twitterImage && !isBlockedImageUrl(twitterImage)) {
      return twitterImage;
    }

    const imgCandidates = $('img')
      .map((_, el) => $(el).attr('src'))
      .get()
      .filter(Boolean);

    for (const img of imgCandidates) {
      if (img.startsWith('http') && !isBlockedImageUrl(img)) {
        return img;
      }
    }

    return '';
  } catch (e) {
    return '';
  }
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

  const mapped = await Promise.all(
    results.slice(0, 40).map(async (item) => {
      let image = extractImage(item);

      if (!image) {
        image = await fetchImageFromProductPage(item.product_link || item.link || '');
      }

      return {
        name: item.title || 'Unknown product',
        price: item.price || item.extracted_price?.toString() || 'Fiyat yok',
        platform: item.source || 'Unknown store',
        image: image || '',
        link: item.product_link || item.link || '',
        rating: item.rating || null,
        reviews: parseReviewCount(item.reviews),
        short_reason: '',
      };
    })
  );

  return mapped;
}

module.exports = { searchGoogleShopping };