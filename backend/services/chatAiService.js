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
  const actions = [];

  if (!products || products.length === 0) {
    return actions;
  }

  if (products.length >= 2) {
    actions.push('Karşılaştır');
  }

  actions.push('Daha ucuz alternatifler');
  actions.push('Benzer ürünler');
  actions.push('En iyisini seç');

  const normalizedMessage = String(userMessage).toLowerCase();

  if (
    normalizedMessage.includes('telefon') ||
    normalizedMessage.includes('kulaklık') ||
    normalizedMessage.includes('mouse') ||
    normalizedMessage.includes('tablet') ||
    normalizedMessage.includes('şarj') ||
    normalizedMessage.includes('sarj')
  ) {
    actions.push('Fiyat performans öner');
  }

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

  const compareProducts = (finalProducts || []).slice(0, 3).map((p) => ({
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

async function generatePlanner({ userMessage, previousMessages = [] }) {
  const historyText = formatHistory(previousMessages);
  const recentProducts = extractRecentProducts(previousMessages);

  const plannerPrompt = `
Sen gelişmiş bir AI alışveriş asistanısın.

Görevin kullanıcının son mesajını sınıflandırmak.

Intent türleri:
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
- Eğer kullanıcı önceki ürünlere atıf yapıyorsa bunu anlamaya çalış.
- "bunlardan", "en iyisi", "2. ürün", "4. ürün", "en ucuz" gibi ifadeleri dikkate al.
- Eğer yeni ürün aramak gerekiyorsa kısa bir arama sorgusu üret.
- Eğer önceki ürünleri kullanmak yeterliyse needs_product_search=false yap.
- Eğer kullanıcı fiyat filtresi verdiyse ve bulunan ürünler bu aralığa tam uymuyorsa, bunu açıkça belirt.
- Fiyat filtresine uymayan ürünleri önerme.
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
  "needs_product_search": false,
  "search_query": "",
  "uses_recent_products": false
}

Sohbet geçmişi:
${historyText || 'Yok'}

Önceki ürünler:
${JSON.stringify(recentProducts, null, 2)}

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
  needs_product_search: false,
  search_query: '',
  uses_recent_products: false,
};
}

async function generateAnswer({
  userMessage,
  previousMessages = [],
  planner,
  searchedProducts = [],
}) {
  const historyText = formatHistory(previousMessages);
  const recentProducts = extractRecentProducts(previousMessages);
  const normalizedSearchedProducts = normalizeProducts(searchedProducts);

  const answerPrompt = `
Sen konuşkan, doğal, yardımcı ve akıllı bir AI alışveriş asistanısın.
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

function buildSmallTalkReply(userMessage = '') {
  const text = String(userMessage).toLowerCase().trim();

  if (
    text === 'merhaba' ||
    text === 'selam' ||
    text === 'selamlar' ||
    text === 'hey' ||
    text === 'hi' ||
    text === 'hello'
  ) {
    return 'Merhaba 👋 Ben PaiShop. İstersen sana ürün önerileri, karşılaştırma ya da bütçene uygun seçenekler konusunda yardımcı olayım.';
  }

  if (
    text.includes('nasılsın') ||
    text.includes('nasilsin') ||
    text.includes('iyi misin')
  ) {
    return 'İyiyim, teşekkür ederim 😊 Senin için güzel ürünler bulmaya hazırım. Ne arıyorsun?';
  }

  if (
    text.includes('napıyorsun') ||
    text.includes('napiyorsun') ||
    text.includes('ne yapıyorsun')
  ) {
    return 'Buradayım, sana en uygun ürünleri bulmak ve karşılaştırmak için hazırım 😄';
  }

  if (
    text.includes('teşekkürler') ||
    text.includes('tesekkurler') ||
    text.includes('teşekkür ederim') ||
    text.includes('tesekkur ederim') ||
    text.includes('sağ ol') ||
    text.includes('sag ol')
  ) {
    return 'Rica ederim 😊 İstersen başka bir ürün için de yardımcı olayım.';
  }

  if (
    text.includes('görüşürüz') ||
    text.includes('gorusuruz') ||
    text.includes('hoşçakal') ||
    text.includes('hoscakal') ||
    text.includes('bye')
  ) {
    return 'Görüşürüz 👋 İhtiyacın olursa yine buradayım.';
  }

  return null;
}

async function generateChatReply({ userMessage, previousMessages = [] }) {
  const recentProducts = extractRecentProducts(previousMessages);
  const referencedProduct = resolveProductReference(userMessage, recentProducts);
  const referenceAction = buildReferenceBasedReply(userMessage, referencedProduct);
  const isComparisonRequest = isComparisonLikeRequest(userMessage);

  const planner = await generatePlanner({
    userMessage,
    previousMessages,
  });

  const text = String(userMessage).toLowerCase().trim();

const shoppingKeywords = [
  'ürün', 'öner', 'oner', 'fiyat', 'bütçe', 'butce', 'karşılaştır', 'karsilastir',
  'telefon', 'kulaklık', 'kulaklik', 'mouse', 'tablet', 'bilgisayar', 'laptop',
  'şarj', 'sarj', 'kamera', 'krem', 'makyaj', 'ayakkabı', 'ayakkabi', 'elbise',
  'hediye', 'marka', 'ucuz', 'pahalı', 'pahali', 'benzer', 'alternatif',
  'çanta', 'canta', 'saat', 'parfüm', 'parfum', 'kulak içi', 'oyuncu', 'gaming'
];

const isShoppingRelated = shoppingKeywords.some((keyword) => text.includes(keyword));
const smallTalkReply = buildSmallTalkReply(userMessage);

if (!isShoppingRelated && planner.intent === 'general_question') {
  if (smallTalkReply) {
    return {
      assistantText: smallTalkReply,
      products: [],
      actions: [],
      comparison: null,
    };
  }

  return {
    assistantText:
      'Ben daha çok alışveriş, ürün önerisi ve karşılaştırma konusunda yardımcı oluyorum. İstersen bir ürün, kategori, bütçe veya özellik söyle; sana uygun seçenekler bulayım.',
    products: [],
    actions: [],
    comparison: null,
  };
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
  
        if (hasPriceFilter && filteredResults.length < 4) {
          const broaderResults = await searchGoogleShopping(
            sanitizeSearchQuery(userMessage)
          );
        
          let bestExpandedResults = [...filteredResults];
        
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
        
          if (broaderFilteredLevel1.length > bestExpandedResults.length) {
            bestExpandedResults = broaderFilteredLevel1;
          }
        
          if (bestExpandedResults.length < 4) {
            const expandedLevel2 = expandPriceRange(min, max, 2);
        
            let broaderFilteredLevel2 = filterProductsByExplicitRange(
              broaderResults,
              expandedLevel2.min,
              expandedLevel2.max
            );
        
            if (broaderFilteredLevel2.length > 0) {
              const featureFilteredLevel2 = filterProductsByFeatures(
                broaderFilteredLevel2,
                userMessage
              );
        
              if (featureFilteredLevel2.length > 0) {
                broaderFilteredLevel2 = featureFilteredLevel2;
              }
            }
        
            broaderFilteredLevel2 = removeWeakProducts(
              broaderFilteredLevel2,
              userMessage,
              planner.search_query
            );
        
            broaderFilteredLevel2 = scoreAndRankProducts(
              broaderFilteredLevel2,
              userMessage,
              planner.search_query
            );
        
            if (broaderFilteredLevel2.length > bestExpandedResults.length) {
              bestExpandedResults = broaderFilteredLevel2;
            }
          }
        
          if (bestExpandedResults.length > 0) {
            filteredResults = bestExpandedResults;
          }
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
  });

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

const comparison = buildComparisonData(
  answer,
  finalProducts,
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

module.exports = {
  generateChatReply,
  generateChatTitle,
};