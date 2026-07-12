const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 4001;

// Connection pool to PostgreSQL — configured entirely from environment
// variables so the exact same image works in Compose, Kind, or any cloud
// cluster without code changes. This is the "12-Factor App" config principle.
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
});

pool.on('error', (err) => {
  // This fires for background/idle client errors (e.g., Postgres becoming
  // unreachable). Without this handler, Node treats it as an uncaught
  // exception and crashes the whole process — turning a transient
  // dependency outage into a full service crash-loop, exactly the
  // anti-pattern this chapter's demo is meant to expose.
  console.error('Unexpected PG pool error (handled, not crashing):', err.message);
});

// Liveness probe target (Step 9): must respond even if dependencies are down.
// A liveness check that pings the database would cause Kubernetes to kill
// and restart the pod during a transient DB blip — a very common anti-pattern.
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'auth-service' });
});

// Readiness probe target (Step 9): SHOULD check the DB, because "ready"
// means "able to actually serve traffic correctly," not just "process alive."
app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ready' });
  } catch (err) {
    res.status(503).json({ status: 'not ready', error: err.message });
  }
});

// Ensures the users table exists. In a real system this would be a proper
// migration tool (Flyway, Prisma Migrate, node-pg-migrate) — we do it inline
// here deliberately to keep the app minimal; the migration-tooling gap is
// something worth mentioning as a known simplification if asked.
async function initDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now()
    );
  `);
}

// Minimal "auth": issues a fake token tied to a username, creating the user
// row if it doesn't exist. Deliberately not real JWT/crypto — the point of
// this project is Kubernetes, not building a security-hardened auth system.
app.post('/token', async (req, res) => {
  const { username } = req.body;
  if (!username) {
    return res.status(400).json({ error: 'username is required' });
  }
  try {
    await pool.query(
      'INSERT INTO users (username) VALUES ($1) ON CONFLICT (username) DO NOTHING',
      [username]
    );
    const token = Buffer.from(`${username}:${Date.now()}`).toString('base64');
    res.json({ token });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

initDb()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`auth-service listening on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error('Failed to initialize database:', err.message);
    process.exit(1);
  });
