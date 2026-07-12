const express = require('express');
const amqp = require('amqplib');

const app = express();
const PORT = process.env.PORT || 4002;
const RABBITMQ_URL = process.env.RABBITMQ_URL;

let isConsuming = false;

app.get('/healthz', (req, res) => res.status(200).json({ status: 'ok', service: 'notification-service' }));
app.get('/readyz', (req, res) => {
  res.status(isConsuming ? 200 : 503).json({ status: isConsuming ? 'ready' : 'not ready' });
});

async function consumeWithRetry(retries = 10, delayMs = 3000) {
  for (let i = 1; i <= retries; i++) {
    try {
      const conn = await amqp.connect(RABBITMQ_URL);
      const channel = await conn.createChannel();
      await channel.assertQueue('notifications', { durable: true });

      // prefetch(1): process one message at a time before acknowledging.
      // This is a deliberate backpressure choice — prevents this single
      // replica from pulling the entire queue into memory at once. When we
      // scale this service to multiple replicas (Step 11, HPA), each replica
      // will fairly compete for messages instead of one replica hoarding them.
      channel.prefetch(1);

      console.log('notification-service: connected, waiting for messages');
      isConsuming = true;

      channel.consume('notifications', (msg) => {
        if (msg !== null) {
          const payload = JSON.parse(msg.content.toString());
          console.log(`[notification] event=${payload.event} user=${payload.username}`);
          channel.ack(msg);
        }
      });
      return;
    } catch (err) {
      console.warn(`RabbitMQ connection attempt ${i}/${retries} failed: ${err.message}`);
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
  throw new Error('Could not connect to RabbitMQ after retries');
}

app.listen(PORT, () => console.log(`notification-service HTTP (health) listening on port ${PORT}`));
consumeWithRetry().catch((err) => {
  console.error('Fatal startup error:', err.message);
  process.exit(1);
});
