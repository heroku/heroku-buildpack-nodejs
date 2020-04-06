#!/usr/bin/env node

const http = require('http');
const exec = require('child_process').exec;
const PORT = process.env.PORT || 5000;

const server = http.createServer((req, res) => {
  /*
    Note: we cannot use `heroku run` to test this since the metrics plugin is
          disabled on run dynos
  */
  exec('heroku whoami', (error, stdout, stderr) => {
    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/plain');
    res.end(stderr);
  });
})

server.listen(PORT, () => console.log(`Listening on ${PORT}`));
