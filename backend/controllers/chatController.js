const Chat = require('../models/Chat');
const User = require('../models/User');
const Favorite = require('../models/Favorite');
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
            ...(m.toObject?.() || m),
            _sourceChatId: String(c._id),
          }))
        : []
    );

  const normalizedCurrentMessages = currentMessages.map((m) => ({
    ...(m.toObject?.() || m),
    _sourceChatId: currentChatId,
  }));

  const merged = [
    ...otherMessages.slice(-40),
    ...normalizedCurrentMessages,
  ];

  return merged.slice(-60);
}
const { searchProducts } = require('../services/shoppingSearchService');

const {
  generateSearchQueryFromImage,
  generateSearchQueriesFromImages,
} = require('../services/imageSearchService');
const {
  generateChatReply,
  generateChatTitle,
} = require('../services/chatAiService');

console.log('CHAT CONTROLLER VERSION: normalizeActions v2 loaded');

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

const createChat = async (req, res) => {
  try {
    const { userId, firstMessage } = req.body;

    if (!userId) {
      return res.status(400).json({ error: 'userId zorunlu' });
    }

    let title = 'Yeni Sohbet';

    if (firstMessage && firstMessage.trim().length > 0) {
      try {
        title = await generateChatTitle(firstMessage.trim());
      } catch (e) {
        title = firstMessage.trim().substring(0, 40);
      }
    }

    const chat = await Chat.create({
      userId,
      title,
      messages: [],
    });

    return res.status(201).json(chat);
  } catch (error) {
    console.error('Create chat error:', error.message);
    return res.status(500).json({ error: 'Sohbet oluşturulamadı' });
  }
};

const getUserChats = async (req, res) => {
  try {
    const { userId } = req.params;
    const chats = await Chat.find({ userId }).sort({ updatedAt: -1 });
    return res.json(chats);
  } catch (error) {
    console.error('Get user chats error:', error.message);
    return res.status(500).json({ error: 'Sohbetler alınamadı' });
  }
};

const getChatById = async (req, res) => {
  try {
    const { chatId } = req.params;
    const chat = await Chat.findById(chatId);

    if (!chat) {
      return res.status(404).json({ error: 'Sohbet bulunamadı' });
    }

    return res.json(chat);
  } catch (error) {
    console.error('Get chat by id error:', error.message);
    return res.status(500).json({ error: 'Sohbet alınamadı' });
  }
};

const deleteChat = async (req, res) => {
  try {
    const { chatId } = req.params;
    const deleted = await Chat.findByIdAndDelete(chatId);

    if (!deleted) {
      return res.status(404).json({ error: 'Sohbet bulunamadı' });
    }

    return res.json({ message: 'Sohbet silindi' });
  } catch (error) {
    console.error('Delete chat error:', error.message);
    return res.status(500).json({ error: 'Sohbet silinemedi' });
  }
};

const addMessageToChat = async (req, res) => {
  try {
    const { chatId } = req.params;
    const { role, text, products } = req.body;

    if (!role || !text) {
      return res.status(400).json({ error: 'role ve text zorunlu' });
    }

    const chat = await Chat.findById(chatId);

    if (!chat) {
      return res.status(404).json({ error: 'Sohbet bulunamadı' });
    }

    chat.messages.push({
      role,
      text,
      products: Array.isArray(products) ? products : [],
      actions: [],
      comparison: null,
    });

  

    await chat.save();

    return res.json(chat);
  } catch (error) {
    console.error('Add message error:', error.message);
    return res.status(500).json({ error: 'Mesaj eklenemedi' });
  }
};

function normalizeMemoryText(text = '') {
  return String(text || '')
    .toLowerCase()
    .replace(/ı/g, 'i')
    .replace(/ğ/g, 'g')
    .replace(/ü/g, 'u')
    .replace(/ş/g, 's')
    .replace(/ö/g, 'o')
    .replace(/ç/g, 'c');
}

function uniqueLimit(existing = [], incoming = [], limit = 8) {
  const set = new Set([
    ...(existing || []).map((e) => String(e).trim()).filter(Boolean),
    ...(incoming || []).map((e) => String(e).trim()).filter(Boolean),
  ]);

  return [...set].slice(0, limit);
}

