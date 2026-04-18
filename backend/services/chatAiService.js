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

  const compareProducts = filterProductsToSameCategory(finalProducts || [], userMessage)
  .slice(0, 3)
  .map((p) => ({
    name: p.name || '',
    price: p.price || '',
    platform: p.platform || '',
    image: p.image || '',
    link: p.link || '',
    short_reason: p.short_reason || '',
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
    .slice(-3);

  let recentProducts = [];

  for (const msg of assistantMessages) {
    recentProducts = [...recentProducts, ...msg.products];
  }

  return normalizeProducts(recentProducts).slice(0, 12);
}

function formatHistory(previousMessages = []) {
  return previousMessages
    .slice(-12)
    .map((m) => `${m.role === 'user' ? 'Kullanıcı' : 'Asistan'}: ${m.text}`)
    .join('\n');
}

async function generatePlanner({ userMessage, previousMessages = [], userProfile = null }) {
  const profileText = formatUserProfile(userProfile);
  const historyText = formatHistory(previousMessages);
  const recentProducts = extractRecentProducts(previousMessages);

  const plannerPrompt = `
Sen shopi'sin gelişmiş bir alışveriş asistanısın.

Görevin kullanıcının son mesajını sınıflandırmak.

Intent türleri:
- Önce kullanıcının mesajının alışverişle ne kadar ilgili olduğunu değerlendir.
- "shopping_relevance" alanını üret:
  - "high" = doğrudan alışveriş / ürün / bütçe / marka / özellik / satın alma kararı
  - "medium" = alışverişe bağlanabilecek ama net olmayan istek
  - "low" = zayıf bağlantı
  - "none" = alışveriş dışı
- Eğer kullanıcı alışverişle ilgili bir şey söylüyor ama ürün tipi / kullanım amacı / bütçe / hedef belirsizse "needs_clarification" alanını true yap.
- needs_clarification true ise kullanıcıya sorulacak tek, doğal ve kısa bir soru üret. Bunu "clarification_question" alanına yaz.
- Eğer kullanıcı kısa gündelik sohbet yapıyorsa "small_talk" alanını true yap.
- Küçük sohbet mesajları için needs_product_search=false yap.
- Belirsiz ama alışveriş odaklı mesajlarda hemen ürün arama; önce netleştirme sorusu üret.
- Kelime listesine bağımlı davranma. Mesajın genel niyetini anlamaya çalış.
- "general_question" = genel bilgi sorusu
- "product_search" = yeni ürün önerisi / arama isteği
- "comparison" = mevcut ürünleri kıyaslama isteği
- "refinement" = önceki aramayı daraltma / bütçe değiştirme / özellik değiştirme
- "best_choice" = önceki ürünler arasından en iyi / en ucuz / fiyat performans seçimi
- Kullanıcı fiyat aralığı verirse bunu çok dikkatli analiz et.
- Örnekler:
  - "1000 tl altı"
  - "2000-3000 tl arası"
  - "1500 ile 2500 arası"
  - "3000 tl üstü"
  - "2500 civarı" ifadesini yaklaşık 2000-3000 bandı gibi düşün.
- "2000 bandında" ifadesini yaklaşık 1500-2500 bandı gibi düşün.
- "3000'e kadar" ifadesini 3000 altı olarak düşün.
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
- search_query üretirken fiyat bilgisi yazma ama ürün tipi ve önemli özellikleri ekle.
- "uygun fiyatlı" veya "çok pahalı olmasın" gibi ifadeleri bütçe hassasiyeti olarak yorumla.
- Eğer kullanıcı yeni bir fiyat filtresi veriyorsa bunu refinement veya product_search olarak değerlendir.
- search_query üretirken fiyat bilgisini de kısa şekilde dahil et.

Kurallar:
- Eğer kullanıcı mesajı çok genel bir ürün isteğiyse ve doğru sonuç vermek için kullanım amacı, tarz, tür, bütçe veya alt kategori bilgisi gerekiyorsa needs_clarification=true yap.
- Eğer kullanıcı profili varsa ve bu profil ilgili kategori için güçlü sinyal sağlıyorsa clarification yerine direkt ürün aramaya daha yatkın olabilirsin.
- Ancak kullanıcı profili alakasızsa sadece profil var diye direkt ürün arama.
- Ev, mutfak, dekorasyon, aksesuar, saat, çatal, tabak, bardak gibi kategorilerde kullanıcı profili çoğu zaman yeterli değildir; bu tür durumlarda belirsizlik varsa soru sormayı tercih et.
- Ayakkabı, giyim, kombin gibi kategorilerde kullanıcı profili güçlü sinyal olabilir.
- needs_clarification true olduğunda clarification_question kısa, doğal ve kategoriye uygun olsun.
- Eğer kullanıcı önceki ürünlere atıf yapıyorsa bunu anlamaya çalış.
- "bunlardan", "en iyisi", "2. ürün", "4. ürün", "en ucuz" gibi ifadeleri dikkate al.
- Eğer yeni ürün aramak gerekiyorsa kısa bir arama sorgusu üret.
- Eğer önceki ürünleri kullanmak yeterliyse needs_product_search=false yap.
- Eğer kullanıcı fiyat filtresi verdiyse ve bulunan ürünler bu aralığa tam uymuyorsa, bunu açıkça belirt.
- Fiyat filtresine uymayan ürünleri önerme.
- Eğer kullanıcı profili varsa niyeti ve ürün türünü buna göre daha iyi anlamaya çalış.
- Ayakkabı, giyim, stil ve kombin isteklerinde kullanıcı profilini dikkate al.
- Profil bilgisi varsa gereksiz tekrar yapma, bunu akıllı bir yardımcı sinyal olarak kullan.
- Eğer uygun ürün yoksa products boş dizi olabilir ve bunu dürüstçe söyle.
- Bu uygulama sadece alışveriş, ürün önerisi, ürün karşılaştırma, fiyat, özellik, marka, bütçe ve satın alma kararları için kullanılmaktadır.
- Eğer kullanıcının sorusu alışverişle ilgili değilse intent'i "general_question" olarak işaretle.
- Alışveriş dışı genel bilgi sorularında needs_product_search=false yap.
- Alışveriş dışı sorular için ürün önerme.
- search_query üretirken fiyat bilgisini yazma; sadece ürün tipini ve temel özelliği yaz.
- Fiyat aralığı backend tarafından ayrıca filtrelenecek.
- Kullanıcı belirli özellikler istediyse bunlara en uygun ürünleri öne çıkar.
- Eğer bazı ürünler özelliklere daha çok uyuyorsa bunu short_reason içinde belirt.
- "civarı", "bandında", "e kadar", "uygun fiyatlı" gibi bütçe ifadelerini dikkate al.
- Bu tür durumlarda yaklaşık fiyat aralığına uygun ürünleri tercih et.
- Eğer ürün listesi döndürüyorsan aşağıdaki aksiyonları da üret:
  "En iyisini seç"
  "Karşılaştır"
  "Daha ucuz alternatifler"
  "Benzer ürünler"
- actions alanı string listesi olmalı.
- Sadece geçerli JSON döndür.
- Markdown kullanma.
- Eğer ürün döndürüyorsan her ürün için mutlaka "short_reason" alanı üret.
- short_reason kısa, net ve faydalı olsun.

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
}) {
  const profileText = formatUserProfile(userProfile);
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
- Eğer kullanıcı profili varsa ürün önerirken bunu dikkate al.
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
})  

{
  if (selectedProduct) {
    console.log("DETAIL FLOW ACTIVE FOR:", selectedProduct.name);

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
      detailCard: {
        product: {
          name: selectedProduct.name || '',
          price: selectedProduct.price || '',
          platform: selectedProduct.platform || '',
          image: selectedProduct.image || '',
          link: selectedProduct.link || '',
        },
        title: detailResult.title || 'Ürün detayı',
        bullets: Array.isArray(detailResult.bullets)
          ? detailResult.bullets.slice(0, 4)
          : [],
      },
    };
  }
  console.log("NEW GENERATECHATREPLY ACTIVE:", userMessage);

  const recentProducts = extractRecentProducts(previousMessages);
  const comparisonProducts = extractRecentProductsForComparison(previousMessages, 4);
  const referencedProduct = resolveProductReference(userMessage, recentProducts);
  const referenceAction = buildReferenceBasedReply(userMessage, referencedProduct);
  const isComparisonRequest = isComparisonLikeRequest(userMessage);

  const actionCommand = detectActionCommand(userMessage);
  const latestBatchProducts = extractLastProductBatch(previousMessages);
  const stableBatchProducts = filterProductsToSameCategory(
    latestBatchProducts.length > 0 ? latestBatchProducts : comparisonProducts,
    userMessage
  );

  if (actionCommand === 'compare') {
    const compareProducts =
      stableBatchProducts.length >= 2 ? stableBatchProducts : comparisonProducts;

    const deterministicComparison = buildDeterministicComparison(compareProducts);

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
  if (genericCategoryQuestion && wordCount <= 3) {
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

      let broaderFiltered = filterProductsByPriceIntent(
        broaderResults,
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

        let broaderFilteredLevel1 = filterProductsByExplicitRange(
          broaderResults,
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
  });

  if (isComparisonRequest && comparisonProducts.length >= 2) {
    return {
      assistantText: answer.assistant_text || 'Senin için seçenekleri karşılaştırdım.',
      products: [],
      actions: normalizeActions(answer.actions),
      comparison: buildComparisonData(answer, comparisonProducts, userMessage),
    };
  }

  const finalProducts =
    Array.isArray(answer.products) && answer.products.length > 0
      ? normalizeProducts(answer.products)
      : normalizeProducts(searchedProducts);

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

  const compareSourceProducts =
    isComparisonRequest && comparisonProducts.length >= 2
      ? comparisonProducts
      : finalProducts;

  const comparison = buildComparisonData(
    answer,
    compareSourceProducts,
    userMessage
  );

  return {
    assistantText: polishedAssistantText,
    products: displayProducts,
    actions: finalActions,
    comparison,
  };
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