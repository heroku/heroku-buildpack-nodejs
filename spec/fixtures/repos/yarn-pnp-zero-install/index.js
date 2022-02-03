const express = require("express");
const app = express();
const port = process.env["PORT"] || 3000;

app.get("/", (_req,res) => {
  res.send("Hello from yarn-pnp-zero-install");
});

app.listen(port, () => {
  console.log(`yarn-pnp-zero-install listening on ${port}`);
});