function extractPassiveMemorySignals(userText = '', favoriteProducts = []) {
  const text = normalizeMemoryText(userText);

  const brands = [];
  const categories = [];
  const colors = [];
  const features = [];
  let budgetRange = '';
  let shoppingStyle = '';

  const brandList = [
    'apple',
    'samsung',
    'xiaomi',
    'dyson',
    'logitech',
    'steelseries',
    'razer',
    'jbl',
    'sony',
    'nike',
    'adidas',
    'puma',
    'zara',
    'mango',
    'lenovo',
    'asus',
    'msi',
    'hp',
  ];

  for (const brand of brandList) {
    if (text.includes(brand)) brands.push(brand);
  }

  const categoryMap = {
    mouse: ['mouse', 'gaming mouse'],
    kulaklik: ['kulaklik', 'headset', 'airpods'],
    telefon: ['telefon', 'iphone', 'samsung'],
    laptop: ['laptop', 'bilgisayar'],
    ayakkabi: ['ayakkabi', 'sneaker'],
    parfum: ['parfum'],
    sac_bakim: ['sac', 'dyson', 'sac duzlestirici', 'airwrap'],
    cilt_bakim: ['cilt', 'sivilce', 'siyah nokta', 'serum', 'krem'],
  };

  for (const [category, words] of Object.entries(categoryMap)) {
    if (words.some((w) => text.includes(w))) {
      categories.push(category);
    }
  }

  const colorList = [
    'siyah',
    'beyaz',
    'gri',
    'mavi',
    'lacivert',
    'kirmizi',
    'yesil',
    'bej',
    'kahverengi',
    'pembe',
    'mor',
  ];

  for (const color of colorList) {
    if (text.includes(color)) colors.push(color);
  }

  const featureMap = {
    kablosuz: ['kablosuz', 'wireless', 'bluetooth'],
    gaming: ['gaming', 'oyuncu'],
    premium: ['premium', 'kaliteli', 'ust seviye'],
    fiyat_performans: ['fiyat performans', 'f/p', 'fp'],
    hafif: ['hafif'],
    dayanikli: ['dayanikli', 'saglam'],
  };

  for (const [feature, words] of Object.entries(featureMap)) {
    if (words.some((w) => text.includes(w))) {
      features.push(feature);
    }
  }

  const priceMatches = text.match(/(\d{3,7})\s*(tl|₺|lira)?/g) || [];
  if (priceMatches.length > 0) {
    const values = priceMatches
      .map((m) => parseInt(m.replace(/[^\d]/g, ''), 10))
      .filter((n) => !isNaN(n) && n >= 100);

    if (values.length === 1) {
      budgetRange = `${values[0]} TL civarı`;
    }

    if (values.length >= 2) {
      const sorted = values.sort((a, b) => a - b);
      budgetRange = `${sorted[0]}-${sorted[sorted.length - 1]} TL arası`;
    }
  }

  if (
    text.includes('ucuz') ||
    text.includes('uygun fiyat') ||
    text.includes('fiyat performans')
  ) {
    shoppingStyle = 'Fiyat/performans odaklı';
  }

  if (
    text.includes('premium') ||
    text.includes('kaliteli') ||
    text.includes('en iyi')
  ) {
    shoppingStyle = shoppingStyle
      ? 'Hem kalite hem fiyat dengesine önem veriyor'
      : 'Kalite odaklı';
  }

  for (const product of favoriteProducts || []) {
    const pText = normalizeMemoryText(
      `${product.name || ''} ${product.platform || ''}`
    );

    for (const brand of brandList) {
      if (pText.includes(brand)) brands.push(brand);
    }

    for (const [category, words] of Object.entries(categoryMap)) {
      if (words.some((w) => pText.includes(w))) {
        categories.push(category);
      }
    }
  }

  return {
    brands,
    categories,
    colors,
    features,
    budgetRange,
    shoppingStyle,
  };
}

async function updatePassiveUserMemory(userId, userText, favoriteProducts = []) {
  try {
    if (!userId || !userText) return;

    const signals = extractPassiveMemorySignals(userText, favoriteProducts);

    const user = await User.findById(userId).select(
      'favoriteBrands favoriteCategories preferredColors preferredFeatures budgetRange shoppingStyle'
    );

    if (!user) return;

    user.favoriteBrands = uniqueLimit(user.favoriteBrands, signals.brands, 10);
    user.favoriteCategories = uniqueLimit(user.favoriteCategories, signals.categories, 10);
    user.preferredColors = uniqueLimit(user.preferredColors, signals.colors, 8);
    user.preferredFeatures = uniqueLimit(user.preferredFeatures, signals.features, 10);

    if (signals.budgetRange) {
      user.budgetRange = signals.budgetRange;
    }

    if (signals.shoppingStyle) {
      user.shoppingStyle = signals.shoppingStyle;
    }

    await user.save();

    console.log('PASSIVE MEMORY UPDATED:', userId);
  } catch (err) {
    console.log('PASSIVE MEMORY ERROR:', err.message);
  }
}

