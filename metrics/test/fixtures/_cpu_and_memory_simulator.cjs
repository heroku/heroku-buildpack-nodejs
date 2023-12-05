const crypto = require('crypto');

// This will block the event loop for ~lengths of time
function blockCpuFor(ms) {
    const now = new Date().getTime();
    let result = 0
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
