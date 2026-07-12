const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
});

// Deletes users older than N days — a stand-in for real session/token
// garbage collection. RETURNING lets us log exactly what was deleted,
// which matters enormously for auditability of a destructive scheduled task.
const RETENTION_DAYS = parseInt(process.env.RETENTION_DAYS || '30', 10);

async function cleanup() {
  console.log(`[cleanup] Starting stale-user cleanup (retention: ${RETENTION_DAYS} days)`);

  try {
    const result = await pool.query(
      `DELETE FROM users
       WHERE created_at < now() - ($1 || ' days')::interval
       RETURNING username;`,
      [RETENTION_DAYS]
    );
    console.log(`[cleanup] Deleted ${result.rowCount} stale user(s): ${result.rows.map(r => r.username).join(', ') || 'none'}`);
    await pool.end();
    process.exit(0);
  } catch (err) {
    console.error('[cleanup] Failed:', err.message);
    await pool.end();
    process.exit(1);
  }
}

cleanup();
