const Chat = require('../models/Chat');
const User = require('../models/User');
const { searchGoogleShopping } = require('../services/googleShoppingService');
const { generateSearchQueryFromImage } = require('../services/imageSearchService');

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

    let userProfile = null;

try {
  userProfile = await User.findById(chat.userId).select(
    'shoeSize clothingSize height weight style gender onboardingCompleted'
  );
} catch (e) {
  console.error('User profile fetch error:', e.message);
}

const aiResult = await generateChatReply({
  userMessage: userText,
  previousMessages: chat.messages,
  selectedProduct,
  userProfile,
});

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
      text: typeof safeAssistantText === 'string' ? safeAssistantText : '',
      products: Array.isArray(safeProducts) ? safeProducts : [],
      actions: Array.isArray(safeActions) ? safeActions : [],
      comparison: safeComparison || null,
      detailCard: safeDetailCard || null,
      reviewCard: safeReviewCard || null,
      contextProduct: null,
    });

    await chat.save();

    return res.json({
      assistantText: safeAssistantText,
      products: safeProducts,
      actions: safeActions,
      comparison: safeComparison,
      detailCard: safeDetailCard,
      reviewCard: safeReviewCard,
      chat,
    });
  } catch (error) {
    console.error('Send chat message error:', error.message);
    return res.status(500).json({ error: 'Mesaj işlenemedi' });
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

    const rawResults = await searchGoogleShopping(searchQuery);

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
    console.error('Image search error:', error.message);
    return res.status(500).json({ error: 'Görsel arama başarısız' });
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
};