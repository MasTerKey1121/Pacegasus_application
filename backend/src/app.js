const path = require('path');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const env = require('./config/env');
const routes = require('./routes');
const { notFound, errorHandler } = require('./middleware/errorHandler');
const usageLogMiddleware = require('./middleware/usageLog'); 
const asyncHandler = require('./utils/asyncHandler');
const { getImage } = require('./services/clubImageService');

const app = express();

app.use(helmet());
app.use(
  cors({
    origin: env.clientUrl === '*' ? true : env.clientUrl,
    credentials: true,
  })
);
app.use('/api/clubs/images', express.json({ limit: '3mb' }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));

app.use(usageLogMiddleware);
app.get('/api/club-images/:id', asyncHandler(async (req, res) => {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(req.params.id)) {
    return res.status(404).json({ success: false, message: 'ไม่พบรูปคลับ' });
  }
  const image = await getImage(req.params.id);
  res.set('Content-Type', image.content_type);
  res.set('Cross-Origin-Resource-Policy', 'cross-origin');
  res.set('Cache-Control', 'public, max-age=31536000, immutable');
  return res.send(image.image_data);
}));

// Uploaded profile pictures; allow other origins (the app's web client) to embed them
app.use(
  '/uploads',
  (req, res, next) => {
    res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
    next();
  },
  express.static(path.join(__dirname, '..', 'uploads'))
);

app.use('/api', routes);

app.use(notFound);
app.use(errorHandler);

module.exports = app;
