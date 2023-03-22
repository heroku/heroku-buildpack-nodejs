#!/usr/bin/env node

const http = require('http');
const crypto = require('crypto');

const PORT = process.env.PORT || 5000;

// This will block the event loop for ~lengths of time
function blockCpuFor(ms) {
	var now = new Date().getTime();
	var result = 0
	while(true) {
		result += Math.random() * Math.random();
		if (new Date().getTime() > now +ms)
			return;
	}
}

// block the event loop for 100ms every second
setInterval(() => {
  blockCpuFor(100);
}, 1000)

// block the event loop for 1sec every 30 seconds
setInterval(() => {
  blockCpuFor(1000);
}, 30000)

// Allocate and erase memory on an interval
let store = [];

setInterval(() => {
  store.push(crypto.randomBytes(1000000).toString('hex'));
}, 500);

setInterval(() => {
  store = [];
}, 60000);

const server = http.createServer((_req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end("Hello, world!");
})

server.listen(PORT, () => console.log(`Listening on ${PORT}`));
