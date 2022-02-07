const express = require("express");
const app = express();
const port = process.env["PORT"] || 3000;

app.get("/", (_req,res) => {
  res.send("Hello from yarn2-modules-zero-install");
});

app.listen(port, () => {
  console.log(`yarn2-modules-zero-install listening on ${port}`);
});
