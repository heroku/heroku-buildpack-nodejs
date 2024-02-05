/**
 * @typedef {{
 *     "node.gc.collections": number;
 *     "node.gc.pause.ns": number;
 *     "node.gc.old.collections": number;
 *     "node.gc.old.pause.ns": number;
 *     "node.gc.young.collections": number;
 *     "node.gc.young.pause.ns": number;
 * }} MemoryCounters
 *
 * @typedef {{
 *     "node.eventloop.usage.percent": number;
 *     "node.eventloop.delay.ms.median": number;
 *     "node.eventloop.delay.ms.p95": number;
 *     "node.eventloop.delay.ms.p99": number;
 *     "node.eventloop.delay.ms.max": number;
 * }} EventLoopGauges
 *
 * @typedef {{
 *     counters: MemoryCounters;
 *     gauges: EventLoopGauges;
 * }} MetricsPayload
 */
const { setInterval } = require('timers')
const { URL } = require('url');
const { debuglog } = require('util');
const { monitorEventLoopDelay, PerformanceObserver, constants, performance } = require('perf_hooks')
const { request: insecureRequest } = require('http');
const { request: secureRequest } = require('https');

try {
    // failures from the instrumentation shouldn't mess with the application
    registerInstrumentation()
} catch (e) {
    log(`An unexpected error occurred: ${e.stack}`)
}

/**
 * The main entry point of this instrumentation script. It sets up all
 * the memory and event loop tracking then sets a repeating timer to
 * collect the metrics and send them to a configured endpoint.
 */
function registerInstrumentation() {
    log('Registering metrics instrumentation')

    const herokuMetricsUrl = parseHerokuMetricsUrl()
    if (herokuMetricsUrl === undefined) {
        log('Metrics will not be collected for this application')
        return
    }

    const herokuMetricsInterval = parseHerokuMetricsInterval()

    let memoryCounters = initializeMemoryCounters()
    const gcObserver = new PerformanceObserver((value) => {
        value.getEntries().forEach(entry => updateMemoryCounters(memoryCounters, entry))
    })
    gcObserver.observe({ entryTypes: ['gc'] })

    const eventLoopHistogram = monitorEventLoopDelay()
    eventLoopHistogram.enable()

    let previousEventLoopUtilization = performance.eventLoopUtilization()

    const timeout  = setInterval(() => {
        try {
            const eventLoopUtilization = performance.eventLoopUtilization(previousEventLoopUtilization)
            eventLoopHistogram.disable()
            gcObserver.disconnect()

            sendMetrics(herokuMetricsUrl, {
                counters: {...memoryCounters},
                gauges: captureEventLoopGauges(eventLoopUtilization, eventLoopHistogram)
            })

            // reset memory and event loop measures
            previousEventLoopUtilization = eventLoopUtilization
            memoryCounters = initializeMemoryCounters()
            gcObserver.observe({ entryTypes: ['gc'] })
            eventLoopHistogram.reset()
            eventLoopHistogram.enable()
        } catch (e) {
            log(`An unexpected error occurred: ${e.stack}`)
        }
    }, herokuMetricsInterval)

    // `setInterval` actually returns a Timeout object but this isn't recognized by the type-checker which
    // thinks it's a number so adding this little guard to silence the type warnings
    if ('unref' in timeout) {
        timeout.unref()
    }
}

/**
 * Log a message to the Node debug log. These messages will be displayed if `NODE_DEBUG=heroku` is set in the environment.
 * @param {string} msg
 */
function log(msg) {
    debuglog('heroku')(`[heroku-metrics] ${msg}`)
}

/**
 * The url is where the runtime metrics will be posted to. This is parsed from the environment variable `HEROKU_METRICS_URL`
 * which is added to dynos by runtime only if the app has opted into the heroku runtime metrics beta. If this value is not
 * present, metrics collection must be disabled.
 * @returns {URL | undefined}
 */
function parseHerokuMetricsUrl() {
    const value = process.env.HEROKU_METRICS_URL
    if (value) {
        log(`HEROKU_METRICS_URL set to "${value}"`)
        try {
            return new URL(value)
        } catch (e) {
            log(`Invalid URL: ${e}`)
        }
    } else {
        log(`HEROKU_METRICS_URL was not set in the environment`)
    }
}

/**
 * Returns the time in milliseconds to wait between requests to send metrics to the collecting service. This value is
 * either parsed from the environment variable `METRICS_INTERVAL_OVERRIDE` or defaults to 20s. The parsed value also
 * can be no less than 10s.
 * @returns {number}
 */
