const OpenAI = require('openai');
const { searchGoogleShopping } = require('./googleShoppingService');

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

function safeParseJson(text) {
  try {
    const cleaned = String(text)
      .replace(/```json/g, '')
      .replace(/```/g, '')
      .trim();

    return JSON.parse(cleaned);
  } catch (error) {
    console.error('JSON parse error:', error.message);
    console.error('Raw AI response:', text);
    return null;
  }
}

function parsePriceValue(price) {
  if (!price) return Number.MAX_SAFE_INTEGER;

  const cleaned = String(price)
    .replace(/[^\d,.-]/g, '')
    .replace(/\./g, '')
    .replace(',', '.');

  const value = parseFloat(cleaned);
  return isNaN(value) ? Number.MAX_SAFE_INTEGER : value;
}

function sanitizeSearchQuery(query) {
  if (!query) return '';

  return query
    .toLowerCase()
    .replace(/\d+\s*-\s*\d+/g, ' ')
    .replace(/\d+\s*(?:tl)?\s*(?:altı|alti|altında|altinda|alt|üstü|ustu|üzeri|uzeri)/g, ' ')
    .replace(/\d+\s*(?:ile|ila)\s*\d+\s*(?:arası|arasi)?/g, ' ')
    .replace(/\d+\s*(?:e|a)?\s*kadar/g, ' ')
    .replace(/\d+\s*(?:tl)?\s*(?:civarı|civari|civarında|civarinda)/g, ' ')
    .replace(/\d+\s*(?:tl)?\s*(?:bandında|bandinda|bandı|bandi)/g, ' ')
    .replace(/uygun fiyatlı|uygun fiyatli|uygun fiyat|çok pahalı olmasın|cok pahali olmasin|fazla pahalı olmasın|fazla pahali olmasin|çok pahalı değil|cok pahali degil/g, ' ')
    .replace(/öner|oner|bul|göster|goster|istiyorum|arıyorum|ariyorum|olsun|olmalı|olmali/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeText(text = '') {
  return String(text)
    .toLowerCase()
    .replace(/ı/g, 'i')
    .replace(/ğ/g, 'g')
    .replace(/ü/g, 'u')
    .replace(/ş/g, 's')
    .replace(/ö/g, 'o')
    .replace(/ç/g, 'c');
}

function extractQueryKeywords(userMessage, plannerQuery = '') {
  const raw = `${plannerQuery} ${sanitizeSearchQuery(userMessage)}`
    .toLowerCase()
    .split(/\s+/)
    .map((w) => w.trim())
    .filter(Boolean);

  const stopWords = new Set([
    've', 'ile', 'icin', 'için', 'ama', 'veya', 'ya', 'da',
    'en', 'iyi', 'olan', 'olsun', 'gibi', 'bir', 'bu', 'su', 'şu',
    'alti', 'altı', 'ustu', 'üstü', 'kadar', 'civari', 'civarı',
    'bandinda', 'bandında', 'fiyat', 'uygun', 'oner', 'öner', 'goster', 'göster'
  ]);

  return [...new Set(raw.filter((w) => w.length > 1 && !stopWords.has(w)))];
}

function scoreAndRankProducts(products, userMessage, plannerQuery = '') {
  const keywords = extractQueryKeywords(userMessage, plannerQuery);
  const features = extractFeatureKeywords(userMessage);
  const { hasPriceFilter, min, max } = detectPriceIntent(userMessage);

  const scored = (products || []).map((product) => {
    const name = normalizeText(product.name || '');
    const platform = normalizeText(product.platform || '');
    const reason = normalizeText(product.short_reason || '');
    const combined = `${name} ${platform} ${reason}`;

    let score = 0;

    for (const keyword of keywords) {
      const k = normalizeText(keyword);
      if (name.includes(k)) score += 4;
      else if (combined.includes(k)) score += 2;
    }

    for (const feature of features) {
      const f = normalizeText(feature);
      if (combined.includes(f)) score += 3;
    }

    const priceValue = parsePriceValue(product.price);

    if (priceValue !== Number.MAX_SAFE_INTEGER) {
      score += 1;

      if (hasPriceFilter) {
        if (min != null && max != null && priceValue >= min && priceValue <= max) {
          score += 5;
        } else if (max != null && priceValue <= max) {
          score += 4;
        } else if (min != null && priceValue >= min) {
          score += 4;
        } else {
          score -= 8;
        }

        if (min != null && max != null) {
          const center = (min + max) / 2;
          const distance = Math.abs(priceValue - center);
          if (distance <= 250) score += 2;
          else if (distance <= 500) score += 1;
        }
      }
    } else {
      score -= 5;
    }

    if (!product.link) score -= 2;
    if (!product.image) score -= 1;
    if (!product.name) score -= 10;

    return { ...product, _score: score };
  });

  return scored
    .sort((a, b) => b._score - a._score)
    .map(({ _score, ...rest }) => rest);
}

function removeWeakProducts(products, userMessage, plannerQuery = '') {
  const keywords = extractQueryKeywords(userMessage, plannerQuery);

  return (products || []).filter((product) => {
    if (!product || !product.name) return false;

    const text = normalizeText(
      `${product.name} ${product.platform || ''} ${product.short_reason || ''}`
    );

    const keywordMatchCount = keywords.filter((k) =>
      text.includes(normalizeText(k))
    ).length;

    const priceValue = parsePriceValue(product.price);

    if (priceValue === Number.MAX_SAFE_INTEGER) return false;
    if (keywordMatchCount === 0 && keywords.length > 0) return false;

    return true;
  });
}

function extractFeatureKeywords(userMessage) {
  const text = userMessage.toLowerCase();

  const features = [];

  const featureMap = [
    {
      keywords: ['kablosuz', 'wireless', 'bluetooth'],
      value: 'kablosuz',
    },
    {
      keywords: ['mikrofonu iyi', 'iyi mikrofon', 'mikrofon kaliteli', 'mikrofon'],
      value: 'iyi mikrofon',
    },
    {
      keywords: ['oyun için', 'gaming', 'oyuncu', 'gamer'],
      value: 'gaming',
    },
    {
      keywords: ['kulak üstü', 'over ear', 'over-ear'],
      value: 'kulak üstü',
    },
    {
      keywords: ['kulak içi', 'in ear', 'in-ear'],
      value: 'kulak içi',
    },
    {
      keywords: ['gürültü engelleme', 'anc', 'noise cancelling', 'aktif gürültü engelleme'],
      value: 'gürültü engelleme',
    },
    {
      keywords: ['hafif', 'lightweight'],
      value: 'hafif',
    },
    {
      keywords: ['iphone uyumlu', 'iphone ile uyumlu', 'ios uyumlu'],
      value: 'iphone uyumlu',
    },
    {
      keywords: ['android uyumlu', 'android ile uyumlu'],
      value: 'android uyumlu',
    },
    {
      keywords: ['bluetooth 5.3', '5.3'],
      value: 'bluetooth 5.3',
    },
    {
      keywords: ['su geçirmez', 'waterproof'],
      value: 'su geçirmez',
    },
    {
      keywords: ['spor için', 'spor', 'fitness'],
      value: 'spor',
    },
    {
      keywords: ['uzun pil', 'pil ömrü iyi', 'şarjı uzun', 'batarya iyi'],
      value: 'uzun pil ömrü',
    },
  ];


  for (const item of featureMap) {
    if (item.keywords.some((keyword) => text.includes(keyword))) {
      features.push(item.value);
    }
  }

  return [...new Set(features)];
}

function filterProductsByFeatures(products, userMessage) {
  const features = extractFeatureKeywords(userMessage);

  if (features.length === 0) return products;

  return products.filter((product) => {
    const text = `${product.name} ${product.short_reason || ''}`.toLowerCase();

    let score = 0;

    for (const feature of features) {
      if (feature === 'kablosuz' && (text.includes('kablosuz') || text.includes('bluetooth') || text.includes('wireless'))) {
        score++;
      }
      if (feature === 'iyi mikrofon' && text.includes('mikrofon')) {
        score++;
      }
      if (feature === 'gaming' && (text.includes('gaming') || text.includes('oyuncu'))) {
        score++;
      }
      if (feature === 'kulak üstü' && (text.includes('kulak üstü') || text.includes('over ear') || text.includes('over-ear'))) {
        score++;
      }
      if (feature === 'kulak içi' && (text.includes('kulak içi') || text.includes('in ear') || text.includes('in-ear'))) {
        score++;
      }
      if (feature === 'gürültü engelleme' && (text.includes('anc') || text.includes('gürültü engelleme') || text.includes('noise cancelling'))) {
        score++;
      }
      if (feature === 'hafif' && text.includes('hafif')) {
        score++;
      }
      if (feature === 'iphone uyumlu' && (text.includes('iphone') || text.includes('ios'))) {
        score++;
      }
      if (feature === 'android uyumlu' && text.includes('android')) {
        score++;
      }
      if (feature === 'bluetooth 5.3' && text.includes('5.3')) {
        score++;
      }
      if (feature === 'su geçirmez' && (text.includes('su geçirmez') || text.includes('waterproof'))) {
        score++;
      }
      if (feature === 'spor' && text.includes('spor')) {
        score++;
      }
      if (feature === 'uzun pil ömrü' && (text.includes('pil') || text.includes('batarya') || text.includes('şarj'))) {
        score++;
      }
    }

    return score > 0;
  });
}

function filterProductsByGender(products = [], userProfile = null) {
  if (!userProfile || !userProfile.gender) return products;

  const gender = normalizeText(userProfile.gender);

  if (!gender) return products;

  return (products || []).filter((product) => {
    const text = normalizeText(
      `${product.name || ''} ${product.short_reason || ''} ${product.platform || ''}`
    );

    const hasWomenTag =
      text.includes('kadin') ||
      text.includes('bayan') ||
      text.includes('women') ||
      text.includes('female');

    const hasMenTag =
      text.includes('erkek') ||
      text.includes('men') ||
      text.includes('male');

    const hasUnisexTag = text.includes('unisex');

    if (gender.includes('erkek')) {
      if (hasWomenTag && !hasUnisexTag) return false;
      return true;
    }

    if (gender.includes('kadin')) {
      if (hasMenTag && !hasUnisexTag) return false;
      return true;
    }

    return true;
  });
}

async function searchWithFallback(userMessage, plannerQuery) {
  const primaryQuery = sanitizeSearchQuery(plannerQuery || userMessage);
  const fallbackQuery = sanitizeSearchQuery(userMessage);

  let results = [];

  if (primaryQuery) {
    results = await searchGoogleShopping(primaryQuery);
  }

  if ((!results || results.length === 0) && fallbackQuery && fallbackQuery !== primaryQuery) {
    results = await searchGoogleShopping(fallbackQuery);
  }

  return results || [];
}

function filterProductsByPriceIntent(products, userMessage) {
  const { hasPriceFilter, min, max } = detectPriceIntent(userMessage);

  if (!hasPriceFilter) {
    return products;
  }

  return products.filter((product) => {
    const priceValue = parsePriceValue(product.price);

    if (priceValue === Number.MAX_SAFE_INTEGER) return false;
    if (min != null && priceValue < min) return false;
    if (max != null && priceValue > max) return false;

    return true;
  });
}

function filterProductsByExplicitRange(products, min, max) {
  return (products || []).filter((product) => {
    const priceValue = parsePriceValue(product.price);

    if (priceValue === Number.MAX_SAFE_INTEGER) return false;
    if (min != null && priceValue < min) return false;
    if (max != null && priceValue > max) return false;

    return true;
  });
}

function detectPriceIntent(userMessage) {
  const text = userMessage.toLowerCase().replace(/\./g, '').replace(/,/g, '.');

  let min = null;
  let max = null;
  let hasPriceFilter = false;

  // 2000-3000
  const dashRangeMatch = text.match(/(\d+)\s*-\s*(\d+)/);

  if (dashRangeMatch) {
    min = parseInt(dashRangeMatch[1], 10);
    max = parseInt(dashRangeMatch[2], 10);
    hasPriceFilter = true;
  }

  // 1500 ile 2500 arası
  const betweenMatch = text.match(
    /(\d+)\s*(?:ile|ila)\s*(\d+)\s*(?:arası|arasi)?/
  );

  if (!hasPriceFilter && betweenMatch) {
    min = parseInt(betweenMatch[1], 10);
    max = parseInt(betweenMatch[2], 10);
    hasPriceFilter = true;
  }

  // 1000 tl altı
  const belowMatch = text.match(
    /(\d+)\s*(?:tl)?\s*(?:altı|alti|altinda|altında|alt)/
  );

  if (!hasPriceFilter && belowMatch) {
    max = parseInt(belowMatch[1], 10);
    hasPriceFilter = true;
  }

  // 3000 tl üstü
  const aboveMatch = text.match(
    /(\d+)\s*(?:tl)?\s*(?:üstü|ustu|üzeri|uzeri)/
  );

  if (!hasPriceFilter && aboveMatch) {
    min = parseInt(aboveMatch[1], 10);
    hasPriceFilter = true;
  }

  // 3000'e kadar / 3000 e kadar
  const untilMatch = text.match(/(\d+)\s*(?:e|a)?\s*kadar/);

  if (!hasPriceFilter && untilMatch) {
    max = parseInt(untilMatch[1], 10);
    hasPriceFilter = true;
  }

  // 2500 civarı / 2500 civarında
  const aroundMatch = text.match(/(\d+)\s*(?:tl)?\s*(?:civarı|civari|civarında|civarinda)/);

  if (!hasPriceFilter && aroundMatch) {
    const center = parseInt(aroundMatch[1], 10);
    min = Math.max(0, center - 500);
    max = center + 500;
    hasPriceFilter = true;
  }

  // 2000 bandında / 2000 bandi
  const bandMatch = text.match(/(\d+)\s*(?:tl)?\s*(?:bandında|bandinda|bandı|bandi)/);

  if (!hasPriceFilter && bandMatch) {
    const center = parseInt(bandMatch[1], 10);
    min = Math.max(0, center - 500);
    max = center + 500;
    hasPriceFilter = true;
  }

  // "uygun fiyatlı" / "çok pahalı olmasın"
  if (!hasPriceFilter) {
    if (
      text.includes('uygun fiyat') ||
      text.includes('uygun fiyatlı') ||
      text.includes('uygun fiyatli') ||
      text.includes('çok pahalı olmasın') ||
      text.includes('cok pahali olmasin') ||
      text.includes('fazla pahalı olmasın') ||
      text.includes('fazla pahali olmasin') ||
      text.includes('çok pahalı değil') ||
      text.includes('cok pahali degil')
    ) {
      max = 3000;
      hasPriceFilter = true;
    }
  }

  return { hasPriceFilter, min, max };
}

function expandPriceRange(min, max, level = 1) {
  if (min == null && max == null) {
    return { min, max };
  }

  if (min != null && max != null) {
    if (level === 1) {
      return {
        min: Math.max(0, min - 200),
        max: max + 200,
      };
    }

    return {
      min: Math.max(0, min - 500),
      max: max + 500,
    };
  }

  if (max != null) {
    if (level === 1) {
      return { min: null, max: max + 200 };
    }

    return { min: null, max: max + 500 };
  }

  if (min != null) {
    if (level === 1) {
      return { min: Math.max(0, min - 200), max: null };
    }

    return { min: Math.max(0, min - 500), max: null };
  }

  return { min, max };
}


function normalizeProducts(products) {
  return (products || []).map((item, index) => ({
    index: index + 1,
    name: item.name || '',
    price: item.price || '',
    platform: item.platform || '',
    image: item.image || '',
    link: item.link || '',
    rating: item.rating || null,
    reviews: item.reviews || null,
    short_reason: item.short_reason || item.shortReason || '',
  }));
}

function enrichProductsWithSource(products = [], sourceProducts = []) {
  if (!Array.isArray(products) || products.length === 0) return [];
  if (!Array.isArray(sourceProducts) || sourceProducts.length === 0) {
    return normalizeProducts(products);
  }

  const normalizedProducts = normalizeProducts(products);
  const normalizedSource = normalizeProducts(sourceProducts);

  return normalizedProducts.map((product, index) => {
    let sourceMatch = null;

    if (typeof product.index === 'number' && product.index > 0) {
      sourceMatch = normalizedSource[product.index - 1] || null;
    }

    if (!sourceMatch && product.name) {
      const targetName = normalizeText(product.name);
      sourceMatch =
          normalizedSource.find((item) =>
            normalizeText(item.name || '') === targetName
          ) ||
          normalizedSource.find((item) =>
            normalizeText(item.name || '').includes(targetName) ||
            targetName.includes(normalizeText(item.name || ''))
          ) ||
          null;
    }

    if (!sourceMatch) {
      sourceMatch = normalizedSource[index] || null;
    }

    return {
      ...product,
      price: product.price || sourceMatch?.price || '',
      platform: product.platform || sourceMatch?.platform || '',
      image: product.image || sourceMatch?.image || '',
      link: product.link || sourceMatch?.link || '',
      rating: product.rating || sourceMatch?.rating || null,
      reviews: product.reviews || sourceMatch?.reviews || null,
      short_reason: product.short_reason || sourceMatch?.short_reason || '',
    };
  });
}

function buildFallbackActions(products = [], planner = {}, userMessage = '') {
  if (!products || products.length === 0) {
    return [];
  }

  const sameCategoryProducts = filterProductsToSameCategory(products, userMessage);
  const actions = [];

  if (sameCategoryProducts.length >= 2) {
    actions.push('Karşılaştır');
  }

  actions.push('Benzer ürünler');
  actions.push('Daha ucuz alternatifler');

  return [...new Set(actions)].slice(0, 4);
}

function isComparisonLikeRequest(userMessage = '') {
  const text = String(userMessage).toLowerCase().trim();

  return (
    text === 'karşılaştır' ||
    text === 'karsilastir' ||
    text.includes('bunları karşılaştır') ||
    text.includes('bunlari karsilastir') ||
    text.includes('şunları karşılaştır') ||
    text.includes('sunlari karsilastir') ||
    text.includes('hangisini alayım') ||
    text.includes('hangisini alayim') ||
    text.includes('hangisi daha iyi') ||
    text.includes('en iyisi hangisi')
  );
}



function buildComparisonData(answer, finalProducts = [], userMessage = '') {
  
  
  const isComparisonRequest = isComparisonLikeRequest(userMessage);

  if (!isComparisonRequest) {
    return null;
  }

  const compareProducts = normalizeProducts(
    filterProductsToSameCategory(finalProducts || [], userMessage)
  )
    .slice(0, 4)
    .map((p) => ({
      name: p.name || '',
      price: p.price || '',
      platform: p.platform || '',
      image: p.image || p.thumbnail || p.productImage || '',
      link: p.link || '',
      short_reason: p.short_reason || '',
      rating: p.rating || null,
      reviews: p.reviews || null,
    }));

  if (compareProducts.length === 0) {
    return null;
  }

  const winner = compareProducts[0]?.name || '';

  const highlights = compareProducts
    .slice(0, 3)
    .map((p) => p.short_reason)
    .filter(Boolean)
    .slice(0, 3);

  return {
    summary: answer.assistant_text || '',
    winner,
    highlights,
    products: compareProducts,
  };
}

function resolveProductReference(userMessage = '', recentProducts = []) {
  const text = String(userMessage).toLowerCase();

  if (!recentProducts || recentProducts.length === 0) {
    return null;
  }

  if (
    text.includes('ilk ürün') ||
    text.includes('1. ürün') ||
    text.includes('birinci ürün')
  ) {
    return recentProducts[0] || null;
  }

  if (
    text.includes('ikinci ürün') ||
    text.includes('2. ürün')
  ) {
    return recentProducts[1] || null;
  }

  if (
    text.includes('üçüncü ürün') ||
    text.includes('3. ürün')
  ) {
    return recentProducts[2] || null;
  }

  if (
    text.includes('en ucuz') ||
    text.includes('daha ucuz olan')
  ) {
    const sorted = [...recentProducts].sort(
      (a, b) => parsePriceValue(a.price) - parsePriceValue(b.price)
    );
    return sorted[0] || null;
  }

  if (
    text.includes('son ürün') ||
    text.includes('az önceki ürün')
  ) {
    return recentProducts[recentProducts.length - 1] || null;
  }

  return null;
}

function buildReferenceBasedReply(userMessage = '', referencedProduct = null) {
  if (!referencedProduct) return null;

  const text = String(userMessage).toLowerCase();

  if (text.includes('benzer')) {
    return {
      mode: 'similar',
      searchQuery: referencedProduct.name || '',
      assistantText: `"${referencedProduct.name}" ürününe benzer seçenekleri getiriyorum.`,
    };
  }

  if (
    text.includes('karşılaştır') ||
    text.includes('hangisi daha iyi') ||
    text.includes('hangisini alayım') ||
    text.includes('hangisini alayim')
  ) {
    return {
      mode: 'compare_reference',
      assistantText: `"${referencedProduct.name}" ürününü baz alarak karşılaştırma yapıyorum.`,
    };
  }

  if (
    text.includes('daha ucuz') ||
    text.includes('ucuzunu göster') ||
    text.includes('ucuz alternatif')
  ) {
    return {
      mode: 'cheaper',
      searchQuery: referencedProduct.name || '',
      assistantText: `"${referencedProduct.name}" ürününe göre daha uygun fiyatlı alternatifler bakıyorum.`,
    };
  }

  return {
    mode: 'info',
    assistantText: `"${referencedProduct.name}" ürününü baz alıyorum.`,
  };
}

function extractRecentProducts(previousMessages = []) {
  const assistantMessages = previousMessages
    .filter((m) => m.role === 'assistant' && Array.isArray(m.products) && m.products.length > 0)
    .slice(-8);

  let recentProducts = [];

  for (const msg of assistantMessages) {
    recentProducts = [...recentProducts, ...msg.products];
  }

  return normalizeProducts(recentProducts).slice(0, 24);
}

function formatHistory(previousMessages = []) {
  return previousMessages
    .slice(-24)
    .map((m) => `${m.role === 'user' ? 'Kullanıcı' : 'Asistan'}: ${m.text}`)
    .join('\n');
}

async function generatePlanner({
  userMessage,
  previousMessages = [],
  userProfile = null,
  favoriteProducts = [],
}) {
  const profileText = formatUserProfile(userProfile);
  const preferenceSummary = buildUserPreferenceSummary(previousMessages, favoriteProducts);
  const historyText = formatHistory(previousMessages);
  const recentProducts = extractRecentProducts(previousMessages);

  const plannerPrompt = `
  Sen Shopi'sin. Akıllı bir alışveriş asistanısın.
  Görevin kullanıcının son mesajını sınıflandırmak ve gerekiyorsa kısa, doğru bir arama yönü çıkarmaktır.
  
  Öncelik sırası:
  1. Kullanıcının ana ürün tipini doğru anla.
  2. Gereksiz soru sormadan yeterli bilgi varsa ürün aramasına geç.
  3. Kullanıcıyı alakasız ürün sınıflarına kaydırma.
  4. Sadece gerçekten kritik eksik bilgi varsa tek bir netleştirme sorusu sor.
  
  Ana intent türleri:
  - "general_question" = alışveriş dışı soru veya genel sohbet
  - "product_search" = yeni ürün önerisi / ürün arama isteği
  - "comparison" = mevcut ürünleri kıyaslama isteği
  - "refinement" = önceki aramayı daraltma / bütçe / marka / özellik değiştirme
  - "best_choice" = önceki ürünler arasından en iyi / en ucuz / fiyat-performans seçimi
  
  shopping_relevance alanı:
  - "high" = doğrudan alışveriş / ürün / bütçe / marka / özellik / satın alma kararı
  - "medium" = alışverişe bağlanabilecek ama net olmayan istek
  - "low" = zayıf bağlantı
  - "none" = alışveriş dışı
  
 Netleştirme kuralları:

- needs_clarification sadece gerçekten kritik bilgi eksikse true olsun.

- Kullanıcı yalnızca çok geniş bir ana ürün tipi söylediyse needs_clarification=true yap.
- Çok geniş ana ürün tiplerine örnek: ayakkabı, sneaker, saat, ceket, mont, çanta, telefon, tablet, kulaklık, çatal seti.
- Bu durumda ilk netleştirme sorusu ürünün kullanım amacı, tarzı, alt türü veya temel beklentisini anlamaya yönelik olsun.
- Örneğin kullanıcı sadece "ayakkabı" dediyse günlük mü, spor mu, şık mı gibi kullanım amacı sorulabilir.
- Kullanıcı sadece "çatal seti" dediyse klasik / modern gibi tarz veya günlük / misafir için gibi kullanım amacı sorulabilir.

- Kullanıcı ilk netleştirme sorusuna cevap verdiyse hemen ürün önerme.
- İkinci aşamada mümkünse tek bir kritik bilgi daha iste:
  - marka tercihi
  - bütçe aralığı
  - kullanım bağlamı
- İkinci netleştirme sorusu kısa ve tek odaklı olsun.

- Kullanıcı iki tur boyunca yeterli sinyal verdiyse artık needs_clarification=false yap ve ürün aramaya geç.
- Aynı sohbet içinde ikiden fazla netleştirme sorusu sorma.
- Kullanıcı yeterli bilgi verdikten sonra tekrar tekrar soru sorma.
- Aynı konuşmada kullanıcı önceki sorulara cevap verdiyse aynı tür soruları tekrar sorma.

- Kullanıcı kategori + marka + kullanım amacı + bütçe gibi alanlardan en az 2 tanesini verdiyse ürün aramaya yatkın ol.
- Ancak kategori çok genişse ve hala kritik bir eksik varsa, ürün aramadan önce tek bir kısa netleştirme daha sorabilirsin.

- Kullanıcı ana ürün tipini net söylediyse sırf alt kategori eksik diye gereksiz soru sorma.

- Kullanıcı "direkt öner", "soru sorma", "uzatma", "hemen göster" gibi bir ifade kullanırsa needs_clarification=false olmaya güçlü şekilde yatkın ol.

- needs_clarification true ise kullanıcıya sorulacak tek, doğal, kısa ve kritik bir soru üret.
- clarification_question alanına yaz.
- clarification_question asla uzun olmasın.
  
  Ana ürün tipi koruma kuralları:
  - Kullanıcı çekirdek bir ürün tipi söylediyse önce o ana ürün sınıfını koru.
  - Ana ürün tipi netse bunu alakasız yan ürün, aksesuar, organizer, dolap, raf, stand, bakım ürünü veya mobilyaya genişletme.
  - Örneğin kullanıcı "ayakkabı", "sneaker", "koşu ayakkabısı", "bot", "sandalet", "terlik" diyorsa aramayı giyilebilir ayakkabı ürünleri içinde tut.
  - Kullanıcı "kulaklık" diyorsa kulaklık kabı, standı, aparatı gibi yan ürünlere kayma.
  - Kullanıcı "telefon" diyorsa telefon aksesuarlarına kayma.
  - Kullanıcı açıkça aksesuar, organizer, stand, dolap, raf, bakım ürünü veya yardımcı ekipman istemediyse bunları önerme.
  - Kullanıcının söylediği ana ürün tipi search_query içinde korunmalı.
  
  Örnek ana ürün tipi sınıfları:
  - footwear = ayakkabı, sneaker, koşu ayakkabısı, bot, loafer, terlik, sandalet
  - audio = kulaklık, headset, earbuds, hoparlör
  - phone = telefon, akıllı telefon
  - bag = çanta, sırt çantası, omuz çantası, valiz
  - beauty = kapatıcı, maskara, fondöten, serum, krem
  - apparel = tişört, gömlek, mont, pantolon, elbise
  
  Profil ve geçmiş kullanımı:
  - Kullanıcının davranışsal özeti, genel önerilerde fiziksel profil bilgisinden daha önceliklidir.
  - Boy, kilo, beden ve numara bilgisini sadece gerçekten gerekli olduğunda kullan.
  - Kullanıcı yeni sohbette bile genel öneri istiyorsa geçmiş ilgi alanlarını dikkate al.
  - Eğer kullanıcı profili varsa ve bu profil ilgili kategori için güçlü sinyal sağlıyorsa clarification yerine direkt ürün aramaya daha yatkın olabilirsin.
  - Ancak kullanıcı profili alakasızsa sadece profil var diye direkt ürün arama.
  - Ayakkabı, giyim, stil ve kombin isteklerinde kullanıcı profilini yardımcı sinyal olarak kullanabilirsin.
  - Profil bilgisi varsa gereksiz tekrar yapma.
  
  Önceki ürünlere referans:
  - Eğer kullanıcı önceki ürünlere atıf yapıyorsa bunu anlamaya çalış.
  - "bunlardan", "en iyisi", "2. ürün", "4. ürün", "en ucuz" gibi ifadeleri dikkate al.
  - Eğer önceki ürünleri kullanmak yeterliyse needs_product_search=false yap.
  
  Fiyat ve özellik kuralları:
  - Kullanıcı fiyat aralığı verirse bunu dikkatli analiz et.
  - Örnekler:
    - "1000 tl altı"
    - "2000-3000 tl arası"
    - "1500 ile 2500 arası"
    - "3000 tl üstü"
    - "2500 civarı" ≈ yaklaşık 2000-3000 bandı
    - "2000 bandında" ≈ yaklaşık 1500-2500 bandı
    - "3000'e kadar" = 3000 altı
  - "uygun fiyatlı" veya "çok pahalı olmasın" gibi ifadeleri bütçe hassasiyeti olarak yorumla.
  - Kullanıcının ürün özelliği isteklerini dikkatle analiz et.
  - Örnek özellikler:
    - kablosuz
    - mikrofonu iyi
    - gaming
    - kulak üstü
    - kulak içi
    - gürültü engelleme
    - hafif
    - iphone uyumlu
    - android uyumlu
    - bluetooth 5.3
    - su geçirmez
    - spor için
    - uzun pil ömrü
  
  Arama sorgusu üretme kuralları:
  - needs_product_search=true ise kısa ve net bir search_query üret.
  - search_query içinde ana ürün tipini koru.
  - search_query içine alakasız aksesuar veya yan ürün sınıfı sokma.
  - search_query üretirken fiyat bilgisini yazma.
  - Sadece ürün tipi, marka, kullanım amacı ve temel özellikleri yaz.
  - Eğer kullanıcı yeni fiyat filtresi verdiyse bu refinement veya product_search olabilir; fiyat filtreleme backend tarafından ayrıca yapılacak.
  
  Ek davranış kuralları:
  - Eğer kullanıcı alışveriş dışı bir şey soruyorsa intent'i "general_question" yap.
  - Alışveriş dışı sorularda needs_product_search=false yap.
  - Küçük gündelik sohbetlerde small_talk=true olabilir.
  - Küçük sohbet mesajlarında ürün arama zorlama.
  - Kullanıcı belirli özellikler istediyse bunlara en uygun ürünleri öne çıkar.
  - Eğer bazı ürünler özelliklere daha çok uyuyorsa bunu short_reason içinde belirt.
  - Eğer ürün listesi döndürülürse actions alanı için şu seçeneklere uygun davran:
    "En iyisini seç"
    "Karşılaştır"
    "Daha ucuz alternatifler"
    "Benzer ürünler"
  
  Çıktı kuralları:
  - Sadece geçerli JSON döndür.
  - Markdown kullanma.
  
  JSON formatı:
  {
    "intent": "general_question",
    "shopping_relevance": "none",
    "needs_product_search": false,
    "needs_clarification": false,
    "clarification_question": "",
    "search_query": "",
    "uses_recent_products": false,
    "small_talk": false
  }
  
  Sohbet geçmişi:
  ${historyText || 'Yok'}
  
  Önceki ürünler:
  ${JSON.stringify(recentProducts, null, 2)}
  
  Kullanıcı davranış özeti:
  ${preferenceSummary}
  
  Kullanıcı profili:
  ${profileText}
  
  Kullanıcının son mesajı:
  ${userMessage}
  `;

  const response = await client.chat.completions.create({
    model: 'gpt-4.1-mini',
    messages: [{ role: 'user', content: plannerPrompt }],
    temperature: 0.2,
  });

  const text = response.choices[0].message.content;
const parsed = safeParseJson(text);

return parsed || {
  intent: 'general_question',
  shopping_relevance: 'none',
  needs_product_search: false,
  needs_clarification: false,
  clarification_question: '',
  search_query: '',
  uses_recent_products: false,
  small_talk: false,
};
}

async function generateAnswer({
  userMessage,
  previousMessages = [],
  planner,
  searchedProducts = [],
  userProfile = null,
  favoriteProducts = [],
}) {
  const profileText = formatUserProfile(userProfile);
  const preferenceSummary = buildUserPreferenceSummary(previousMessages, favoriteProducts);
  const historyText = formatHistory(previousMessages);
  const recentProducts = extractRecentProducts(previousMessages);
  const normalizedSearchedProducts = normalizeProducts(searchedProducts);

  const answerPrompt = `
Sen Shopi’sin. Kullanıcılara ürün bulma, karşılaştırma ve alışveriş kararlarında yardımcı olan akıllı ve samimi bir asistansın.
Türkçe cevap ver.
Samimi ama profesyonel ol.
Kullanıcıyla ChatGPT gibi doğal konuş.

Kurallar:
- Bu uygulama yalnızca alışveriş ve ürün önerileri için tasarlanmıştır.
- Eğer kullanıcı alışveriş dışı bir şey sorarsa bunu kibarca belirt.
- Alışveriş dışı sorularda kısa ve net şekilde, bu uygulamanın ürün bulma ve karşılaştırma konusunda yardımcı olduğunu söyle.
- Alışveriş dışı konularda uzun genel bilgi verme.
- Eğer ürün döndürüyorsan her ürün için mutlaka "short_reason" alanı üretmek zorundasın.
- short_reason her ürün için farklı olsun.
- short_reason doğal, spesifik ve kullanıcı isteğine uygun olsun.
- Kullanıcının davranışsal özeti, genel ürün önerilerinde beden/boy/kilo gibi profil alanlarından daha önceliklidir.
- Kullanıcı kendi ilgi alanlarını sormuyorsa profil bilgilerini doğrudan söyleme.
- Genel önerilerde önce davranışsal tercihleri kullan, profil bilgilerini sadece gerekiyorsa ince ayar olarak kullan.
- Yeni sohbet açılmış olsa bile geçmiş sohbet davranışlarını alışveriş hafızası olarak dikkate al.
- Eğer kullanıcı profili varsa ürün önerirken bunu dikkate al.
- Cinsiyet bilgisi varsa özellikle giyim, ayakkabı, çanta, aksesuar ve parfüm önerilerinde bunu dikkate al.
- Eğer cinsiyet bilgisi varsa alakasız kadın/erkek karışık ürünler gösterme.
- Uygun olduğunda unisex seçenekler de sunabilirsin.
- Ayakkabı önerilerinde ayakkabı numarasını göz önünde bulundur.
- Giyim ürünlerinde beden bilgisini dikkate al.
- Stil / tarz bilgisi varsa önerileri buna göre kişiselleştir.
- Boy ve kilo bilgisi varsa özellikle giyim ve stil önerilerinde bunu yardımcı sinyal olarak kullan.
- Profil bilgisi varsa bunu kullanıcıya hissettirmeden doğal şekilde önerilere yansıt.
- Klişe ifadeler kullanma.
- "İyi bir seçenek", "öne çıkan ürün" gibi genel tekrarlar kullanma.
- Her ürünün neden önerildiğini kısa ama özgün şekilde açıkla.
- Kısa ama faydalı cevap ver.
- Eğer ürünler sunuyorsan önce kısa bir açıklama yap.
- Kullanıcı "en iyisi hangisi" dediyse net bir öneri ver.
- Kullanıcı "karşılaştır" dediyse avantaj/dezavantaj şeklinde anlat.
- Kullanıcı genel soru sorduysa ürün zorlamadan cevap ver.
- Eğer kullanıcı belirli bir fiyat aralığı verdiyse, o aralığa uygun ürünleri önceliklendir.
- Eğer ürünler verilen bütçeye tam uymuyorsa bunu dürüstçe belirt.
- Ürün yoksa products boş dizi olabilir.
- Mevcut ürün bağlamını kullan.
- Cevabın sonunda gereksiz tekrar yapma.
- Eğer kullanıcı seçili bir ürün hakkında özellik soruyorsa uzun paragraf yazma.
- Cevabı en fazla 4 kısa madde halinde ver.
- Her madde kısa olsun.
- Eğer yorum soruyorsa "Genel yorum", "Beğenilenler", "Dikkat edilmesi gerekenler" şeklinde kısa satırlar ver.
- Eğer satıcı soruyorsa varsa farklı mağazaları kısa liste halinde ver.
- Göz yoran uzun metinlerden kaçın.
- Ürün detay cevaplarında düz paragraf yerine kısa maddeler kullan.
- Markdown tablo kullanma.
- Her satır kısa ve okunabilir olsun.
- Sadece JSON döndür.
- Markdown kullanma.

JSON formatı:
{
  "assistant_text": "doğal cevap",
  "products": [
    {
      "index": 1,
      "name": "ürün adı",
      "price": "fiyat",
      "platform": "mağaza",
      "image": "görsel url",
      "link": "ürün linki",
      "rating": 4.5,
      "reviews": 120,
      "short_reason": "bu ürünün neden önerildiğini doğal ve özgün şekilde açıkla"
    }
  ],
  "actions": []
}

Intent:
${planner.intent}

Yeni ürün araması yapıldı mı:
${planner.needs_product_search}

Sohbet geçmişi:
${historyText || 'Yok'}

Kullanıcı davranış özeti:
${preferenceSummary}

Kullanıcı profili:
${profileText}

Önceki ürünler:
${JSON.stringify(recentProducts, null, 2)}

Yeni arama sonucu ürünler:
${JSON.stringify(normalizedSearchedProducts, null, 2)}

Kullanıcının son mesajı:
${userMessage}
`;

  const response = await client.chat.completions.create({
    model: 'gpt-4.1-mini',
    messages: [{ role: 'user', content: answerPrompt }],
    temperature: 0.7,
  });

  const text = response.choices[0].message.content;
const parsed = safeParseJson(text);

return parsed || {
  assistant_text: 'Bir hata oldu ama yardımcı olmaya devam edebilirim. İstersen isteğini biraz daha kısa yaz.',
  products: [],
  actions: [],
};
}

function normalizeActionLabel(text = '') {
  return normalizeText(String(text).trim());
}

function detectActionCommand(userMessage = '') {
  const text = normalizeActionLabel(userMessage);

  if (text === 'karsilastir') return 'compare';
  if (text === 'benzer urunler') return 'find_similar';
  if (text === 'daha ucuz alternatifler') return 'find_cheaper';

  return null;
}

function extractLastProductBatch(previousMessages = []) {
  for (let i = previousMessages.length - 1; i >= 0; i--) {
    const msg = previousMessages[i];

    if (
      msg &&
      msg.role === 'assistant' &&
      Array.isArray(msg.products) &&
      msg.products.length > 0
    ) {
      return normalizeProducts(msg.products);
    }
  }

  return [];
}

function scoreProductForWinner(product) {
  let score = 0;

  const price = parsePriceValue(product.price);
  if (price !== Number.MAX_SAFE_INTEGER) score += 2;
  if (product.rating) score += product.rating * 2;
  if (product.reviews) {
    const reviewsBoost = Math.min(product.reviews / 1000, 5);
    score += reviewsBoost;
  }
  if (product.short_reason) score += 1;
  if (product.link) score += 1;
  if (product.image) score += 1;

  return score;
}

function selectWinnerProduct(products = []) {
  if (!products.length) return null;

  const scored = [...products].map((p) => ({
    ...p,
    _winnerScore: scoreProductForWinner(p),
  }));

  scored.sort((a, b) => b._winnerScore - a._winnerScore);

  const { _winnerScore, ...winner } = scored[0];
  return winner;
}

function buildDeterministicComparison(products = []) {
  if (!products || products.length < 2) return null;

  const normalized = normalizeProducts(products).slice(0, 4);
  const winner = selectWinnerProduct(normalized);

  if (!winner) return null;

  const highlights = [];

  if (winner.rating) {
    highlights.push(`${winner.name} puan tarafında öne çıkıyor.`);
  }

  if (winner.reviews) {
    highlights.push(`${winner.name} yorum sayısı ile daha güven veriyor.`);
  }

  const validPriceProducts = normalized.filter(
    (p) => parsePriceValue(p.price) !== Number.MAX_SAFE_INTEGER
  );

  if (validPriceProducts.length >= 2) {
    const cheapest = [...validPriceProducts].sort(
      (a, b) => parsePriceValue(a.price) - parsePriceValue(b.price)
    )[0];

    if (cheapest && cheapest.name !== winner.name) {
      highlights.push(`${cheapest.name} fiyat tarafında daha avantajlı görünüyor.`);
    }
  }

  if (highlights.length === 0) {
    highlights.push(`${winner.name} genel denge açısından daha mantıklı görünüyor.`);
  }

  return {
    summary: `${winner.name} genel denge açısından en güçlü seçenek gibi duruyor.`,
    winner: winner.name || '',
    highlights: highlights.slice(0, 3),
    products: normalized.map((p) => ({
      name: p.name || '',
      price: p.price || '',
      platform: p.platform || '',
      image: p.image || '',
      link: p.link || '',
      short_reason: p.short_reason || '',
      rating: p.rating || null,
      reviews: p.reviews || null,
    })),
  };
}

function normalizeActions(actions) {
  if (!actions) return [];

  if (Array.isArray(actions)) {
    return actions
      .map((item) => String(item).trim())
      .filter((item) => item.length > 0);
  }

  if (typeof actions === 'string') {
    const text = actions.trim();

    try {
      const parsed = JSON.parse(text);
      if (Array.isArray(parsed)) {
        return parsed
          .map((item) => String(item).trim())
          .filter((item) => item.length > 0);
      }
    } catch (_) {}

    return text
      .replace(/^\[/, '')
      .replace(/\]$/, '')
      .split(',')
      .map((item) => item.replace(/['"]/g, '').trim())
      .filter((item) => item.length > 0);
  }

  return [];
}

function buildCrossChatMemory(currentChat, allChats = []) {
  const currentChatId = String(currentChat?._id || '');

  const currentMessages = Array.isArray(currentChat?.messages)
    ? currentChat.messages
    : [];

  const otherMessages = allChats
    .filter((c) => String(c._id) !== currentChatId)
    .sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt))
    .flatMap((c) =>
      Array.isArray(c.messages)
        ? c.messages.map((m) => ({
            ...m.toObject?.() || m,
            _sourceChatId: String(c._id),
          }))
        : []
    );

  const normalizedCurrentMessages = currentMessages.map((m) => ({
    ...m.toObject?.() || m,
    _sourceChatId: currentChatId,
  }));

  // Önce diğer sohbetlerden son hafıza, sonra aktif sohbetin tamamı
  const merged = [
    ...otherMessages.slice(-40),
    ...normalizedCurrentMessages,
  ];

  // Çok uzamasın
  return merged.slice(-60);
}


function extractRecentProductsForComparison(previousMessages = [], limit = 6) {
  const collected = [];

  for (let i = previousMessages.length - 1; i >= 0; i--) {
    const msg = previousMessages[i];

    if (
      msg &&
      msg.role === 'assistant' &&
      Array.isArray(msg.products) &&
      msg.products.length > 0
    ) {
      for (const product of msg.products) {
        if (!product || !product.name) continue;
        collected.push(product);
      }
    }

    if (collected.length >= limit * 2) break;
  }

  const seen = new Set();
  const unique = [];

  for (const product of collected) {
    const key =
      product.link ||
      `${product.name}-${product.price || ''}-${product.platform || ''}`;

    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(product);
  }

  return unique.slice(0, limit);
}

function extractLatestAssistantProductBatch(previousMessages = []) {
  for (let i = previousMessages.length - 1; i >= 0; i--) {
    const msg = previousMessages[i];

    if (
      msg &&
      msg.role === 'assistant' &&
      Array.isArray(msg.products) &&
      msg.products.length > 0
    ) {
      return normalizeProducts(msg.products);
    }
  }

  return [];
}

function detectCategoryFromText(text = '') {
  const t = normalizeText(text);

  if (t.includes('kulaklik')) return 'kulaklik';
  if (t.includes('telefon')) return 'telefon';
  if (t.includes('mouse')) return 'mouse';
  if (t.includes('klavye')) return 'klavye';
  if (t.includes('tablet')) return 'tablet';
  if (t.includes('sarj') || t.includes('powerbank')) return 'sarj';
  if (t.includes('parfum')) return 'parfum';
  if (t.includes('kapatici') || t.includes('makyaj')) return 'kozmetik';
  if (t.includes('ayakkabi')) return 'ayakkabi';

  return null;
}

function getProductCategory(product = {}) {
  return detectCategoryFromText(
    `${product.name || ''} ${product.short_reason || ''}`
  );
}

function filterProductsToSameCategory(products = [], fallbackText = '') {
  if (!products.length) return [];

  const categoryCounts = {};

  for (const product of products) {
    const category = getProductCategory(product) || detectCategoryFromText(fallbackText);
    if (!category) continue;
    categoryCounts[category] = (categoryCounts[category] || 0) + 1;
  }

  const bestCategory =
    Object.entries(categoryCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ||
    detectCategoryFromText(fallbackText);

  if (!bestCategory) return products.slice(0, 4);

  return products.filter((p) => getProductCategory(p) === bestCategory).slice(0, 4);
}

function isSimilarRequest(userMessage = '') {
  const text = normalizeText(userMessage);
  return (
    text === 'benzer urunler' ||
    text.includes('benzer urun') ||
    text.includes('benzerini goster')
  );
}

function isBestChoiceRequest(userMessage = '') {
  const text = normalizeText(userMessage);
  return (
    text === 'en iyisini sec' ||
    text.includes('en iyisini sec') ||
    text.includes('en iyi secim') ||
    text.includes('hangisini alayim') ||
    text.includes('hangisi daha iyi')
  );
}

function isCheaperRequest(userMessage = '') {
  const text = normalizeText(userMessage);
  return (
    text === 'daha ucuz alternatifler' ||
    text.includes('daha ucuz') ||
    text.includes('ucuz alternatif')
  );
}


async function generateChatReply({
  userMessage,
  previousMessages = [],
  selectedProduct = null,
  userProfile = null,
  favoriteProducts = [],
})

{
  if (selectedProduct) {
    console.log(
      "SELECTED PRODUCT FLOW ACTIVE FOR:",
      selectedProduct ? selectedProduct.name : null
    );
    console.log("SELECTED PRODUCT USER MESSAGE:", userMessage);
    console.log(
      "SELECTED PRODUCT SELLER INTENT:",
      isSellerComparisonRequest(userMessage)
    );
  
    if (isSellerComparisonRequest(userMessage)) {
      const sellerComparison = await buildSellerComparisonFromSearch({
        baseProduct: selectedProduct,
      });
  
      if (!sellerComparison) {
        return {
          assistantText: `"${selectedProduct?.name || 'Bu ürün'}" için farklı satıcıları bulamadım.`,
          products: [],
          actions: [],
          comparison: null,
          detailCard: null,
          reviewCard: null,
          sellerComparison: null,
        };
      }
  
      return {
        assistantText: `"${selectedProduct?.name || 'Bu ürün'}" için farklı satıcıları buldum.`,
        products: [],
        actions: [],
        comparison: null,
        detailCard: null,
        reviewCard: null,
        sellerComparison,
      };
    }
  
    if (isReviewRequest(userMessage)) {
      const reviewResult = await generateSelectedProductReviews({
        selectedProduct,
        userMessage,
        userProfile,
      });
  
      return {
        assistantText: 'Yorum özetini hazırladım.',
        products: [],
        actions: [],
        comparison: null,
        detailCard: null,
        reviewCard: {
          product: {
            name: selectedProduct?.name || '',
            price: selectedProduct?.price || '',
            platform: selectedProduct?.platform || '',
            image: selectedProduct?.image || '',
            link: selectedProduct?.link || '',
          },
          title: reviewResult.title || 'Yorum özeti',
          items: Array.isArray(reviewResult.items)
            ? reviewResult.items.slice(0, 5)
            : [],
        },
        sellerComparison: null,
      };
    }
  
    const detailResult = await generateSelectedProductDetail({
      selectedProduct,
      userMessage,
      userProfile,
    });
  
    return {
      assistantText: 'Ürün detayını hazırladım.',
      products: [],
      actions: [],
      comparison: null,
      reviewCard: null,
      detailCard: {
        product: {
          name: selectedProduct?.name || '',
          price: selectedProduct?.price || '',
          platform: selectedProduct?.platform || '',
          image: selectedProduct?.image || '',
          link: selectedProduct?.link || '',
        },
        title: detailResult.title || 'Ürün detayı',
        bullets: Array.isArray(detailResult.bullets)
          ? detailResult.bullets.slice(0, 4)
          : [],
      },
      sellerComparison: null,
    };
  }
  console.log("NEW GENERATECHATREPLY ACTIVE:", userMessage);

  if (isUserPreferenceQuestion(userMessage)) {
    return {
      assistantText: generatePreferenceInsightReply(previousMessages, favoriteProducts),
      products: [],
      actions: [],
      comparison: null,
    };
  }

  if (isGenericRecommendationRequest(userMessage)) {
    const preferenceSeed = buildPreferenceSeed(previousMessages, favoriteProducts);

    if (preferenceSeed && preferenceSeed.trim().length > 0) {
      const seededMessage = `
Kullanıcı genel bir öneri istiyor.
Aşağıdaki uzun dönem alışveriş hafızasını kullanarak daha kişisel öneri ver:

${preferenceSeed}

Kullanıcı mesajı:
${userMessage}
      `.trim();

      const planner = await generatePlanner({
        userMessage: seededMessage,
        previousMessages,
        userProfile,
        favoriteProducts,
      });

      let searchedProducts = [];

      if (planner.needs_product_search) {
        const rawResults = await searchWithFallback(userMessage, planner.search_query);

        let filteredResults = [...rawResults];
        filteredResults = filterProductsByGender(filteredResults, userProfile);
        filteredResults = filterProductsByPriceIntent(filteredResults, userMessage);

        if (filteredResults.length > 0) {
          const featureFiltered = filterProductsByFeatures(filteredResults, userMessage);
          if (featureFiltered.length > 0) {
            filteredResults = featureFiltered;
          }
        }

        filteredResults = removeWeakProducts(
          filteredResults,
          userMessage,
          planner.search_query
        );

        filteredResults = scoreAndRankProducts(
          filteredResults,
          userMessage,
          planner.search_query
        );

        searchedProducts =
          filteredResults.length > 0
            ? filteredResults.slice(0, 10)
            : scoreAndRankProducts(rawResults, userMessage, planner.search_query).slice(0, 10);
      }

      const answer = await generateAnswer({
        userMessage: seededMessage,
        previousMessages,
        planner,
        searchedProducts,
        userProfile,
        favoriteProducts,
      });

      const finalProducts =
  Array.isArray(answer.products) && answer.products.length > 0
    ? enrichProductsWithSource(answer.products, searchedProducts)
    : normalizeProducts(searchedProducts);

      const finalActions =
        finalProducts.length === 0
          ? []
          : (Array.isArray(answer.actions) && answer.actions.length > 0
              ? answer.actions
              : buildFallbackActions(finalProducts, planner, userMessage));

      return {
        assistantText: answer.assistant_text || 'Seni tanıdığım kadarıyla birkaç öneri hazırladım.',
        products: finalProducts,
        actions: finalActions,
        comparison: null,
      };
    }
  }


  const recentProducts = extractRecentProducts(previousMessages);
  const comparisonProducts = extractRecentProductsForComparison(previousMessages, 4);
  const referencedProduct = resolveProductReference(userMessage, recentProducts);
  const referenceAction = buildReferenceBasedReply(userMessage, referencedProduct);
  const isComparisonRequest = isComparisonLikeRequest(userMessage);
  const isSellerCompare = isSellerComparisonRequest(userMessage);
  console.log("GLOBAL SELLER COMPARE:", isSellerCompare);
  console.log("GLOBAL USER MESSAGE:", userMessage);
  console.log("GLOBAL SELECTED PRODUCT:", selectedProduct ? selectedProduct.name : null);


  console.log(
    "SELECTED PRODUCT FLOW ACTIVE FOR:",
    selectedProduct ? selectedProduct.name : null
  );
  console.log("SELECTED PRODUCT SELLER INTENT:", isSellerComparisonRequest(userMessage));
  console.log("SELECTED PRODUCT USER MESSAGE:", userMessage);

  if (isSellerCompare && !selectedProduct) {
    const latestBatch = extractLastProductBatch(previousMessages);
  
    const referencedProduct = resolveProductReference(userMessage, latestBatch);
  
    if (!referencedProduct) {
      return {
        assistantText:
          'Tabii, satıcı karşılaştırması yapabilmem için önce hangi ürünü baz alacağımı bilmem gerekiyor. Üstteki ürünlerden birine dokunup Sor diyebilir ya da ilk ürün / ikinci ürün diye yazabilirsin.',
        products: [],
        actions: [],
        comparison: null,
        detailCard: null,
        reviewCard: null,
        sellerComparison: null,
      };
    }
  }

  if (isSellerCompare) {
    const baseProduct = resolveSellerBaseProduct({
      userMessage,
      selectedProduct,
      previousMessages,
    });
  
    if (!baseProduct) {
      return {
        assistantText: 'Hangi ürünü baz alayım? Üstteki ürünlerden birine dokunabilir ya da ilk ürün / ikinci ürün diye yazabilirsin.',
        products: [],
        actions: [],
        comparison: null,
        detailCard: null,
        reviewCard: null,
        sellerComparison: null,
      };
    }
  
    const sellerComparison = await buildSellerComparisonFromSearch({
      baseProduct,
    });
  
    if (!sellerComparison) {
      return {
        assistantText: 'Bu ürün için farklı satıcıları bulamadım.',
        products: [],
        actions: [],
        comparison: null,
        detailCard: null,
        reviewCard: null,
        sellerComparison: null,
      };
    }
  
    return {
      assistantText: `"${baseProduct.name}" için farklı satıcıları buldum.`,
      products: [],
      actions: [],
      comparison: null,
      detailCard: null,
      reviewCard: null,
      sellerComparison,
    };
  }

  const actionCommand = detectActionCommand(userMessage);
  const latestBatchProducts = extractLastProductBatch(previousMessages);
  const stableBatchProducts = filterProductsToSameCategory(
    latestBatchProducts.length > 0 ? latestBatchProducts : comparisonProducts,
    userMessage
  );

  if (actionCommand === 'compare') {
    const compareBaseProducts =
      stableBatchProducts.length >= 2 ? stableBatchProducts : comparisonProducts;
  
    if (!compareBaseProducts || compareBaseProducts.length < 2) {
      return {
        assistantText: 'Karşılaştırma yapabilmem için önce aynı kategoride en az 2 ürün göstermem gerekiyor.',
        products: [],
        actions: [],
        comparison: null,
      };
    }
  
    const compareQuery = compareBaseProducts
      .map((p) => p.name || '')
      .filter(Boolean)
      .slice(0, 2)
      .join(' ');
  
    let compareSearchResults = [];
  
    if (compareQuery.trim().isNotEmpty) {
      const rawCompareResults = await searchWithFallback(compareQuery, compareQuery);
  
      compareSearchResults = scoreAndRankProducts(
        rawCompareResults,
        compareQuery,
        compareQuery
      ).slice(0, 10);
    }
  
    const enrichedCompareProducts = enrichProductsWithSource(
      compareBaseProducts,
      compareSearchResults
    );
  
    const deterministicComparison = buildDeterministicComparison(enrichedCompareProducts);
  
    if (deterministicComparison) {
      return {
        assistantText: `${deterministicComparison.winner} öne çıkıyor. Senin için seçenekleri net şekilde karşılaştırdım.`,
        products: [],
        actions: [],
        comparison: deterministicComparison,
      };
    }
  
    return {
      assistantText: 'Karşılaştırma yapabilmem için önce aynı kategoride en az 2 ürün göstermem gerekiyor.',
      products: [],
      actions: [],
      comparison: null,
    };
  }

  if (actionCommand === 'find_similar') {
    const baseProduct =
      referencedProduct ||
      stableBatchProducts[0] ||
      latestBatchProducts[0] ||
      recentProducts[0] ||
      null;

    if (baseProduct) {
      const similarResults = await searchWithFallback(
        baseProduct.name || userMessage,
        baseProduct.name || userMessage
      );

      let cleanedSimilar = removeWeakProducts(
        similarResults,
        baseProduct.name || userMessage,
        baseProduct.name || userMessage
      );

      cleanedSimilar = scoreAndRankProducts(
        cleanedSimilar,
        baseProduct.name || userMessage,
        baseProduct.name || userMessage
      ).slice(0, 8);

      const normalizedSimilar = normalizeProducts(cleanedSimilar);

      return {
        assistantText: `"${baseProduct.name}" için benzer seçenekleri buldum.`,
        products: normalizedSimilar,
        actions: buildFallbackActions(normalizedSimilar, {}, baseProduct.name || userMessage),
        comparison: null,
      };
    }

    return {
      assistantText: 'Benzer ürünler bulabilmem için önce bir ürün seçmem gerekiyor.',
      products: [],
      actions: [],
      comparison: null,
    };
  }

  if (actionCommand === 'find_cheaper') {
    const baseProduct =
      referencedProduct ||
      stableBatchProducts[0] ||
      latestBatchProducts[0] ||
      recentProducts[0] ||
      null;

    if (baseProduct) {
      const basePrice = parsePriceValue(baseProduct.price);

      const cheaperResults = await searchWithFallback(
        baseProduct.name || userMessage,
        baseProduct.name || userMessage
      );

      let cleanedCheaper = removeWeakProducts(
        cheaperResults,
        baseProduct.name || userMessage,
        baseProduct.name || userMessage
      ).filter((p) => parsePriceValue(p.price) < basePrice);

      cleanedCheaper = scoreAndRankProducts(
        cleanedCheaper,
        baseProduct.name || userMessage,
        baseProduct.name || userMessage
      ).slice(0, 8);

      const normalizedCheaper = normalizeProducts(cleanedCheaper);

      return {
        assistantText: `"${baseProduct.name}" için daha uygun fiyatlı alternatifleri buldum.`,
        products: normalizedCheaper,
        actions: buildFallbackActions(normalizedCheaper, {}, baseProduct.name || userMessage),
        comparison: null,
      };
    }

    return {
      assistantText: 'Daha ucuz alternatif gösterebilmem için önce bir ürün seçmem gerekiyor.',
      products: [],
      actions: [],
      comparison: null,
    };
  }

  const planner = await generatePlanner({
    userMessage,
    previousMessages,
    userProfile,
    favoriteProducts,
  });
  
  const normalizedMessage = normalizeText(userMessage.trim());
  const wordCount = normalizedMessage.split(/\s+/).filter(Boolean).length;
  const genericCategoryQuestion = detectGenericShoppingCategory(userMessage);
  const profileHelpsThisCategory = hasUsefulProfileForCategory(userMessage, userProfile);
  
  // TEST için log
  console.log("GENERIC QUESTION:", genericCategoryQuestion);
  console.log("WORD COUNT:", wordCount);
  console.log("PROFILE HELPS:", profileHelpsThisCategory);
  
  // 🔥 EN KRİTİK FIX
  if (genericCategoryQuestion && wordCount <= 2) {
    if (!profileHelpsThisCategory) {
      console.log("GENERIC CATEGORY HIT:", genericCategoryQuestion);
  
      return {
        assistantText: genericCategoryQuestion,
        products: [],
        actions: [],
        comparison: null,
      };
    }
  }
  
  const isSmallTalk =
    planner.small_talk === true || isSmallTalkMessage(userMessage);
  
  if (isSmallTalk) {
    const smallTalkReply = await generateSmallTalkReply(userMessage, previousMessages);
  
    return {
      assistantText: smallTalkReply,
      products: [],
      actions: [],
      comparison: null,
    };
  }

  if (planner.needs_clarification && planner.clarification_question && !profileHelpsThisCategory) {
    return {
      assistantText: planner.clarification_question,
      products: [],
      actions: [],
      comparison: null,
    };
  }

  if (planner.shopping_relevance === 'none' || planner.shopping_relevance === 'low') {
    if (genericCategoryQuestion) {
      return {
        assistantText: genericCategoryQuestion,
        products: [],
        actions: [],
        comparison: null,
      };
    }

  }

  let searchedProducts = [];

  if (planner.needs_product_search) {
    const rawResults = await searchWithFallback(userMessage, planner.search_query);
    const { hasPriceFilter, min, max } = detectPriceIntent(userMessage);

    let filteredResults = [...rawResults];

    filteredResults = filterProductsByGender(filteredResults, userProfile);

    filteredResults = filterProductsByPriceIntent(filteredResults, userMessage);

    if (filteredResults.length > 0) {
      const featureFiltered = filterProductsByFeatures(filteredResults, userMessage);
      if (featureFiltered.length > 0) {
        filteredResults = featureFiltered;
      }
    }

    filteredResults = removeWeakProducts(
      filteredResults,
      userMessage,
      planner.search_query
    );

    filteredResults = scoreAndRankProducts(
      filteredResults,
      userMessage,
      planner.search_query
    );

    if (hasPriceFilter && filteredResults.length < 3) {
      const broaderResults = await searchGoogleShopping(
        sanitizeSearchQuery(userMessage)
      );

      let broaderFiltered = filterProductsByGender(
        broaderResults,
        userProfile
      );
      
      broaderFiltered = filterProductsByPriceIntent(
        broaderFiltered,
        userMessage
      );

      if (broaderFiltered.length > 0) {
        const broaderFeatureFiltered = filterProductsByFeatures(
          broaderFiltered,
          userMessage
        );

        if (broaderFeatureFiltered.length > 0) {
          broaderFiltered = broaderFeatureFiltered;
        }
      }

      broaderFiltered = removeWeakProducts(
        broaderFiltered,
        userMessage,
        planner.search_query
      );

      broaderFiltered = scoreAndRankProducts(
        broaderFiltered,
        userMessage,
        planner.search_query
      );

      if (broaderFiltered.length > filteredResults.length) {
        filteredResults = broaderFiltered;
      }

      if (filteredResults.length < 4) {
        const expandedLevel1 = expandPriceRange(min, max, 1);

        let broaderFilteredLevel1 = filterProductsByGender(
          broaderResults,
          userProfile
        );
        
        broaderFilteredLevel1 = filterProductsByExplicitRange(
          broaderFilteredLevel1,
          expandedLevel1.min,
          expandedLevel1.max
        );

        if (broaderFilteredLevel1.length > 0) {
          const featureFilteredLevel1 = filterProductsByFeatures(
            broaderFilteredLevel1,
            userMessage
          );

          if (featureFilteredLevel1.length > 0) {
            broaderFilteredLevel1 = featureFilteredLevel1;
          }
        }

        broaderFilteredLevel1 = removeWeakProducts(
          broaderFilteredLevel1,
          userMessage,
          planner.search_query
        );

        broaderFilteredLevel1 = scoreAndRankProducts(
          broaderFilteredLevel1,
          userMessage,
          planner.search_query
        );

        if (broaderFilteredLevel1.length > filteredResults.length) {
          filteredResults = broaderFilteredLevel1;
        }
      }
    }

    searchedProducts =
      filteredResults.length > 0
        ? filteredResults.slice(0, 10)
        : scoreAndRankProducts(rawResults, userMessage, planner.search_query).slice(0, 10);
  }

  if (referenceAction && referencedProduct) {
    if (referenceAction.mode === 'similar' || referenceAction.mode === 'cheaper') {
      planner.needs_product_search = true;
      planner.search_query = referencedProduct.name || planner.search_query;
    }

    if (referenceAction.mode === 'compare_reference' || referenceAction.mode === 'info') {
      planner.needs_product_search = false;
    }
  }

  const answer = await generateAnswer({
    userMessage,
    previousMessages,
    planner,
    searchedProducts,
    userProfile,
    favoriteProducts,
  });
  
  const finalProducts =
    Array.isArray(answer.products) && answer.products.length > 0
      ? enrichProductsWithSource(answer.products, searchedProducts)
      : normalizeProducts(searchedProducts);
  
  if (isComparisonRequest && finalProducts.length >= 2) {
    return {
      assistantText: answer.assistant_text || 'Senin için seçenekleri karşılaştırdım.',
      products: [],
      actions: normalizeActions(answer.actions),
      comparison: buildComparisonData(answer, finalProducts, userMessage),
    };
  }

const displayProducts = isComparisonRequest ? [] : finalProducts;

const finalActions =
  displayProducts.length === 0
    ? (Array.isArray(answer.actions) && answer.actions.length > 0
        ? answer.actions
        : [])
    : (Array.isArray(answer.actions) && answer.actions.length > 0
        ? answer.actions
        : buildFallbackActions(displayProducts, planner, userMessage));

  const finalAssistantText =
    referenceAction?.assistantText && referencedProduct
      ? `${referenceAction.assistantText}\n\n${answer.assistant_text || ''}`.trim()
      : (answer.assistant_text || '');

  let polishedAssistantText = finalAssistantText;

  if ((!finalProducts || finalProducts.length === 0) && planner.needs_product_search) {
    const { hasPriceFilter, min, max } = detectPriceIntent(userMessage);

    if (hasPriceFilter) {
      polishedAssistantText =
        `Tam istediğin fiyat aralığında güçlü sonuç bulamadım.` +
        `${min != null || max != null ? ' İstersen bütçeyi biraz genişletip tekrar bakabilirim.' : ''}`;
    } else {
      polishedAssistantText =
        'Bu isteğe uygun güçlü ürün bulamadım. İstersen marka, özellik veya bütçe ekleyerek biraz daha netleştirebiliriz.';
    }
  }

  const compareSourceProducts = finalProducts;

  const comparison = buildComparisonData(
    answer,
    finalProducts,
    userMessage
  );
  if (isSellerCompare && finalProducts.length >= 2) {
    const sellerComparison = buildSellerComparisonData(finalProducts);
  
    if (sellerComparison) {
      return {
        assistantText: 'Aynı ürünü farklı satıcılarda senin için çıkardım.',
        products: [],
        actions: [],
        comparison: null,
        detailCard: null,
        reviewCard: null,
        sellerComparison,
      };
    }
  }

  return {
    assistantText: polishedAssistantText,
    products: displayProducts,
    actions: finalActions,
    comparison,
  };
}

async function buildSellerComparisonFromSearch({
  baseProduct,
}) {
  if (!baseProduct || !baseProduct.name) return null;

  console.log("SELLER SEARCH FOR:", baseProduct.name);

  const rawResults = await searchGoogleShopping(baseProduct.name);

  const normalized = normalizeProducts(rawResults);

  const targetKey = normalizeSellerKey(baseProduct.name);

  const sameProducts = normalized.filter((item) => {
    const itemKey = normalizeSellerKey(item.name);

    if (!itemKey) return false;

    if (itemKey === targetKey) return true;

    if (itemKey.includes(targetKey)) return true;

    if (targetKey.includes(itemKey)) return true;

    const words = targetKey.split(' ').filter(Boolean);

    const matchCount = words.filter((w) => itemKey.includes(w)).length;

    return matchCount >= Math.max(2, Math.ceil(words.length * 0.6));
  });

  const finalList = sameProducts.length > 0 ? sameProducts : normalized;

  const grouped = groupProductsBySeller(finalList);

  if (!grouped.length) return null;

  return {
    title: 'Satıcı karşılaştırması',
    groups: grouped,
  };
}

function normalizeSellerKey(name = '') {
  return normalizeText(name)
    .replace(/erkek|kadin|bayan|unisex/g, '')
    .replace(/ayakkabi|sneaker|lifestyle|originals/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function resolveSellerBaseProduct({
  userMessage,
  selectedProduct,
  previousMessages,
}) {
  if (selectedProduct && selectedProduct.name) {
    return selectedProduct;
  }

  const latestBatch = extractLastProductBatch(previousMessages);

  const referenced = resolveProductReference(userMessage, latestBatch);

  if (referenced) return referenced;

  if (latestBatch.length === 1) return latestBatch[0];

  return null;
}

async function generateChatTitle(firstMessage) {
  const prompt = `
Kullanıcının ilk mesajına göre kısa ve doğal bir sohbet başlığı üret.
Türkçe üret.
En fazla 5 kelime olsun.
Sadece düz metin döndür.

Mesaj:
${firstMessage}
`;

  const response = await client.chat.completions.create({
    model: 'gpt-4.1-mini',
    messages: [{ role: 'user', content: prompt }],
    temperature: 0.5,
  });

  return response.choices[0].message.content.trim().replace(/^"|"$/g, '');
}

function isSmallTalkMessage(userMessage = '') {
  const text = normalizeText(String(userMessage).trim());

  const patterns = [
    'merhaba',
    'selam',
    'selamlar',
    'hey',
    'hi',
    'hello',
    'nasilsin',
    'iyi misin',
    'napiyorsun',
    'ne yapiyorsun',
    'napiyosun',
    'napiyosun',
    'napiyon',
    'napiyon',
    'naber',
    'ne haber',
    'tesekkurler',
    'tesekkur ederim',
    'sag ol',
    'gorusuruz',
    'hoscakal',
    'bye'
  ];

  return patterns.some((p) => text.includes(p));
}

function isReviewRequest(userMessage = '') {
  const text = normalizeText(userMessage);

  return (
    text.includes('yorum') ||
    text.includes('yorumlari nasil') ||
    text.includes('kullanici yorum') ||
    text.includes('inceleme') ||
    text.includes('degerlendirme') ||
    text.includes('memnun') ||
    text.includes('begenilmis')
  );
}

function normalizeProductNameForSellerCompare(name = '') {
  return normalizeText(name)
    .replace(/\b(\d+)\s?gb\b/g, '$1gb')
    .replace(/\b(\d+)\s?tb\b/g, '$1tb')
    .replace(/\b(rgb|gaming|oyuncu|kablosuz|bluetooth|wireless)\b/g, ' $1 ')
    .replace(/[^\w\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractSellerCompareKey(product = {}) {
  const raw = `${product.name || ''} ${product.short_reason || ''}`.trim();
  const normalized = normalizeProductNameForSellerCompare(raw);

  const words = normalized.split(' ').filter(Boolean);

  if (words.length <= 6) return normalized;

  return words.slice(0, 6).join(' ');
}

function groupProductsBySeller(products = []) {
  const groups = {};

  for (const product of normalizeProducts(products)) {
    const key = extractSellerCompareKey(product);
    if (!key) continue;

    if (!groups[key]) {
      groups[key] = [];
    }

    groups[key].push(product);
  }

  return Object.values(groups)
    .map((items) => {
      const sortedByPrice = [...items].sort(
        (a, b) => parsePriceValue(a.price) - parsePriceValue(b.price)
      );

      const cheapest = sortedByPrice[0] || null;
      const highest = sortedByPrice[sortedByPrice.length - 1] || null;

      const minPrice = cheapest ? parsePriceValue(cheapest.price) : null;
      const maxPrice = highest ? parsePriceValue(highest.price) : null;

      return {
        baseName: cheapest?.name || items[0]?.name || '',
        image: cheapest?.image || items[0]?.image || '',
        sellers: sortedByPrice.map((item) => ({
          name: item.name || '',
          price: item.price || '',
          platform: item.platform || '',
          image: item.image || '',
          link: item.link || '',
          rating: item.rating || null,
          reviews: item.reviews || null,
        })),
        cheapestSeller: cheapest
          ? {
              price: cheapest.price || '',
              platform: cheapest.platform || '',
              link: cheapest.link || '',
            }
          : null,
        priceSpread:
          minPrice != null &&
          maxPrice != null &&
          minPrice !== Number.MAX_SAFE_INTEGER &&
          maxPrice !== Number.MAX_SAFE_INTEGER
            ? maxPrice - minPrice
            : null,
      };
    })
    .filter((group) => group.sellers.length >= 2)
    .sort((a, b) => b.sellers.length - a.sellers.length);
}



function isSellerComparisonRequest(userMessage = '') {
  const text = normalizeText(userMessage)
    .replace(/\s+/g, ' ')
    .trim();

  return (
    text.includes('satici') ||
    text.includes('saticilar') ||
    text.includes('magaza') ||
    text.includes('magazalar') ||
    text.includes('farkli satici') ||
    text.includes('farkli saticilar') ||
    text.includes('farkli magazada') ||
    text.includes('farkli magazalarda') ||
    text.includes('ayni urun') ||
    text.includes('ayni urunu') ||
    text.includes('en ucuz satici') ||
    text.includes('saticilar arasinda') ||
    text.includes('hangi magazada') ||
    text.includes('nerede daha ucuz') ||
    text.includes('fiyat karsilastir') ||
    text.includes('fiyatlari karsilastir') ||
    text.includes('bunu farkli') ||
    text.includes('bunu saticilarda') ||
    text.includes('bunu magazalarda')
  );
}

function buildSellerComparisonData(products = []) {
  const grouped = groupProductsBySeller(products).slice(0, 10);

  if (!grouped.length) return null;

  return {
    title: 'Satıcı karşılaştırması',
    groups: grouped.map((group) => ({
      baseName: group.baseName,
      image: group.image,
      cheapestSeller: group.cheapestSeller,
      priceSpread: group.priceSpread,
      sellers: group.sellers
    })),
  };
}

async function generateSmallTalkReply(userMessage, previousMessages = []) {
  console.log('SMALL TALK DYNAMIC HIT:', userMessage);

  const recentAssistantMessages = previousMessages
    .filter((m) => m && m.role === 'assistant' && m.text)
    .slice(-4)
    .map((m) => `- ${m.text}`)
    .join('\n');

  const styleOptions = [
    'sıcak ve kısa',
    'samimi ve hafif esprili',
    'rahat ve doğal',
    'pozitif ve canlı'
  ];

  const randomStyle =
    styleOptions[Math.floor(Math.random() * styleOptions.length)];

  const prompt = `
Sen Shopi'sin.
Kullanıcıyla konuşan samimi bir alışveriş asistanısın.
Şu an kullanıcı küçük sohbet yapıyor.
Cevabın kısa, doğal ve insan gibi olsun.
Robot gibi, kalıp gibi veya tekrar eden cevaplar verme.
Daha önce verdiğin cevaplara fazla benzeme.
Cevap en fazla 2 kısa cümle olsun.
Tarzın: ${randomStyle}

Önceki bazı assistant cevapları:
${recentAssistantMessages || '- Yok'}

Kullanıcı mesajı:
"${userMessage}"

Kurallar:
- Gereksiz resmi konuşma yapma.
- Aynı kalıpları tekrar etme.
- Gerekirse sohbeti nazikçe alışveriş yardımına bağlayabilirsin.
- Sadece düz cevap metni yaz.
`;

  const response = await client.chat.completions.create({
    model: 'gpt-4.1-mini',
    messages: [{ role: 'user', content: prompt }],
    temperature: 1.2,
    presence_penalty: 0.8,
    frequency_penalty: 0.7,
  });

  return response.choices[0].message.content.trim();
}

async function generateSelectedProductReviews({ selectedProduct, userMessage, userProfile = null }) {
  const profileText = formatUserProfile(userProfile);

  const prompt = `
Sen Shopi'sin.
Kullanıcı seçtiği ürün için yorumları soruyor.

Kurallar:
- Uzun paragraf yazma.
- Yalnızca geçerli JSON döndür.
- En fazla 5 kısa yorum maddesi üret.
- Maddeler kısa ve okunabilir olsun.
- Şu başlık mantığını kullan:
  - Genel yorum
  - Beğenilenler
  - Dikkat edilmesi gerekenler
- Dengeli yaz, abartma.
- Ürün dışına çıkma.
- Markdown kullanma.

Ürün:
${JSON.stringify(selectedProduct, null, 2)}

Kullanıcı profili:
${profileText}

Kullanıcı mesajı:
${userMessage}

JSON formatı:
{
  "title": "Yorum özeti",
  "items": [
    "Genel yorum: ...",
    "Beğenilenler: ...",
    "Dikkat edilmesi gerekenler: ..."
  ]
}
`;

  const response = await client.chat.completions.create({
    model: 'gpt-4.1-mini',
    messages: [{ role: 'user', content: prompt }],
    temperature: 0.4,
  });

  const text = response.choices[0].message.content;
  const parsed = safeParseJson(text);

  const items = Array.isArray(parsed?.items)
    ? parsed.items.map((e) => String(e).trim()).filter(Boolean).slice(0, 5)
    : [];

  return {
    title:
      typeof parsed?.title === 'string' && parsed.title.trim().length > 0
        ? parsed.title.trim()
        : 'Yorum özeti',
    items:
      items.length > 0
        ? items
        : ['Genel yorum: Bu ürün için kısa bir değerlendirme hazırladım.'],
  };
}

async function generateSelectedProductDetail({ selectedProduct, userMessage, userProfile = null }) {
  const profileText = formatUserProfile(userProfile);
  const prompt = `
Sen Shopi'sin.
Kullanıcı seçtiği TEK bir ürün hakkında soru soruyor.
Sadece bu ürüne odaklan.
Uzun paragraf yazma.
En fazla 4 kısa madde yaz.
Her madde kısa olsun.
Başka ürün önerme.
Ürün listesi oluşturma.
Sadece kullanıcının sorduğu şeye cevap ver.

Eğer soru ürünle ilgiliyse kısa maddeler üret.
Eğer soru ürünle alakasızsa bunu kibarca belirt.

Ürün:
${JSON.stringify(selectedProduct, null, 2)}

Kullanıcı profili:
${profileText}

Kullanıcı sorusu:
${userMessage}

Sadece geçerli JSON döndür.

JSON formatı:
{
  "title": "kısa başlık",
  "bullets": [
    "kısa madde 1",
    "kısa madde 2",
    "kısa madde 3"
  ]
}
`;

  const response = await client.chat.completions.create({
    model: 'gpt-4.1-mini',
    messages: [{ role: 'user', content: prompt }],
    temperature: 0.3,
  });

  const text = response.choices[0].message.content;
  const parsed = safeParseJson(text);

  const safeBullets = Array.isArray(parsed?.bullets)
    ? parsed.bullets
        .map((e) => String(e).trim())
        .filter((e) => e.length > 0)
        .slice(0, 4)
    : [];

  return {
    title:
      typeof parsed?.title === 'string' && parsed.title.trim().length > 0
        ? parsed.title.trim()
        : 'Ürün detayı',
    bullets:
      safeBullets.length > 0
        ? safeBullets
        : ['Bu ürün hakkında şu an kısa bilgi verebildim.'],
  };
}

function formatUserProfile(userProfile = null) {
  if (!userProfile) return 'Kullanıcı profili yok.';

  const parts = [];

  if (userProfile.gender) {
    parts.push(`Cinsiyet: ${userProfile.gender}`);
  }

  if (userProfile.shoeSize) {
    parts.push(`Ayakkabı numarası: ${userProfile.shoeSize}`);
  }

  if (userProfile.clothingSize) {
    parts.push(`Beden: ${userProfile.clothingSize}`);
  }

  if (userProfile.height) {
    parts.push(`Boy: ${userProfile.height}`);
  }

  if (userProfile.weight) {
    parts.push(`Kilo: ${userProfile.weight}`);
  }

  if (userProfile.style) {
    parts.push(`Tarz: ${userProfile.style}`);
  }

  return parts.length > 0 ? parts.join('\n') : 'Kullanıcı profili boş.';
}

function detectInterestCategory(text = '') {
  const t = normalizeText(text);

  if (
    t.includes('ayakkabi') ||
    t.includes('sneaker') ||
    t.includes('bot') ||
    t.includes('terlik') ||
    t.includes('sandalet')
  ) {
    return 'Ayakkabı & sneaker';
  }

  if (
    t.includes('ceket') ||
    t.includes('mont') ||
    t.includes('gomlek') ||
    t.includes('pantolon') ||
    t.includes('elbise') ||
    t.includes('tisort') ||
    t.includes('tshirt') ||
    t.includes('kombin') ||
    t.includes('giyim')
  ) {
    return 'Giyim & stil';
  }

  if (
    t.includes('kulaklik') ||
    t.includes('mouse') ||
    t.includes('klavye') ||
    t.includes('telefon') ||
    t.includes('tablet') ||
    t.includes('gaming') ||
    t.includes('laptop')
  ) {
    return 'Teknoloji & gaming';
  }

  if (
    t.includes('parfum') ||
    t.includes('kozmetik') ||
    t.includes('serum') ||
    t.includes('krem') ||
    t.includes('makyaj') ||
    t.includes('ruj') ||
    t.includes('fondoten')
  ) {
    return 'Kozmetik & bakım';
  }

  if (
    t.includes('canta') ||
    t.includes('aksesuar') ||
    t.includes('saat') ||
    t.includes('gozluk')
  ) {
    return 'Aksesuar';
  }

  if (
    t.includes('catal') ||
    t.includes('bicak') ||
    t.includes('kasik') ||
    t.includes('bardak') ||
    t.includes('tabak') ||
    t.includes('mutfak')
  ) {
    return 'Ev & mutfak';
  }

  return null;
}

function extractBrandSignals(text = '') {
  const t = normalizeText(text);

  const knownBrands = [
    'nike', 'adidas', 'puma', 'new balance', 'skechers',
    'apple', 'samsung', 'xiaomi', 'jbl', 'logitech',
    'steelseries', 'razer', 'anker', 'philips',
    'nivea', 'loreal', 'maybelline', 'nars'
  ];

  return knownBrands.filter((brand) => t.includes(normalizeText(brand)));
}


function isUserPreferenceQuestion(userMessage = '') {
  const text = normalizeText(userMessage);

  return (
    text.includes('ilgi alanlarim ne') ||
    text.includes('ilgi alanlarim neler') ||
    text.includes('neleri seviyorum') ||
    text.includes('en cok neye bakiyorum') ||
    text.includes('hangi kategorilere daha cok bakiyorum') ||
    text.includes('hangi kategorileri seviyorum') ||
    text.includes('beni taniyor musun') ||
    text.includes('benim hakkimda ne biliyorsun') ||
    text.includes('alisveris tercihlerim ne') ||
    text.includes('alisveris tarzim ne') ||
    text.includes('tarzimi biliyor musun')
  );
}

function isGenericRecommendationRequest(userMessage = '') {
  const text = normalizeText(userMessage);

  return (
    text === 'ne onerirsin' ||
    text === 'ne önerirsin' ||
    text === 'bana bir sey oner' ||
    text === 'bana bir şey öner' ||
    text === 'bir sey oner' ||
    text === 'bir şey öner' ||
    text === 'bana uygun bir sey oner' ||
    text === 'bana uygun bir şey öner' ||
    text === 'sence ne almaliyim' ||
    text === 'sence ne almalıyım' ||
    text === 'bana bir urun oner' ||
    text === 'bana bir ürün öner'
  );
}

function generatePreferenceInsightReply(previousMessages = [], favoriteProducts = []) {
  const profile = buildUserPreferenceProfile(previousMessages, favoriteProducts);

  if (!profile.hasStrongSignal) {
    return `Seni tanımaya başladım ama henüz güçlü bir alışveriş deseni oluşmadı.
- Birkaç farklı ürün daha aradığında ilgilerini daha net çıkarabilirim.
- Şu an için bana en çok baktığın kategori veya bütçe tarzını biraz daha göstermen lazım.`;
  }

  const bullets = [];

  if (profile.topCategories.length > 0) {
    bullets.push(`En çok ilgilendiğin alanlar: ${profile.topCategories.join(', ')}`);
  }

  if (profile.topBrands.length > 0) {
    bullets.push(`Tekrarlayan marka ilgilerin: ${profile.topBrands.join(', ')}`);
  }

  if (profile.shoppingStyle && profile.shoppingStyle !== 'Henüz net değil') {
    bullets.push(`Alışveriş yaklaşımın: ${profile.shoppingStyle}`);
  }

  bullets.push('Bunu geçmiş aramalarına ve baktığın ürünlere göre çıkarıyorum.');

  return `Seni şöyle tanıyorum:\n- ${bullets.join('\n- ')}`;
}

function buildPreferenceSeed(previousMessages = [], favoriteProducts = []) {
  const profile = buildUserPreferenceProfile(previousMessages, favoriteProducts);

  if (!profile.hasStrongSignal) {
    return '';
  }

  const parts = [];

  if (profile.topCategories.length > 0) {
    parts.push(`Öne çıkan kategoriler: ${profile.topCategories.join(', ')}`);
  }

  if (profile.topBrands.length > 0) {
    parts.push(`Marka eğilimleri: ${profile.topBrands.join(', ')}`);
  }

  if (profile.shoppingStyle && profile.shoppingStyle !== 'Henüz net değil') {
    parts.push(`Alışveriş yaklaşımı: ${profile.shoppingStyle}`);
  }

  return parts.join('\n');
}

function detectInterestCategory(text = '') {
  const t = normalizeText(text);

  if (
    t.includes('ayakkabi') ||
    t.includes('sneaker') ||
    t.includes('bot') ||
    t.includes('terlik') ||
    t.includes('sandalet')
  ) {
    return 'Ayakkabı & sneaker';
  }

  if (
    t.includes('ceket') ||
    t.includes('mont') ||
    t.includes('gomlek') ||
    t.includes('pantolon') ||
    t.includes('elbise') ||
    t.includes('tisort') ||
    t.includes('tshirt') ||
    t.includes('kombin') ||
    t.includes('giyim')
  ) {
    return 'Giyim & stil';
  }

  if (
    t.includes('kulaklik') ||
    t.includes('mouse') ||
    t.includes('klavye') ||
    t.includes('telefon') ||
    t.includes('tablet') ||
    t.includes('gaming') ||
    t.includes('laptop')
  ) {
    return 'Teknoloji & gaming';
  }

  if (
    t.includes('parfum') ||
    t.includes('kozmetik') ||
    t.includes('serum') ||
    t.includes('krem') ||
    t.includes('makyaj') ||
    t.includes('ruj') ||
    t.includes('fondoten')
  ) {
    return 'Kozmetik & bakım';
  }

  if (
    t.includes('canta') ||
    t.includes('aksesuar') ||
    t.includes('saat') ||
    t.includes('gozluk')
  ) {
    return 'Aksesuar';
  }

  if (
    t.includes('catal') ||
    t.includes('bicak') ||
    t.includes('kasik') ||
    t.includes('bardak') ||
    t.includes('tabak') ||
    t.includes('mutfak')
  ) {
    return 'Ev & mutfak';
  }

  return null;
}

function extractBrandSignals(text = '') {
  const t = normalizeText(text);

  const knownBrands = [
    'nike', 'adidas', 'puma', 'new balance', 'skechers',
    'apple', 'samsung', 'xiaomi', 'jbl', 'logitech',
    'steelseries', 'razer', 'anker', 'philips',
    'nivea', 'loreal', 'maybelline', 'nars'
  ];

  return knownBrands.filter((brand) => t.includes(normalizeText(brand)));
}

function buildFavoritePreferenceProfile(favoriteProducts = []) {
  const categoryScores = {};
  const brandScores = {};

  for (const product of favoriteProducts) {
    if (!product) continue;

    const text = `${product.name || ''} ${product.short_reason || ''} ${product.platform || ''}`;

    const category = detectInterestCategory(text);
    if (category) {
      categoryScores[category] = (categoryScores[category] || 0) + 3;
    }

    const brands = extractBrandSignals(text);
    for (const brand of brands) {
      brandScores[brand] = (brandScores[brand] || 0) + 3;
    }
  }

  const topCategories = Object.entries(categoryScores)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([name]) => name);

  const topBrands = Object.entries(brandScores)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([name]) => name);

  return {
    topCategories,
    topBrands,
  };
}

function buildUserPreferenceProfile(previousMessages = [], favoriteProducts = []) {
  const categoryScores = {};
  const brandScores = {};
  let priceSensitiveScore = 0;
  let premiumScore = 0;

  for (const msg of previousMessages) {
    const text = String(msg?.text || '');
    const normalized = normalizeText(text);

    const category = detectInterestCategory(text);
    if (category) {
      categoryScores[category] = (categoryScores[category] || 0) + 2;
    }

    const brands = extractBrandSignals(text);
    for (const brand of brands) {
      brandScores[brand] = (brandScores[brand] || 0) + 2;
    }

    if (
      normalized.includes('uygun fiyat') ||
      normalized.includes('fiyat performans') ||
      normalized.includes('ucuz') ||
      normalized.includes('daha ucuz') ||
      normalized.includes('butce') ||
      normalized.includes('bütçe')
    ) {
      priceSensitiveScore += 2;
    }

    if (
      normalized.includes('premium') ||
      normalized.includes('en iyi') ||
      normalized.includes('kaliteli') ||
      normalized.includes('ust seviye') ||
      normalized.includes('üst seviye')
    ) {
      premiumScore += 1;
    }

    const favoriteProfile = buildFavoritePreferenceProfile(favoriteProducts);

    for (const category of favoriteProfile.topCategories) {
      categoryScores[category] = (categoryScores[category] || 0) + 4;
    }
  
    for (const brand of favoriteProfile.topBrands) {
      brandScores[brand] = (brandScores[brand] || 0) + 4;
    }

    if (msg && Array.isArray(msg.products) && msg.products.length > 0) {
      for (const product of msg.products) {
        const pText = `${product.name || ''} ${product.short_reason || ''}`;
        const pCategory = detectInterestCategory(pText);

        if (pCategory) {
          categoryScores[pCategory] = (categoryScores[pCategory] || 0) + 1;
        }

        const pBrands = extractBrandSignals(pText);
        for (const brand of pBrands) {
          brandScores[brand] = (brandScores[brand] || 0) + 1;
        }
      }
    }
  }

  const favoriteProfile = buildFavoritePreferenceProfile(favoriteProducts);

  for (const category of favoriteProfile.topCategories) {
    categoryScores[category] = (categoryScores[category] || 0) + 4;
  }

  for (const brand of favoriteProfile.topBrands) {
    brandScores[brand] = (brandScores[brand] || 0) + 4;
  }

  const topCategories = Object.entries(categoryScores)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([name]) => name);

  const topBrands = Object.entries(brandScores)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([name]) => name);

  let shoppingStyle = 'Henüz net değil';

  if (priceSensitiveScore >= 3 && premiumScore < 2) {
    shoppingStyle = 'Fiyat/performans odaklı';
  } else if (premiumScore >= 3 && priceSensitiveScore < 2) {
    shoppingStyle = 'Daha kaliteli / premium ürünlere açık';
  } else if (priceSensitiveScore >= 2 && premiumScore >= 2) {
    shoppingStyle = 'Denge arayan, hem fiyatı hem kaliteyi önemseyen';
  }

  return {
    topCategories,
    topBrands,
    shoppingStyle,
    hasStrongSignal: topCategories.length > 0 || topBrands.length > 0,
  };
}

function buildUserPreferenceSummary(previousMessages = [], favoriteProducts = []) {
  const profile = buildUserPreferenceProfile(previousMessages, favoriteProducts);

  if (!profile.hasStrongSignal) {
    return 'Kullanıcının alışveriş tercihleri henüz net değil.';
  }

  const parts = [];

  if (profile.topCategories.length > 0) {
    parts.push(`Öne çıkan ilgi alanları: ${profile.topCategories.join(', ')}`);
  }

  if (profile.topBrands.length > 0) {
    parts.push(`Sık tekrar eden marka ilgileri: ${profile.topBrands.join(', ')}`);
  }

  if (profile.shoppingStyle) {
    parts.push(`Alışveriş yaklaşımı: ${profile.shoppingStyle}`);
  }

  return parts.join('\n');
}

function buildUserPreferenceSummary(previousMessages = []) {
  const text = previousMessages
    .map((m) => m.text || '')
    .join(' ')
    .toLowerCase();

  const preferences = [];

  // 🔥 Kategori ilgisi
  if (text.includes('ayakkabi') || text.includes('sneaker')) {
    preferences.push('Ayakkabı ve sneaker ilgisi yüksek');
  }

  if (text.includes('ceket') || text.includes('kombin') || text.includes('giyim')) {
    preferences.push('Giyim ve stil ürünlerine ilgili');
  }

  if (text.includes('kulaklik') || text.includes('gaming') || text.includes('mouse')) {
    preferences.push('Teknoloji ve gaming ürünlerine ilgili');
  }

  if (text.includes('parfum') || text.includes('kozmetik')) {
    preferences.push('Kozmetik ve bakım ürünlerine ilgili');
  }

  // 🔥 Fiyat hassasiyeti
  if (
    text.includes('uygun fiyat') ||
    text.includes('ucuz') ||
    text.includes('fiyat performans')
  ) {
    preferences.push('Fiyat/performans odaklı');
  }

  // 🔥 Marka hassasiyeti
  if (
    text.includes('nike') ||
    text.includes('adidas') ||
    text.includes('apple') ||
    text.includes('samsung')
  ) {
    preferences.push('Marka odaklı seçim yapıyor');
  }

  if (preferences.length === 0) {
    return 'Kullanıcı tercihleri henüz net değil.';
  }

  return preferences.join('\n');
}

function hasUsefulProfileForCategory(userMessage = '', userProfile = null) {
  if (!userProfile) return false;

  const text = normalizeText(userMessage);

  const hasShoeData = Boolean(userProfile.shoeSize && String(userProfile.shoeSize).trim());
  const hasClothingData = Boolean(userProfile.clothingSize && String(userProfile.clothingSize).trim());
  const hasStyleData = Boolean(userProfile.style && String(userProfile.style).trim());
  const hasBodyData =
    Boolean(userProfile.height && String(userProfile.height).trim()) ||
    Boolean(userProfile.weight && String(userProfile.weight).trim());

  const shoeRelated = [
    'ayakkabi', 'sneaker', 'spor ayakkabi', 'bot', 'terlik', 'sandalet'
  ].some((k) => text.includes(k));

  const clothingRelated = [
    'ceket', 'mont', 'elbise', 'pantolon', 'tisort', 'tshirt', 'gomlek',
    'etek', 'kazak', 'sweatshirt', 'hoodie', 'kombin'
  ].some((k) => text.includes(k));

  if (shoeRelated) {
    return hasShoeData || hasStyleData;
  }

  if (clothingRelated) {
    return hasClothingData || hasStyleData || hasBodyData;
  }

  return false;
}

function detectGenericShoppingCategory(userMessage = '') {
  const text = normalizeText(userMessage);

  const categoryMap = [
    {
      keys: ['ayakkabi', 'sneaker', 'bot', 'terlik', 'sandalet'],
      question: 'Nasıl bir ayakkabı arıyorsun? Günlük mü spor mu, ayrıca bütçe aralığın var mı?',
    },
    {
      keys: ['ceket', 'mont', 'elbise', 'pantolon', 'tisort', 'tshirt', 'gomlek', 'etek', 'kazak', 'hoodie', 'sweatshirt', 'kombin'],
      question: 'Nasıl bir model arıyorsun? Günlük mü şık mı, ayrıca bütçe veya renk tercihin var mı?',
    },
    {
      keys: ['catal', 'tabak', 'bardak', 'bicak', 'kasik', 'mutfak'],
      question: 'Nasıl bir ürün arıyorsun? Tekli mi set mi, günlük kullanım mı yoksa daha şık bir şey mi istiyorsun?',
    },
    {
      keys: ['saat'],
      question: 'Nasıl bir saat arıyorsun? Akıllı mı klasik mi, ayrıca bütçe aralığın var mı?',
    },
    {
      keys: ['canta', 'valiz', 'sirt cantasi'],
      question: 'Nasıl bir model arıyorsun? Günlük kullanım mı seyahat mi, ayrıca boyut veya bütçe tercihin var mı?',
    },
    {
      keys: ['mouse', 'klavye', 'kulaklik', 'telefon', 'tablet', 'laptop'],
      question: 'Hangi kullanım için arıyorsun? Günlük mü performans odaklı mı, ayrıca bütçe aralığın var mı?',
    },
    {
      keys: ['kozmetik', 'makyaj', 'kapatici', 'ruj', 'fondoten', 'serum', 'krem', 'parfum'],
      question: 'Nasıl bir ürün arıyorsun? Cilt bakımı mı makyaj mı, ayrıca belirli bir marka veya bütçe tercihin var mı?',
    },
  ];

  for (const item of categoryMap) {
    if (item.keys.some((k) => text.includes(k))) {
      return item.question;
    }
  }

  return null;
}

module.exports = {
  generateChatReply,
  generateChatTitle,
};