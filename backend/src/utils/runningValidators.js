const Joi = require('joi');

const getSessionHistorySchema = Joi.object({
  sortBy: Joi.string().valid('date', 'month', 'year').default('date'),
  order: Joi.string().valid('asc', 'desc').default('desc'),
});

module.exports = { getSessionHistorySchema };
