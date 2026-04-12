const express = require('express');
const {
  createChat,
  getUserChats,
  getChatById,
  deleteChat,
  addMessageToChat,
  sendChatMessage,
} = require('../controllers/chatController');

const router = express.Router();

router.post('/', createChat);
router.get('/user/:userId', getUserChats);
router.get('/:chatId', getChatById);
router.delete('/:chatId', deleteChat);
router.post('/:chatId/message', addMessageToChat);
router.post('/:chatId/send', sendChatMessage);

module.exports = router;