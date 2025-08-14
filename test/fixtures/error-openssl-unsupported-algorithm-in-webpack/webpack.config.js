const { createHash } = require('node:crypto')

module.exports = {
    entry: './index.js',
    output: {
        hashFunction: createHash('md4')
    },
};
