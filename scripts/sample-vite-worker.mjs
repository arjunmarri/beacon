import http from 'node:http';

const port = Number(process.env.VITE_TARGET_PORT || 5173);
const startedAt = Date.now();

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        ok: true,
        pid: process.pid,
        uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
        memoryMb: Number((process.memoryUsage().rss / (1024 * 1024)).toFixed(1)),
      }),
    );
    return;
  }

  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end(`Beacon Local Vite Target Worker running on port ${port} (PID ${process.pid})\n`);
});

server.listen(port, '127.0.0.1', () => {
  console.log(`[vite-worker] Local dev server ready at http://127.0.0.1:${port} (PID ${process.pid})`);
});

process.on('SIGTERM', () => {
  console.log('[vite-worker] Received SIGTERM, shutting down cleanly');
  server.close(() => process.exit(0));
});
