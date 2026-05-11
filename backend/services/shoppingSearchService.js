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

async function searchProducts(query, type = 'search') {
  const cleanQuery = String(query || '').trim().toLowerCase();

  if (!cleanQuery) return [];

  console.log("SEARCH START:", cleanQuery, "TYPE:", type);

  // 🔥 Barkod lookup sistemi
const barcodeMatch = cleanQuery.match(/\b\d{8,14}\b/);

if (barcodeMatch) {
  const barcode = barcodeMatch[0];

  try {
    console.log("BARCODE DETECTED:", barcode);

    const foodResponse = await axios.get(
      `https://world.openfoodfacts.org/api/v0/product/${barcode}.json`,
      {
        timeout: 8000,
      }
    );

    const productName =
      foodResponse.data?.product?.product_name ||
      foodResponse.data?.product?.generic_name ||
      '';

    if (productName && productName.trim().length > 2) {
      console.log("OPEN FOOD FACTS PRODUCT:", productName);

      query = productName;
    }
  } catch (err) {
    console.log("OPEN FOOD FACTS FAILED");
  }
}

  const cache = await SearchCache.findOne({
    query: cleanQuery,
    type,
  });

  if (cache) {
    console.log("CACHE HIT:", cleanQuery);
    return cache.data;
  }

  console.log("CACHE MISS:", cleanQuery);

  let results = [];

  try {
    console.log("TRY SERPER...");
    results = await searchSerperShopping(cleanQuery);
    console.log("SERPER RESULT COUNT:", Array.isArray(results) ? results.length : 0);
  } catch (err) {
    logProviderError("SERPER", err);
  }

  if (!results || results.length === 0) {
    try {
      console.log("TRY SERPAPI...");
      results = await searchGoogleShopping(cleanQuery);
      console.log("SERPAPI RESULT COUNT:", Array.isArray(results) ? results.length : 0);
    } catch (err) {
      logProviderError("SERPAPI", err);
    }
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

    console.log("CACHE SAVED:", cleanQuery, "MIN:", expireMinutes);
  }

  return results || [];
}

module.exports = { searchProducts };