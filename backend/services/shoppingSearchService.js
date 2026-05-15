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

async function isImageReachable(url = '') {
  if (!url || !url.startsWith('http')) return false;

  try {
    const response = await axios.head(url, {
      timeout: 6000,
      maxRedirects: 3,
      validateStatus: (status) => status >= 200 && status < 400,
    });

    const contentType = response.headers['content-type'] || '';
    return contentType.includes('image');
  } catch (_) {
    return false;
  }
}

async function getFallbackImage(product = {}) {
  const name = String(product.name || '').trim();
  const platform = String(product.platform || '').trim();

  if (!name) return '';

  const queries = [
    `${name} ${platform}`,
    name,
    `${name} ürün görseli`,
  ]
    .filter(Boolean)
    .map((q) => q.trim().toLowerCase());

  for (const imageQuery of queries) {
    const cached = await SearchCache.findOne({
      query: imageQuery,
      type: 'image_lookup_v2',
    });

    if (cached && cached.data?.[0]?.image) {
      const cachedImage = cached.data[0].image;

      if (await isImageReachable(cachedImage)) {
        return cachedImage;
      }
    }

    try {
      console.log('TRY IMAGE FALLBACK:', imageQuery);

      const image = await searchSerperImages(imageQuery);

      if (image && await isImageReachable(image)) {
        await SearchCache.findOneAndUpdate(
          { query: imageQuery, type: 'image_lookup_v2' },
          {
            query: imageQuery,
            type: 'image_lookup_v2',
            data: [{ image }],
            expireAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
          },
          { upsert: true, returnDocument: 'after' }
        );

        return image;
      }
    } catch (err) {
      logProviderError('SERPER IMAGE', err);
    }
  }

  return '';
}

async function enrichMissingImages(products = []) {
  const output = [];

  for (const product of products) {
    const currentImage = String(product.image || '').trim();

    if (currentImage && await isImageReachable(currentImage)) {
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

function normalizeProductText(value = '') {
  return String(value || '')
    .toLowerCase()
    .replace(/ı/g, 'i')
    .replace(/ğ/g, 'g')
    .replace(/ü/g, 'u')
    .replace(/ş/g, 's')
    .replace(/ö/g, 'o')
    .replace(/ç/g, 'c')
    .replace(/[^\w\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function cleanProductName(name = '') {
  return String(name || '')
    .replace(/[🔥⭐🚀✅❌💥]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function productFingerprint(product = {}) {
  return normalizeProductText(product.name || '')
    .replace(/\b(urun|ürün|kampanya|indirim|firsat|fırsat)\b/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 90);
}

function removeDuplicateProducts(products = []) {
  const seen = new Set();
  const output = [];

  for (const product of products || []) {
    const key =
      product.link ||
      `${productFingerprint(product)}-${normalizeProductText(product.platform || '')}`;

    if (!key || seen.has(key)) continue;

    seen.add(key);
    output.push(product);
  }

  return output;
}

function productQualityScore(product = {}, cleanQuery = '') {
  let score = 0;

  const name = normalizeProductText(product.name || '');
  const platform = normalizeProductText(product.platform || '');
  const queryWords = normalizeProductText(cleanQuery)
    .split(' ')
    .filter((w) => w.length >= 3);

  if (product.name) score += 8;
  if (product.price && product.price !== 'Fiyat yok') score += 14;
  if (product.link) score += 14;
  if (hasHttpImage(product)) score += 22;
  if (product.rating) score += 6;
  if (product.reviews) score += 6;
  if (platform) score += 4;

  const haystack = `${name} ${platform}`;
  const matchCount = queryWords.filter((w) => haystack.includes(w)).length;

  if (queryWords.length > 0) {
    score += matchCount * 8;

    if (matchCount === 0) score -= 18;
  }

  if (!product.link) score -= 25;
  if (!product.price || product.price === 'Fiyat yok') score -= 20;
  if (!product.name) score -= 30;

  return score;
}

function applyProductQualityPipeline(products = [], cleanQuery = '') {
  let cleaned = (products || [])
    .map((product) => ({
      ...product,
      name: cleanProductName(product.name || ''),
    }))
    .filter((product) => {
      if (!product.name) return false;
      if (!product.link) return false;
      if (!product.price || product.price === 'Fiyat yok') return false;
      return true;
    });

  cleaned = removeDuplicateProducts(cleaned);

  cleaned = cleaned
    .map((product) => ({
      ...product,
      _qualityScore: productQualityScore(product, cleanQuery),
    }))
    .sort((a, b) => b._qualityScore - a._qualityScore)
    .map(({ _qualityScore, ...rest }) => rest);

  return cleaned;
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
  
  const cacheType = `${type}_v3`;

  const cache = await SearchCache.findOne({
    query: cleanQuery,
    type: cacheType,
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
    results = results.filter(hasHttpImage);
    results = applyProductQualityPipeline(results, cleanQuery);
  }

  if (results && results.length > 0) {
    const expireMinutes = getCacheMinutes(type);

    await SearchCache.findOneAndUpdate(
      { query: cleanQuery, type: cacheType },
      {
        query: cleanQuery,
        type: cacheType,
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