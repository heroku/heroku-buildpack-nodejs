const crypto = require('crypto')

const { privateKey } = crypto.generateKeyPairSync('rsa', {modulusLength: 2048})
const sign = crypto.createSign('RSA-SHA256')
sign.update(Buffer.from("hello"))
sign.sign(privateKey.export({type: 'pkcs1', format: 'pem'}))