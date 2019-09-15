const http = require('http')
const request = require('request')

/**
 * Helper to parse command line arguments for the given flag (simple
 * key-value flags only).
 *
 * @param {String} short - Short version of the flag.
 * @param {String} long - Long version of the flag.
 *
 * @returns {String} The argument value or undefined if not present.
 */
function getArg(short, long) {
    const pos = process.argv.findIndex(v => v === short || v === long)
    if (pos === -1) return
    return process.argv[pos + 1]
}

const url = getArg('-u', '--url')
const duration = parseInt(getArg('-d', '--duration') || '10')
const connections = parseInt(getArg('-c', '--connections') || '1')

// Agent for the requests
let agent = null
let agentCreated = 0

console.log(`Making requests to ${url} for ${duration} seconds over ${connections} connections`)

// Stats for reporting
let finished = 0
let finishedSinceLastReport = 0
let lastReport = Date.now()
let inflight = 0

// Start making requests
const start = Date.now()
for (let i = 0; i < connections; i++) {
    makeRequest()
}

/**
 * Start a new request to the service under test.
 */
function makeRequest () {
    inflight += 1
    request.get(url, { agent: getAgent() }, callback)
}

/**
 * Get agent to use for a request. Returns new agent every 10 seconds to
 * re-establish connections to new backends that might have appeared since
 * the beginning.
 */
function getAgent() {
    if (Date.now() - agentCreated > 10000) {
        agent = new http.Agent({ maxSockets: connections, keepAlive: true })
        agentCreated = Date.now()
    }

    return agent
}

/**
 * Handler for the request finished callback. Updates stats and fires
 * a new request if there's still time left in the benchmark.
 *
 * @param {Error} err - Error if one occurred.
 */
function callback(err) {
    if (err) {
        return console.log(err)
    }

    requestFinished()

    const elapsed = Date.now() - start
    if (elapsed < duration * 1000) {
        // Still time left. Make new request
        makeRequest()
    } else if (inflight === 0) {
        // No time left and this was last one to finish. Exit
        maybeReport(true)
        const total = Math.round(elapsed / 1000 * 1000) / 1000
        console.log(`Finished in ${total} seconds. Exiting.`)
    }
}

/**
 * Update stats after a successful request.
 */
function requestFinished () {
    inflight -= 1
    finished += 1
    finishedSinceLastReport += 1
    maybeReport()
}

/**
 * Report request per sec stats once every second.
 *
 * @param {Boolean} [force] - Force reporting even if there's less than 1 second
 *  since previous report.
 */
function maybeReport(force) {
    const now = Date.now()
    if (!force && now - lastReport < 1000) return
    const overall = Math.round(finished / (now - start) * 1000 * 100) / 100
    const current = Math.round(finishedSinceLastReport / (now - lastReport) * 1000 * 100) / 100

    console.log(`STATS: current=${current} rps; Overall: ${overall} rps`)

    lastReport = Date.now()
    finishedSinceLastReport = 0
}