const sendChatMessage = async (req, res) => {
  try {
    const { chatId } = req.params;
    const { message, selectedProduct } = req.body;

    console.log("REQ.BODY MESSAGE:", message);
    console.log("REQ.BODY SELECTED PRODUCT:", selectedProduct);

    if (!message || !message.trim()) {
      return res.status(400).json({ error: 'Mesaj zorunlu' });
    }

    const chat = await Chat.findById(chatId);

    if (!chat) {
      return res.status(404).json({ error: 'Sohbet bulunamadı' });
    }

    let allUserChats = [];
    let favoriteProducts = [];
    let userProfile = null;
    
    try {
      const [chatsResult, favoriteDocs, profileResult] = await Promise.all([
        Chat.find({ userId: chat.userId }).sort({ updatedAt: -1 }).limit(10),
        Favorite.find({ userId: chat.userId }).sort({ createdAt: -1 }).limit(30),
        User.findById(chat.userId).select(
          'shoeSize clothingSize height weight style gender onboardingCompleted favoriteBrands favoriteCategories preferredColors preferredFeatures budgetRange shoppingStyle'
        ),
      ]);
    
      allUserChats = chatsResult || [];
    
      favoriteProducts = (favoriteDocs || [])
        .map((fav) => fav.product)
        .filter(Boolean);
    
      userProfile = profileResult || null;
    } catch (e) {
      console.error('Parallel context fetch error:', e.message);
    }
    
    const userText = message.trim();
    
    chat.messages.push({
      role: 'user',
      text: userText,
      products: [],
      actions: [],
      comparison: null,
      detailCard: null,
      contextProduct: selectedProduct
        ? {
            name: selectedProduct.name || '',
            image: selectedProduct.image || '',
          }
        : null,
    });
const memoryMessages = buildCrossChatMemory(chat, allUserChats);

let aiResult;


try { 
  aiResult = await generateChatReply({ 
    userMessage: userText, 
    previousMessages: memoryMessages, 
    selectedProduct, 
    userProfile, 
    favoriteProducts, });
} 

catch (error) {
  console.error("AI ERROR:", error.message);
  console.error("AI ERROR STATUS:", error.status || error.response?.status || null);
  console.error("AI ERROR DATA:", error.response?.data || error.error || null);

  const products = await searchProducts(userText);

  aiResult = {
    assistantText: products.length > 0
      ? "Senin için uygun ürünleri listeledim."
      : "Şu an yapay zeka cevabı üretirken sorun oldu ve uygun ürün bulamadım. Biraz daha net yazarak tekrar deneyebilirsin.",
    products: products.slice(0, 10),
    actions: products.length > 0
      ? ["Karşılaştır", "Daha ucuz alternatifler", "Benzer ürünler"]
      : [],
    comparison: null,
    detailCard: null,
    reviewCard: null,
    sellerComparison: null,
  };
}

    const safeProducts = Array.isArray(aiResult.products) ? aiResult.products : [];
    const safeActions = normalizeActions(aiResult.actions);
    const safeComparison = aiResult.comparison || null;
    const safeAssistantText =
  (typeof aiResult.assistantText === 'string' && aiResult.assistantText.trim().length > 0)
    ? aiResult.assistantText.trim()
    : (aiResult.detailCard ? 'Ürün detayını hazırladım.' : 'Sana yardımcı olmaya çalışıyorum.');
    const safeDetailCard = aiResult.detailCard || null;
    const safeReviewCard = aiResult.reviewCard || null;

    console.log('normalizeActions typeof =', typeof normalizeActions);
    console.log("SELECTED PRODUCT:", selectedProduct);

    chat.messages.push({
      role: 'assistant',
      text: typeof aiResult.assistantText === 'string' ? aiResult.assistantText : '',
      products: Array.isArray(aiResult.products) ? aiResult.products : [],
      actions: Array.isArray(aiResult.actions) ? aiResult.actions : [],
      comparison: aiResult.comparison || null,
      detailCard: aiResult.detailCard || null,
      reviewCard: aiResult.reviewCard || null,
      sellerComparison: aiResult.sellerComparison || null,
      contextProduct: null,
    });

    await updatePassiveUserMemory(chat.userId, userText, favoriteProducts);

    await chat.save();

    return res.json({
      assistantText: safeAssistantText,
      products: safeProducts,
      actions: safeActions,
      comparison: safeComparison,
      detailCard: safeDetailCard,
      reviewCard: safeReviewCard,
      sellerComparison: aiResult.sellerComparison || null,
      chat,
    });
  } catch (error) {
    console.error('Send chat message error:', error.message);
    console.error('ERROR STATUS:', error.response?.status);
    console.error('ERROR URL:', error.config?.url);
    console.error('ERROR METHOD:', error.config?.method);
    console.error('ERROR DATA:', JSON.stringify(error.response?.data, null, 2));
  
    return res.status(500).json({
      error: 'Mesaj işlenemedi',
      detail: error.message,
      status: error.response?.status || null,
      url: error.config?.url || null,
    });
  }
};

