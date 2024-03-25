const fastify = require('fastify')();
const port = process.env['PORT'] || 8080;

fastify.get('/', (_request, reply) => {
  reply.send("Hello from pnpm-7-pnp");
});

fastify.listen({ host: "0.0.0.0", port }, (err, address) => {
  if (err) throw err
  console.log(`pnpm-7-pnp running on ${address}.`)
})
