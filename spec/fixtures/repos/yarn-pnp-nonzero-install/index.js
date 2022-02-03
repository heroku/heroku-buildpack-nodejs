const express = require("express");
const app = express();
const port = process.env["PORT"] || 3000;

app.get("/", (_req,res) => {
  res.send("Hello from yarn-pnp-nonzero-install");
});

app.listen(port, () => {
  console.log(`yarn-pnp-nonzero-install listening on ${port}`);
});