const searchByImage = async (req, res) => {
  try {
    const { chatId } = req.params;

    if (!req.file) {
      return res.status(400).json({ error: 'Görsel zorunlu' });
    }

    const chat = await Chat.findById(chatId);

    if (!chat) {
      return res.status(404).json({ error: 'Sohbet bulunamadı' });
    }

    const mimeType = req.file.mimetype || 'image/jpeg';
    const base64Image = req.file.buffer.toString('base64');

    const searchQuery = await generateSearchQueryFromImage(base64Image, mimeType);

    if (!searchQuery || !searchQuery.trim()) {
      return res.status(200).json({
        assistantText:
          'Görselden ürünü net ayırt edemedim. İstersen daha yakın veya daha net bir fotoğrafla tekrar deneyelim.',
        products: [],
        actions: [],
        comparison: null,
      });
    }

    const rawResults = await searchProducts(searchQuery, 'image');

    const products = (rawResults || []).slice(0, 10).map((item, index) => ({
      index: index + 1,
      name: item.name || '',
      price: item.price || '',
      platform: item.platform || '',
      image: item.image || '',
      link: item.link || '',
      rating: item.rating || null,
      reviews: item.reviews || null,
      short_reason: 'Görsele en yakın eşleşmelerden biri olarak öne çıktı.',
    }));

    const assistantText = `"${searchQuery}" için görsele benzer ürünleri buldum.`;

    chat.messages.push({
      role: 'user',
      text: 'Görsel ile ürün arandı',
      products: [],
      actions: [],
      comparison: null,
      detailCard: null,
      reviewCard: null,
      sellerComparison: null,
      imageAttachments: [`data:${mimeType};base64,${base64Image}`],
      contextProduct: null,
    });

    chat.messages.push({
      role: 'assistant',
      text: assistantText,
      products,
      actions: ['Benzer ürünler', 'Daha ucuz alternatifler'],
      comparison: null,
      detailCard: null,
      reviewCard: null,
      contextProduct: null,
    });

    await chat.save();

    return res.json({
      assistantText,
      products,
      actions: ['Benzer ürünler', 'Daha ucuz alternatifler'],
      comparison: null,
      detailCard: null,
      reviewCard: null,
      searchQuery,
      chat,
    });
  } catch (error) {
    console.error('Image search error:', error);
    return res.status(500).json({ error: 'Görsel arama başarısız' });
  }
};

