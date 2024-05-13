const express = require("express");

const port = process.env['PORT'] || 8080;
const app = express();

app.get("/", (_req, res) => {
    res.send("Hello from pnpm-unknown-version");
});

app.listen(port, () => {
    console.log(`pnpm-unknown-version running on ${port}.`);
});
