const express = require('express')
const morgan = require('morgan')
const app = express()
const port = 8080

const crypto = require('crypto')
const os = require('os')

const me = os.hostname()

app.use(morgan('common'))

app.get('/', (req, res) => res.json({msg: 'Hello World!', from: me}))
app.get('/hash', (req, res) => {
    const start = process.hrtime()
    let hash = req.query.value
    let rounds = parseInt(req.query.rounds || '50000')
    for (var round = 0; round < rounds; round++) {
        const h = crypto.createHash('sha256')
        hash = h.update(hash).digest('hex')
    }

    const end = process.hrtime(start)
    res.json({ hash, duration_ms: end[0] * 1000 + end[1] / 1000000, from: me })
})
app.get('/another', (req, res) => {
    process.exit(1)
})

app.listen(port, () => console.log(`Example app listening on port ${port}!`))

function handle(s) {
    console.log(`Received signal ${s}; shutting down`)
    return process.exit(0)
}

process.on('SIGINT', handle);
process.on('SIGTERM', handle);