const searchByImageContext = async (req, res) => {
  try {
    const { chatId } = req.params;
    const { message } = req.body;

    if (!req.files || req.files.length === 0) {
      return res.status(400).json({ error: 'En az bir görsel gerekli' });
    }

    if (!message || !message.trim()) {
      return res.status(400).json({ error: 'Mesaj zorunlu' });
    }

    const chat = await Chat.findById(chatId);

    if (!chat) {
      return res.status(404).json({ error: 'Sohbet bulunamadı' });
    }

    const allUserChats = await Chat.find({ userId: chat.userId }).sort({ updatedAt: -1 });
const memoryMessages = buildCrossChatMemory(chat, allUserChats);

const favoriteDocs = await Favorite.find({ userId: chat.userId }).sort({ createdAt: -1 });
const favoriteProducts = favoriteDocs
  .map((fav) => fav.product)
  .filter(Boolean);

    const userText = message.trim();

    if (
      !/urun|ürün|bul|nedir|benzer|ara|oner|öner|goster|göster|bu ne|hangi ürün/i.test(userText)
    ) {
      return res.status(200).json({
        assistantText:
          'Yüklediğin görseller için ürün bulma, benzerini arama veya ne olduğunu anlama konusunda yardımcı olabilirim. İstersen "ürünü bul" gibi bir şey yaz.',
        products: [],
        actions: [],
        comparison: null,
      });
    }

    const imagePayloads = req.files.slice(0, 3).map((file) => {
      let safeMimeType = file.mimetype || 'image/jpeg';

      if (!safeMimeType.startsWith('image/')) {
        const originalName = String(file.originalname || '').toLowerCase();

        if (originalName.endsWith('.png')) {
          safeMimeType = 'image/png';
        } else if (originalName.endsWith('.webp')) {
          safeMimeType = 'image/webp';
        } else {
          safeMimeType = 'image/jpeg';
        }
      }

      return {
        mimeType: safeMimeType,
        base64: file.buffer.toString('base64'),
      };
    });

    const queryResult = await generateSearchQueriesFromImages(imagePayloads, userText);

    const candidateQueries = [
      queryResult.primary_query,
      ...(queryResult.alternative_queries || []),
    ]
      .map((q) => String(q || '').trim())
      .filter(Boolean);

    console.log('IMAGE CANDIDATE QUERIES:', candidateQueries);

    if (candidateQueries.length === 0) {
      return res.status(200).json({
        assistantText:
          'Görsellerden ürünü net ayırt edemedim. İstersen daha net fotoğraflarla tekrar deneyelim.',
        products: [],
        actions: [],
        comparison: null,
      });
    }

    let usedQuery = candidateQueries[0];
    let rawResults = [];

    for (const query of candidateQueries) {
      try {
        const results = await searchProducts(query, 'image');

        if (Array.isArray(results) && results.length > 0) {
          rawResults = results;
          usedQuery = query;
          break;
        }
      } catch (searchErr) {
        console.error('searchGoogleShopping error for query:', query);
        console.error(searchErr.message);
      }
    }

    const products = (rawResults || []).slice(0, 10).map((item, index) => ({
      index: index + 1,
      name: item.name || '',
      price: item.price || '',
      platform: item.platform || '',
      image: item.image || '',
      link: item.link || '',
      rating: item.rating || null,
      reviews: item.reviews || null,
      short_reason: 'Yüklediğin görsellerle benzer özellik gösterdi.',
    }));

    const assistantText =
      products.length > 0
        ? `"${usedQuery}" için görsellerine yakın ürünleri buldum.`
        : 'Görselleri analiz ettim ama net eşleşme bulamadım. İstersen farklı açıdan veya daha net görsellerle tekrar deneyelim.';

        const imageAttachments = imagePayloads.map((img) => {
          return `data:${img.mimeType};base64,${img.base64}`;
        });

        chat.messages.push({
          role: 'user',
          text: userText,
          products: [],
          actions: [],
          comparison: null,
          detailCard: null,
          reviewCard: null,
          sellerComparison: null,
          imageAttachments,
          contextProduct: null,
        });

    chat.messages.push({
      role: 'assistant',
      text: assistantText,
      products,
      actions: products.length > 0 ? ['Benzer ürünler', 'Daha ucuz alternatifler'] : [],
      comparison: null,
      detailCard: null,
      reviewCard: null,
      contextProduct: null,
    });

    await chat.save();

    return res.json({
      assistantText,
      products,
      actions: products.length > 0 ? ['Benzer ürünler', 'Daha ucuz alternatifler'] : [],
      comparison: null,
      detailCard: null,
      reviewCard: null,
      searchQuery: usedQuery,
      chat,
    });
  } catch (error) {
    console.error('Image context search error:', error);
    return res.status(500).json({ error: 'Görsellerle arama başarısız' });
  }
};

module.exports = {
  createChat,
  getUserChats,
  getChatById,
  deleteChat,
  addMessageToChat,
  sendChatMessage,
  searchByImage,
  searchByImageContext,
};