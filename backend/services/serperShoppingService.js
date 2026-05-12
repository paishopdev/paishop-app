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
  ].filter(Boolean);

  for (const img of candidates) {
    if (
      typeof img === 'string' &&
      img.startsWith('http') &&      // ✅ SADECE GERÇEK LINK
      !img.startsWith('data:image')  // ❌ BASE64 ENGEL
    ) {
      return img;
    }
  }

  return ''; // yoksa boş bırak
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

function parseRating(value) {
  if (value == null) return null;

  if (typeof value === 'number') {
    return value > 0 && value <= 5 ? value : null;
  }

  const text = String(value).toLowerCase().trim();

  // "3.7", "3,7", "3.7 out of 5" gibi durumlarda ilk decimal değeri al
  const match = text.match(/([0-5])([.,]\d)?/);
  if (!match) return null;

  const rating = parseFloat(match[0].replace(',', '.'));

  return rating > 0 && rating <= 5 ? rating : null;
}

function parseSerperReviewCount(item = {}) {
  const raw =
    item.reviews ||
    item.review_count ||
    item.reviewsCount ||
    item.reviewCount;

  if (!raw) return null;

  const text = String(raw).toLowerCase();

  // Emin olmadığımız "ratingCount" gibi alanları yorum sanma
  // Sadece içinde yorum/review/değerlendirme geçen alanları güvenli say
  if (
    !text.includes('yorum') &&
    !text.includes('review') &&
    !text.includes('değerlendirme') &&
    !text.includes('degerlendirme')
  ) {
    return null;
  }

  return parseReviewCount(raw);
}

async function searchSerperShopping(query) {
  const apiKey = process.env.SERPER_API_KEY;

  if (!apiKey) {
    throw new Error('SERPER_API_KEY missing');
  }

  const response = await axios.post(
    'https://google.serper.dev/shopping',
    { q: query, gl: 'tr', hl: 'tr', num: 20 },
    {
      headers: {
        'X-API-KEY': apiKey,
        'Content-Type': 'application/json',
      },
      timeout: 12000,
    }
  );

  const results =
    response.data.shopping ||
    response.data.shopping_results ||
    response.data.results ||
    [];

    return results.slice(0, 10).map((item) => ({
      name: item.title || item.name || 'Unknown product',
      price: item.price || item.extracted_price?.toString() || 'Fiyat yok',
      platform: item.source || item.seller || item.merchant || 'Unknown store',
      image: extractSerperImage(item),
      link: item.link || item.product_link || item.url || '',
      rating: parseRating(item.rating),
      reviews: parseReviewCount(item.ratingCount),
      short_reason: '',
    }));
}

async function searchSerperImages(query) {
  const apiKey = process.env.SERPER_API_KEY;

  if (!apiKey) {
    throw new Error('SERPER_API_KEY missing');
  }

  const response = await axios.post(
    'https://google.serper.dev/images',
    { q: query, gl: 'tr', hl: 'tr' },
    {
      headers: {
        'X-API-KEY': apiKey,
        'Content-Type': 'application/json',
      },
      timeout: 20000,
    }
  );

  const results = response.data.images || [];

  for (const item of results) {
    const img =
      item.imageUrl ||
      item.thumbnailUrl ||
      item.image ||
      item.thumbnail ||
      '';

    if (typeof img === 'string' && img.startsWith('http')) {
      return img;
    }
  }

  return '';
}

module.exports = { searchSerperShopping, searchSerperImages };