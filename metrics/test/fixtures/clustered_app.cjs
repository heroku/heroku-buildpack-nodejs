const { isPrimary, fork } = require('node:cluster')

require('./_cpu_and_memory_simulator.cjs')

if (isPrimary) {
    console.log(`Starting primary cluster ${process.pid} running with NODE_OPTIONS="${process.env.NODE_OPTIONS || ''}"`)
    fork()
    process.on('SIGINT', () => {
        process.exit(0)
    })
} else {
    console.log(`Starting clustered worker with NODE_OPTIONS="${process.env.NODE_OPTIONS || ''}"`)
    setInterval(() => {
        console.log(`  clustered worker is working...`)
    }, 5000)
}
