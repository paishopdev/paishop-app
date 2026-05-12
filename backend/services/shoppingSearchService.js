const SearchCache = require('../models/SearchCache');
const { searchSerperShopping, searchSerperImages } = require('./serperShoppingService');
const { searchGoogleShopping } = require('./googleShoppingService');
const axios = require('axios');

function getCacheMinutes(type) {
  if (type === 'seller') return 20;
  if (type === 'image') return 60;
  if (type === 'barcode') return 360;
  return 120;
}

function logProviderError(provider, err) {
  console.log(`${provider} FAILED:`, err.message);
  console.log(`${provider} STATUS:`, err.response?.status || err.status || null);
  console.log(`${provider} URL:`, err.config?.url || null);
  console.log(`${provider} DATA:`, JSON.stringify(err.response?.data || null, null, 2));
}

function hasHttpImage(product = {}) {
  const image = String(product.image || '').trim();
  return image.startsWith('http');
}

async function getFallbackImage(product = {}) {
  const name = String(product.name || '').trim();
  const platform = String(product.platform || '').trim();

  if (!name) return '';

  const imageQuery = `${name} ${platform}`.trim().toLowerCase();

  const cached = await SearchCache.findOne({
    query: imageQuery,
    type: 'image_lookup',
  });

  if (cached && cached.data?.[0]?.image) {
    return cached.data[0].image;
  }

  try {
    console.log('TRY IMAGE FALLBACK:', imageQuery);

    const image = await searchSerperImages(imageQuery);

    if (image) {
      await SearchCache.findOneAndUpdate(
        { query: imageQuery, type: 'image_lookup' },
        {
          query: imageQuery,
          type: 'image_lookup',
          data: [{ image }],
          expireAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
        },
        { upsert: true, returnDocument: 'after' }
      );
    }

    return image;
  } catch (err) {
    logProviderError('SERPER IMAGE', err);
    return '';
  }
}

async function enrichMissingImages(products = []) {
  const output = [];

  for (const product of products) {
    if (hasHttpImage(product)) {
      output.push(product);
      continue;
    }

    const fallbackImage = await getFallbackImage(product);

    output.push({
      ...product,
      image: fallbackImage || '',
    });
  }

  return output;
}

function normalizeBarcode(value = '') {
  return String(value || '').replace(/[^\d]/g, '');
}

function isValidBarcode(value = '') {
  const barcode = normalizeBarcode(value);

  return (
    barcode.length === 8 ||
    barcode.length === 12 ||
    barcode.length === 13 ||
    barcode.length === 14
  );
}

async function resolveBarcodeQuery(cleanQuery) {
  const barcode = normalizeBarcode(cleanQuery);

  if (!isValidBarcode(barcode)) {
    console.log('INVALID BARCODE:', cleanQuery);
    return {
      ok: false,
      query: '',
      barcode,
    };
  }

  try {
    console.log('BARCODE DETECTED:', barcode);

    const foodResponse = await axios.get(
      `https://world.openfoodfacts.org/api/v0/product/${barcode}.json`,
      { timeout: 8000 }
    );

    const product = foodResponse.data?.product || {};

    const productName =
      product.product_name_tr ||
      product.product_name ||
      product.generic_name_tr ||
      product.generic_name ||
      '';

    const brand =
      product.brands ||
      product.brands_tags?.[0] ||
      '';

    const quantity =
      product.quantity ||
      '';

    const composedName = [brand, productName, quantity]
      .filter(Boolean)
      .join(' ')
      .replace(/\s+/g, ' ')
      .trim();

    if (composedName.length > 2) {
      console.log('OPEN FOOD FACTS PRODUCT:', composedName);
      return {
        ok: true,
        query: composedName.toLowerCase(),
        barcode,
      };
    }
  } catch (err) {
    console.log('OPEN FOOD FACTS FAILED:', err.message);
  }

  return {
    ok: true,
    query: `${barcode} ürün`,
    barcode,
  };
}

