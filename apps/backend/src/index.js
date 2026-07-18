const express = require('express');
const redis = require('redis');
const amqp = require('amqplib');
const fetch = require('node-fetch');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 4000;
const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL; // e.g. http://auth-service:4001
const REDIS_URL = process.env.REDIS_URL;                // e.g. redis://redis:6379
const RABBITMQ_URL = process.env.RABBITMQ_URL;           // e.g. amqp://rabbitmq:5672

let redisClient;
let amqpChannel;

app.get('/healthz', (req, res) => res.status(200).json({ status: 'ok', service: 'backend' }));

app.get('/readyz', async (req, res) => {
  const checks = { redis: false, rabbitmq: false };
  try {
    checks.redis = redisClient?.isReady ?? false;
    checks.rabbitmq = !!amqpChannel;
    const allReady = Object.values(checks).every(Boolean);
    res.status(allReady ? 200 : 503).json({ status: allReady ? 'ready' : 'not ready', checks });
  } catch (err) {
    res.status(503).json({ status: 'not ready', error: err.message });
  }
});

// Core business flow:
// 1. Exchange username for a token via auth-service (inter-service HTTP call
//    over the internal network — this is exactly what a K8s ClusterIP Service
//    DNS name will replace AUTH_SERVICE_URL with in Step 3).
// 2. Cache the token in Redis so repeated requests for the same user are fast.
// 3. Publish a "user_logged_in" event to RabbitMQ for notification-service
//    to consume asynchronously — decoupling backend from notification latency.
app.post('/login', async (req, res) => {
  const { username } = req.body;
  if (!username) return res.status(400).json({ error: 'username is required' });

  const cacheKey = `token:${username}`;

  try {
    const cached = await redisClient.get(cacheKey);
    if (cached) {
      return res.json({ token: cached, cached: true });
    }

    const authRes = await fetch(`${AUTH_SERVICE_URL}/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username }),
    });

    if (!authRes.ok) {
      const errBody = await authRes.text();
      return res.status(502).json({ error: 'auth-service error', details: errBody });
    }

    const { token } = await authRes.json();

    // Cache for 5 minutes — deliberately short, this is a demo cache, not a
    // session store. Prevents unbounded memory growth in Redis.
    await redisClient.setEx(cacheKey, 300, token);

    if (!amqpChannel) {
      return res.status(503).json({ error: 'messaging temporarily unavailable, please retry' });
    }

    await amqpChannel.sendToQueue(
      'notifications',
      Buffer.from(JSON.stringify({ event: 'user_logged_in', username, ts: Date.now() })),
      { persistent: true }
    );

    res.json({ token, cached: false });
  } catch (err) {
    console.error('Error in /login:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// Retry-with-backoff connection helpers. This matters a LOT: in Compose and
// especially in Kubernetes, there is NO guarantee that dependent services
// (redis, rabbitmq) are ready the instant this container starts. Without
// retry logic, backend would crash on startup any time it starts even
// slightly before its dependencies — a very common source of CrashLoopBackOff
// once we're in Kubernetes (Step 4+).
async function connectRedisWithRetry(retries = 10, delayMs = 3000) {
  for (let i = 1; i <= retries; i++) {
    try {
      redisClient = redis.createClient({ url: REDIS_URL });
      redisClient.on('error', (err) => console.error('Redis Client Error', err));
      await redisClient.connect();
      console.log('Connected to Redis');
      return;
    } catch (err) {
      console.warn(`Redis connection attempt ${i}/${retries} failed: ${err.message}`);
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
  throw new Error('Could not connect to Redis after retries');
}

async function connectRabbitWithRetry(retries = 30, delayMs = 5000) {
  for (let i = 1; i <= retries; i++) {
    try {
      const conn = await amqp.connect(RABBITMQ_URL);
      amqpChannel = await conn.createChannel();
      await amqpChannel.assertQueue('notifications', { durable: true });

      // If the channel/connection drops later (RabbitMQ restart, network
      // blip, probe-induced instability), don't just leave amqpChannel
      // pointing at a dead object — null it out and reconnect FOREVER,
      // not just for a fixed budget. A RabbitMQ restart mid-lifetime can
      // take just as long as the initial boot, and giving up permanently
      // here would leave backend stuck "not ready" until manually restarted.
      conn.on('close', () => {
        console.warn('RabbitMQ connection closed, reconnecting...');
        amqpChannel = null;
        reconnectForever();
      });

      console.log('Connected to RabbitMQ');
      return;
    } catch (err) {
      console.warn(`RabbitMQ connection attempt ${i}/${retries} failed: ${err.message}`);
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
  throw new Error('Could not connect to RabbitMQ after retries');
}

async function reconnectForever() {
  while (!amqpChannel) {
    try {
      await connectRabbitWithRetry(1, 5000);
    } catch (err) {
      console.warn('Reconnect attempt failed, will keep trying:', err.message);
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
}

(async () => {
  try {
    await connectRedisWithRetry();
    await connectRabbitWithRetry();
    app.listen(PORT, () => console.log(`backend listening on port ${PORT}`));
  } catch (err) {
    console.error('Fatal startup error:', err.message);
    process.exit(1);
  }
})();
