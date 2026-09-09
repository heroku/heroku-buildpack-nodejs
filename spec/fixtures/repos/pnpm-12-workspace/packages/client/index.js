const _ = require('lodash');

const data = _.map([1, 2, 3], n => n * 2);
console.log('Client data:', data);

module.exports = { data };
