const express = require('express');
const multer = require('multer');

const {
  createChat,
  getUserChats,
  getChatById,
  deleteChat,
  addMessageToChat,
  sendChatMessage,
  searchByImage,
} = require('../controllers/chatController');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage() });

router.post('/', createChat);
router.get('/user/:userId', getUserChats);
router.get('/:chatId', getChatById);
router.delete('/:chatId', deleteChat);
router.post('/:chatId/message', addMessageToChat);
router.post('/:chatId/send', sendChatMessage);
router.post('/:chatId/image-search', upload.single('image'), searchByImage);

module.exports = router;