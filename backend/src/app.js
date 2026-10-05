const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const env = require('./config/env');
const routes = require('./routes');
const { notFound, errorHandler } = require('./middleware/errorHandler');
const usageLogMiddleware = require('./middleware/usageLog');
const { imageDirectory } = require('./services/clubImageService');

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
app.use('/api/club-images', express.static(imageDirectory, {
  dotfiles: 'deny',
  index: false,
  maxAge: '1y',
  immutable: true,
  setHeaders: (res) => res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin'),
}));

app.use('/api', routes);

app.use(notFound);
app.use(errorHandler);

module.exports = app;