function filterBarcodeResults(results = [], cleanQuery = '') {
  if (!Array.isArray(results) || results.length === 0) return results;

  const queryWords = cleanQuery
    .toLowerCase()
    .split(/\s+/)
    .map((w) => w.trim())
    .filter((w) => w.length >= 3)
    .filter(
      (w) =>
        ![
          'urun',
          'ürün',
          'adet',
          'gram',
          'gr',
          'ml',
          'the',
          'and',
          'ile',
          'icin',
          'için',
        ].includes(w)
    );

  if (queryWords.length === 0) return results;

  const filtered = results.filter((item) => {
    const name = String(item.name || '').toLowerCase();
    const platform = String(item.platform || '').toLowerCase();
    const haystack = `${name} ${platform}`;

    const matchCount = queryWords.filter((w) => haystack.includes(w)).length;

    return matchCount >= Math.min(2, queryWords.length);
  });

  return filtered.length > 0 ? filtered : results;
}

function normalizeMatchText(text = '') {
  return String(text || '')
    .toLowerCase()
    .replace(/[^\wğüşöçıİĞÜŞÖÇ\s]/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function matchScore(a = '', b = '') {
  const aWords = normalizeMatchText(a).split(' ').filter((w) => w.length >= 3);
  const bText = normalizeMatchText(b);

  if (aWords.length === 0 || !bText) return 0;

  return aWords.filter((w) => bText.includes(w)).length / aWords.length;
}

function enrichRatingsFromSerpApi(baseProducts = [], serpProducts = []) {
  return baseProducts.map((product) => {
    const match = serpProducts.find((item) => {
      const score1 = matchScore(product.name, item.name);
      const score2 = matchScore(item.name, product.name);
      return Math.max(score1, score2) >= 0.55;
    });

    if (!match) return product;

    return {
      ...product,
      rating: product.rating || match.rating || null,
      reviews: product.reviews || match.reviews || null,
    };
  });
}

async function searchProducts(query, type = 'search') {
  let cleanQuery = String(query || '').trim().toLowerCase();

  if (!cleanQuery) return [];

  console.log('SEARCH START:', cleanQuery, 'TYPE:', type);

  if (type === 'barcode') {
    const resolved = await resolveBarcodeQuery(cleanQuery);

    if (!resolved.ok) {
      return [];
    }

    cleanQuery = resolved.query;
  }

  const cache = await SearchCache.findOne({
    query: cleanQuery,
    type,
  });

  if (cache) {
    console.log('CACHE HIT:', cleanQuery);
    return cache.data;
  }

  console.log('CACHE MISS:', cleanQuery);

  let results = [];

  try {
    console.log('TRY SERPER...');
    results = await searchSerperShopping(cleanQuery);
    console.log('SERPER RESULT COUNT:', Array.isArray(results) ? results.length : 0);
  } catch (err) {
    logProviderError('SERPER', err);
  }

  if (type === 'barcode' && results && results.length > 0) {
    results = filterBarcodeResults(results, cleanQuery);
  }

  const needsRatingEnrichment =
  Array.isArray(results) &&
  results.length > 0 &&
  results.some((p) => !p.rating || !p.reviews || Number.isInteger(p.rating));

if (needsRatingEnrichment && type !== 'seller' && type !== 'image') {
  try {
    console.log('TRY SERPAPI ENRICH RATINGS...');
    const serpResults = await searchGoogleShopping(cleanQuery);

    if (Array.isArray(serpResults) && serpResults.length > 0) {
      results = enrichRatingsFromSerpApi(results, serpResults);
      console.log('SERPAPI ENRICH DONE');
    }
  } catch (err) {
    logProviderError('SERPAPI ENRICH', err);
  }
}

  if (!results || results.length === 0) {
    try {
      console.log('TRY SERPAPI...');
      results = await searchGoogleShopping(cleanQuery);
      console.log('SERPAPI RESULT COUNT:', Array.isArray(results) ? results.length : 0);
    } catch (err) {
      logProviderError('SERPAPI', err);
    }
  }

  if (type === 'barcode' && results && results.length > 0) {
    results = filterBarcodeResults(results, cleanQuery);
  }

  if (results && results.length > 0) {
    results = await enrichMissingImages(results);
  }

  if (results && results.length > 0) {
    const expireMinutes = getCacheMinutes(type);

    await SearchCache.findOneAndUpdate(
      { query: cleanQuery, type },
      {
        query: cleanQuery,
        type,
        data: results,
        expireAt: new Date(Date.now() + expireMinutes * 60 * 1000),
      },
      { upsert: true, returnDocument: 'after' }
    );

    console.log('CACHE SAVED:', cleanQuery, 'MIN:', expireMinutes);
  }

  return results || [];
}

module.exports = { searchProducts };