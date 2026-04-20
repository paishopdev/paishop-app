require('dotenv').config();
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const mongoose = require('mongoose');

const chatRoutes = require('./routes/chat');
const favoriteRoutes = require('./routes/favorite');
const recommendationRoutes = require('./routes/recommendations');
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/userRoutes');

const app = express();
const PORT = process.env.PORT || 3000;

mongoose
  .connect(process.env.MONGO_URI)
  .then(() => console.log('MongoDB connected'))
  .catch((error) => console.error('MongoDB connection error:', error.message));

app.use(
  cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  })
);

app.options('*', cors());

app.use(express.json());

app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl}`);
  next();
});

app.get('/api/image-proxy', async (req, res) => {
  try {
    const imageUrl = req.query.url;

    if (!imageUrl || typeof imageUrl !== 'string') {
      return res.status(400).send('Missing image url');
    }

    const response = await axios.get(imageUrl, {
      responseType: 'arraybuffer',
      timeout: 15000,
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        Referer: 'https://www.google.com/',
        Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      },
    });

    const contentType = response.headers['content-type'] || 'image/jpeg';

    res.set('Content-Type', contentType);
    res.set('Cache-Control', 'public, max-age=86400');
    return res.send(response.data);
  } catch (error) {
    console.error('Image proxy error:', error.message);
    return res.status(500).send('Failed to load image');
  }
});

app.use('/api', recommendationRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/chats', chatRoutes);
app.use('/api/favorites', favoriteRoutes);

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/', (req, res) => {
  res.send('API is running');
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});