function parseHerokuMetricsInterval() {
    const minimumInterval = 10 * 1000 // 10 seconds
    const defaultInterval = 20 * 1000 // 20 seconds

    const value = process.env.METRICS_INTERVAL_OVERRIDE
    if (value) {
        log(`METRICS_INTERVAL_OVERRIDE set to "${value}"`)
        const parsedValue = parseInt(value, 10)

        if (isNaN(parsedValue)) {
            log(`Invalid number, using the default interval of ${defaultInterval}ms instead`)
            return defaultInterval
        }

        if (parsedValue < minimumInterval) {
            log(`Interval is lower than the minimum, using the minimum interval of ${minimumInterval}ms instead`)
            return minimumInterval
        }

        log(`Using interval of ${parsedValue}ms`)
        return parsedValue
    }

    log(`Using default interval of ${defaultInterval}ms`)
    return defaultInterval
}

/**
 * Initializes all the memory counters with their starting values
 * @returns {MemoryCounters}
 */
function initializeMemoryCounters(){
    return {
        "node.gc.collections": 0,
        "node.gc.pause.ns": 0,
        "node.gc.old.collections": 0,
        "node.gc.old.pause.ns": 0,
        "node.gc.young.collections": 0,
        "node.gc.young.pause.ns": 0,
    }
}

/**
 * Increments the memory counters based on the values in the performance entry if the entry has NodeGCPerformanceDetail information.
 * @param {MemoryCounters} memoryCounters
 * @param {PerformanceEntry} performanceEntry
 */
function updateMemoryCounters(memoryCounters, performanceEntry) {
    const nsDuration = millisecondsToNanoseconds(performanceEntry.duration)
    memoryCounters['node.gc.collections'] += 1
    memoryCounters['node.gc.pause.ns'] += nsDuration
    if (getGcPerformanceEntryKind(performanceEntry) === constants.NODE_PERFORMANCE_GC_MINOR) {
        memoryCounters['node.gc.young.collections'] += 1
        memoryCounters['node.gc.young.pause.ns'] += nsDuration
    } else {
        memoryCounters['node.gc.old.collections'] += 1
        memoryCounters['node.gc.old.pause.ns'] += nsDuration
    }
}

/**
 * Reads the `kind` field for the 'gc' performance entry in a backwards-compatible way
 * @param {PerformanceEntry} performanceEntry
 * @returns {number}
 */
function getGcPerformanceEntryKind(performanceEntry) {
    // using try/catch to avoid triggering deprecation warnings
    try {
        // for v16 and up
        return performanceEntry.detail.kind
    } catch (e) {
        // fallback for v14 & v15
        return performanceEntry.kind
    }
}

/**
 * Collects details about the event loop metrics using perf_hooks functionality.
 * @param {EventLoopUtilization} eventLoopUtilization
 * @param {IntervalHistogram} eventLoopHistogram
 * @returns {EventLoopGauges}
 */
function captureEventLoopGauges(eventLoopUtilization, eventLoopHistogram) {
    return  {
        'node.eventloop.usage.percent': eventLoopUtilization.utilization,
        'node.eventloop.delay.ms.median': nanosecondsToMilliseconds(eventLoopHistogram.percentile(50)),
        'node.eventloop.delay.ms.p95': nanosecondsToMilliseconds(eventLoopHistogram.percentile(95)),
        'node.eventloop.delay.ms.p99': nanosecondsToMilliseconds(eventLoopHistogram.percentile(99)),
        'node.eventloop.delay.ms.max': nanosecondsToMilliseconds(eventLoopHistogram.max),
    }
}

/**
 * Converts the given value in milliseconds into nanoseconds
 * @param {number} ms A millisecond value
 * @return {number}
 */
function millisecondsToNanoseconds(ms) {
    return ms * 1e6 // 1_000_000
}

/**
 * Converts the given value in nanoseconds into seconds
 * @param {number} ns A nanosecond value
 * @return {number}
 */
function nanosecondsToMilliseconds(ns) {
    return ns / 1e6 // 1_000_000
}

/**
 * Sends the collected metrics to the given endpoint using a POST request.
 * @param {URL} url
 * @param {MetricsPayload} payload
 * @returns void
 */
function sendMetrics(url, payload) {
    const request = url.protocol === 'https:' ? secureRequest : insecureRequest
    const payloadAsJson = JSON.stringify(payload)

    log(`Sending metrics to ${url.toString()}`)
    const clientRequest = request({
        method: 'POST',
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port,
        path: url.pathname,
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(payloadAsJson)
        }
    })

    clientRequest.on('response', (res) => {
        if (res.statusCode === 200) {
            log('Metrics sent successfully')
        } else {
            log(`Tried to send metrics but response was: ${res.statusCode} - ${res.statusMessage}`)
        }
        // consume response data to free up memory
        // see: https://nodejs.org/docs/latest/api/http.html#http_class_http_clientrequest
        res.resume()
    })

    clientRequest.on('error', (err) => {
        log(`An error occurred while sending metrics - ${err}`)
    })

    clientRequest.write(payloadAsJson)
    clientRequest.end()
}
