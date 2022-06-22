const express = require("express");
const crypto = require('crypto')

const app = express();
const port = process.env["PORT"] || 3000;
const { privateKey } = crypto.generateKeyPairSync('rsa', {modulusLength: 2048})

app.get("/", (_req,res) => {
    const sign = crypto.createSign('RSA-SHA256')
    sign.update(Buffer.from("hello"))
    sign.sign(privateKey.export({type: 'pkcs1', format: 'pem'}))
    res.send("Hello from openssl-v3-on-stack-22");
});

app.listen(port, () => {
    console.log(`openssl-v3-on-stack-22 listening on ${port}`);
});
