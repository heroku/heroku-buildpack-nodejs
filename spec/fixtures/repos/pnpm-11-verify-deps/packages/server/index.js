const express = require('express');
const { label } = require('@acme/client');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send(`Hello from ${label}`);
});

app.listen(port, () => {
  console.log(`Server listening on port ${port}`);
});
