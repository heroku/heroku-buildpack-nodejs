const express = require("express");

const port = process.env['PORT'] || 8080;
const app = express();

app.get("/", (_req, res) => {
    res.send("Hello from pnpm-8-hoist");
});

app.listen(port, () => {
    console.log(`pnpm-8-hoist running on ${port}.`);
});
