#!/usr/bin/env node
require('./_cpu_and_memory_simulator.cjs')

console.log(`- starting single process ${process.pid} with NODE_OPTIONS="${process.env.NODE_OPTIONS || ''}"`)
process.on('SIGINT', () => {
    process.exit(0)
})
