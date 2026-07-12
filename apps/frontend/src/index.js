const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.static(path.join(__dirname, 'public')));

app.get('/healthz', (req, res) => res.status(200).json({ status: 'ok', service: 'frontend' }));
app.get('/readyz', (req, res) => res.status(200).json({ status: 'ready' }));

app.listen(PORT, () => console.log(`frontend listening on port ${PORT}`));
