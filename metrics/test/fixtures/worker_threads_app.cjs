const { Worker, isMainThread} = require('node:worker_threads')

require('./_cpu_and_memory_simulator.cjs')

if (isMainThread) {
    console.log(`Starting main process ${process.pid} running with NODE_OPTIONS="${process.env.NODE_OPTIONS || ''}"`)
    const worker = new Worker(__filename)
    worker.on('exit', () => {
        console.log(`Worker thread exited`)
    })
    process.on('SIGINT', () => {
        process.exit(0)
    })
} else {
    console.log(`Starting worker thread ${process.pid} with NODE_OPTIONS="${process.env.NODE_OPTIONS || ''}"`)
    setInterval(() => {
        console.log(`  worker thread is working...`)
    }, 5000)
}
