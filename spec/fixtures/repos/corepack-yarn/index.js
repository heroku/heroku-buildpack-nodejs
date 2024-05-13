const express = require('express')

const app = express()
const port = process.env.PORT || 3000

app.get('/', (req, res) => {
    res.send('Hello from corepack-yarn')
})

app.listen(port, () => {
    console.log(`corepack-yarn app listening on port ${port}`)
})
