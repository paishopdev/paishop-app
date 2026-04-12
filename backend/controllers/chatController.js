const Chat = require('../models/Chat');
const {
  generateChatReply,
  generateChatTitle,
} = require('../services/chatAiService');

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
      products: products || [],
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
    const { message } = req.body;

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
    });

    const aiResult = await generateChatReply({
      userMessage: userText,
      previousMessages: chat.messages,
    });

    chat.messages.push({
      role: 'assistant',
      text: aiResult.assistantText || '',
      products: Array.isArray(aiResult.products) ? aiResult.products : [],
      actions: Array.isArray(aiResult.actions) ? aiResult.actions : [],
      comparison: aiResult.comparison || null,
    });

    await chat.save();
    
    return res.json({
      assistantText: aiResult.assistantText || '',
      products: Array.isArray(aiResult.products) ? aiResult.products : [],
      actions: Array.isArray(aiResult.actions) ? aiResult.actions : [],
      comparison: aiResult.comparison || null,
      chat,
    });
  } catch (error) {
    console.error('Send chat message error:', error.message);
    return res.status(500).json({ error: 'Mesaj işlenemedi' });
  }
};

module.exports = {
  createChat,
  getUserChats,
  getChatById,
  deleteChat,
  addMessageToChat,
  sendChatMessage,
};