const SearchCache = require('../models/SearchCache');
const { searchSerperShopping } = require('./serperShoppingService');
const { searchGoogleShopping } = require('./googleShoppingService');

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

async function searchProducts(query, type = 'search') {
  const cleanQuery = String(query || '').trim().toLowerCase();

  if (!cleanQuery) return [];

  console.log("SEARCH START:", cleanQuery, "TYPE:", type);

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
    const expireMinutes = getCacheMinutes(type);

    await SearchCache.findOneAndUpdate(
      { query: cleanQuery, type },
      {
        query: cleanQuery,
        type,
        data: results,
        expireAt: new Date(Date.now() + expireMinutes * 60 * 1000),
      },
      { upsert: true, new: true }
    );

    console.log("CACHE SAVED:", cleanQuery, "MIN:", expireMinutes);
  }

  return results || [];
}

module.exports = { searchProducts };