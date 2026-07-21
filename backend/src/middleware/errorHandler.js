const ApiError = require('../utils/ApiError');

// 404 handler
function notFound(req, res, next) {
  next(new ApiError(404, `Route not found: ${req.method} ${req.originalUrl}`));
}

// Central error handler - keep response shape consistent for the frontend
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  const statusCode = err instanceof ApiError ? err.statusCode : err.statusCode || 500;
  const message = err.message || 'Internal server error';

  if (statusCode >= 500) {
    // eslint-disable-next-line no-console
    console.error('[error]', err);
  }

  res.status(statusCode).json({
    success: false,
    message,
    details: err.details,
  });
}

module.exports = { notFound, errorHandler };
