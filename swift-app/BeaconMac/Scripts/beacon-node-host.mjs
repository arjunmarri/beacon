#!/usr/bin/env node
// BeaconMac Built-In Zero-Dependency Node.js Multi-App Host
// Binds strictly to 127.0.0.1 (loopback only) and serves any loaded static/built web app
// (HTML, Vite dist, React build, Next export) or proxies a local loopback app port.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";

function parseArgs(argv) {
  const out = { port: 4173, registry: "", pidfile: "" };
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--port" && argv[i + 1]) {
      const parsed = Number.parseInt(argv[++i], 10);
      if (Number.isInteger(parsed) && parsed >= 1024 && parsed <= 65535) {
        out.port = parsed;
      }
    } else if (arg === "--registry" && argv[i + 1]) {
      out.registry = argv[++i];
    } else if (arg === "--pidfile" && argv[i + 1]) {
      out.pidfile = argv[++i];
    }
  }
  return out;
}

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".htm": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".cjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".wasm": "application/wasm",
  ".txt": "text/plain; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".pdf": "application/pdf",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
  ".mp3": "audio/mpeg",
};

function escapeHtml(raw) {
  return String(raw ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function detectServeRoot(folderPath) {
  if (!folderPath || typeof folderPath !== "string") return null;
  const resolved = path.resolve(folderPath);
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) return null;

  for (const candidate of ["dist", "build", "out", "public"]) {
    const subDir = path.join(resolved, candidate);
    if (fs.existsSync(path.join(subDir, "index.html"))) {
      return { rootDir: subDir, detectedSubdir: candidate };
    }
  }
  return { rootDir: resolved, detectedSubdir: "" };
}

const config = parseArgs(process.argv);
const startedAt = Date.now();

let cachedMtimeMs = -1;
let cachedRegistry = { activeRootSlug: null, apps: [] };

function loadRegistry() {
  if (!config.registry) return cachedRegistry;
  try {
    const stat = fs.statSync(config.registry);
    if (stat.mtimeMs !== cachedMtimeMs) {
      const raw = JSON.parse(fs.readFileSync(config.registry, "utf8"));
      const apps = Array.isArray(raw.apps)
        ? raw.apps
            .filter((a) => a && typeof a.slug === "string" && /^[a-z0-9][a-z0-9-]*$/.test(a.slug))
            .map((a) => ({
              id: String(a.id || a.slug),
              name: String(a.name || a.slug),
              slug: String(a.slug),
              mode: a.mode === "proxy" ? "proxy" : "static",
              folderPath: typeof a.folderPath === "string" ? a.folderPath : "",
              proxyPort:
                Number.isInteger(a.proxyPort) && a.proxyPort >= 1 && a.proxyPort <= 65535
                  ? a.proxyPort
                  : null,
              spaFallback: a.spaFallback !== false,
            }))
        : [];
      const activeRootSlug =
        typeof raw.activeRootSlug === "string" && apps.some((a) => a.slug === raw.activeRootSlug)
          ? raw.activeRootSlug
          : null;
      cachedRegistry = { activeRootSlug, apps };
      cachedMtimeMs = stat.mtimeMs;
    }
  } catch {
    // Keep last known good registry if file is temporarily missing or mid-write
  }
  return cachedRegistry;
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(body);
}

function renderDashboardHtml(registry) {
  const activeSlug = registry.activeRootSlug || (registry.apps.length === 1 ? registry.apps[0].slug : null);
  const cards = registry.apps.length
    ? registry.apps
        .map((app) => {
          const isRoot = app.slug === activeSlug;
          const info =
            app.mode === "proxy"
              ? `Proxy → 127.0.0.1:${escapeHtml(app.proxyPort ?? "—")}`
              : (() => {
                  const detected = detectServeRoot(app.folderPath);
                  if (!detected) return "Folder not found";
                  return detected.detectedSubdir
                    ? `${escapeHtml(path.basename(app.folderPath))}/${escapeHtml(detected.detectedSubdir)}`
                    : escapeHtml(path.basename(app.folderPath));
                })();
          const href = isRoot ? "/" : `/apps/${encodeURIComponent(app.slug)}/`;
          return `
            <div class="card">
              <div class="row">
                <div>
                  <div class="title">${escapeHtml(app.name)} ${isRoot ? '<span class="tag">ACTIVE ROOT /</span>' : ""}</div>
                  <div class="meta">${escapeHtml(app.mode.toUpperCase())} · ${info} · /apps/${escapeHtml(app.slug)}/</div>
                </div>
                <a class="btn" href="${href}">Open App →</a>
              </div>
            </div>`;
        })
        .join("\n")
    : `<div class="empty">No apps loaded yet. Click <strong>Load App Folder</strong> inside BeaconMac to mount any HTML, Vite, React, or local app directly into this built-in Node.js server.</div>`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>BeaconMac Built-In Node.js Server</title>
  <style>
    :root { color-scheme: dark; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; background: #0b0e14; color: #e6edf3; }
    .wrap { max-width: 780px; margin: 48px auto; padding: 0 24px; }
    h1 { font-size: 22px; margin: 0 0 6px; letter-spacing: -0.02em; }
    .sub { color: #8b949e; font-size: 13px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; margin-bottom: 24px; }
    .card { background: #131820; border: 1px solid rgba(255,255,255,0.08); border-radius: 10px; padding: 16px 18px; margin-bottom: 12px; }
    .row { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
    .title { font-size: 15px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
    .meta { font-size: 12px; color: #8b949e; margin-top: 4px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .tag { font-size: 10px; font-weight: 700; color: #34d399; background: rgba(52,211,153,0.12); border: 1px solid rgba(52,211,153,0.3); padding: 2px 7px; border-radius: 6px; }
    .btn { text-decoration: none; color: #fff; background: #2563eb; padding: 8px 14px; border-radius: 7px; font-size: 12.5px; font-weight: 600; white-space: nowrap; }
    .btn:hover { background: #1d4ed8; }
    .empty { background: #131820; border: 1px dashed rgba(255,255,255,0.14); border-radius: 10px; padding: 24px; color: #9ca3af; font-size: 13.5px; line-height: 1.5; }
    .foot { margin-top: 28px; color: #6b7280; font-size: 11.5px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>BeaconMac Built-In Node.js Server</h1>
    <div class="sub">127.0.0.1:${config.port} · Node ${escapeHtml(process.version)} · ${registry.apps.length} loaded app(s)</div>
    ${cards}
    <div class="foot">Loopback-only local host · Health: /_beacon/health · Apps JSON: /_beacon/apps</div>
  </div>
</body>
</html>`;
}

function isBlockedDotPath(relPath) {
  const segments = relPath.split("/");
  return segments.some((seg) => seg.startsWith(".") && seg !== ".well-known");
}

function serveStaticApp(app, relPathname, req, res) {
  const detected = detectServeRoot(app.folderPath);
  if (!detected) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    res.end(`App folder not found for "${app.name}".`);
    return;
  }

  let rootReal;
  try {
    rootReal = fs.realpathSync(detected.rootDir);
  } catch {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    res.end(`Unable to access app directory for "${app.name}".`);
    return;
  }

  let decoded;
  try {
    decoded = decodeURIComponent(relPathname || "/");
  } catch {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad Request");
    return;
  }

  if (decoded.includes("\0")) {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad Request");
    return;
  }

  const normalizedRel = decoded.replace(/^\/+/, "");
  if (isBlockedDotPath(normalizedRel)) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Forbidden");
    return;
  }

  const candidate = path.resolve(rootReal, normalizedRel);
  if (candidate !== rootReal && !candidate.startsWith(rootReal + path.sep)) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Forbidden");
    return;
  }

  let fileToServe = candidate;
  try {
    const stat = fs.statSync(fileToServe);
    if (stat.isDirectory()) {
      fileToServe = path.join(fileToServe, "index.html");
    }
  } catch {
    // Will try SPA fallback below
  }

  let existsAndFile = false;
  try {
    existsAndFile = fs.statSync(fileToServe).isFile();
  } catch {
    existsAndFile = false;
  }

  if (!existsAndFile && app.spaFallback) {
    const indexFallback = path.join(rootReal, "index.html");
    if (fs.existsSync(indexFallback) && fs.statSync(indexFallback).isFile()) {
      fileToServe = indexFallback;
      existsAndFile = true;
    }
  }

  if (!existsAndFile) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    res.end(`Not Found: /${normalizedRel}`);
    return;
  }

  let realTarget;
  try {
    realTarget = fs.realpathSync(fileToServe);
  } catch {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not Found");
    return;
  }

  if (realTarget !== rootReal && !realTarget.startsWith(rootReal + path.sep)) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Forbidden");
    return;
  }

  const ext = path.extname(realTarget).toLowerCase();
  const contentType = MIME_TYPES[ext] || "application/octet-stream";
  const stat = fs.statSync(realTarget);

  res.writeHead(200, {
    "Content-Type": contentType,
    "Content-Length": stat.size,
    "Cache-Control": ext === ".html" ? "no-cache" : "public, max-age=60",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  });

  if (req.method === "HEAD") {
    res.end();
    return;
  }

  const stream = fs.createReadStream(realTarget);
  stream.on("error", () => {
    if (!res.headersSent) {
      res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
    }
    res.end("Internal Server Error");
  });
  stream.pipe(res);
}

function proxyLocalApp(app, relPathWithQuery, req, res) {
  if (!app.proxyPort) {
    res.writeHead(502, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(`App "${app.name}" has no valid local proxy port configured.`);
    return;
  }

  const headers = { ...req.headers, host: `127.0.0.1:${app.proxyPort}` };
  delete headers["connection"];

  const proxyReq = http.request(
    {
      hostname: "127.0.0.1",
      port: app.proxyPort,
      method: req.method,
      path: relPathWithQuery.startsWith("/") ? relPathWithQuery : `/${relPathWithQuery}`,
      headers,
      timeout: 15000,
    },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode || 502, proxyRes.headers);
      proxyRes.pipe(res);
    }
  );

  proxyReq.on("error", (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    }
    res.end(`BeaconMac Proxy: 127.0.0.1:${app.proxyPort} is unreachable (${err.code || err.message}).`);
  });

  proxyReq.on("timeout", () => {
    proxyReq.destroy();
    if (!res.headersSent) {
      res.writeHead(504, { "Content-Type": "text/plain; charset=utf-8" });
    }
    res.end(`BeaconMac Proxy: 127.0.0.1:${app.proxyPort} timed out.`);
  });

  req.pipe(proxyReq);
}

function dispatchToApp(app, relPathname, search, req, res) {
  if (app.mode === "proxy") {
    proxyLocalApp(app, `${relPathname}${search}`, req, res);
  } else {
    serveStaticApp(app, relPathname, req, res);
  }
}

const server = http.createServer((req, res) => {
  const registry = loadRegistry();
  const rawUrlPath = (req.url || "/").split("?")[0];
  let rawDecoded = rawUrlPath;
  try {
    rawDecoded = decodeURIComponent(rawUrlPath);
  } catch {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad Request");
    return;
  }
  if (rawDecoded.includes("\0") || rawDecoded.split(/[\\/]/).includes("..")) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8", "X-Content-Type-Options": "nosniff" });
    res.end("Forbidden");
    return;
  }

  let parsedUrl;
  try {
    parsedUrl = new URL(req.url || "/", `http://127.0.0.1:${config.port}`);
  } catch {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad Request");
    return;
  }

  const pathname = parsedUrl.pathname;
  const search = parsedUrl.search || "";

  if (pathname === "/_beacon/health") {
    sendJson(res, 200, {
      ok: true,
      pid: process.pid,
      port: config.port,
      nodeVersion: process.version,
      activeRootSlug: registry.activeRootSlug,
      appCount: registry.apps.length,
      uptimeSec: Math.floor((Date.now() - startedAt) / 1000),
    });
    return;
  }

  if (pathname === "/_beacon/apps") {
    sendJson(res, 200, {
      port: config.port,
      activeRootSlug: registry.activeRootSlug,
      apps: registry.apps.map((a) => ({
        id: a.id,
        name: a.name,
        slug: a.slug,
        mode: a.mode,
        mountPath: `/apps/${a.slug}/`,
        proxyPort: a.proxyPort,
      })),
    });
    return;
  }

  if (pathname === "/_beacon" || pathname === "/_beacon/") {
    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    });
    res.end(renderDashboardHtml(registry));
    return;
  }

  // Explicit app mount: /apps/<slug>/...
  const mountMatch = pathname.match(/^\/apps\/([a-z0-9][a-z0-9-]*)(\/.*)?$/);
  if (mountMatch) {
    const slug = mountMatch[1];
    const rest = mountMatch[2];
    const targetApp = registry.apps.find((a) => a.slug === slug);
    if (!targetApp) {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end(`App "${slug}" is not currently loaded in BeaconMac's built-in Node.js server.`);
      return;
    }
    if (!rest) {
      res.writeHead(302, { Location: `/apps/${slug}/${search}` });
      res.end();
      return;
    }
    dispatchToApp(targetApp, rest, search, req, res);
    return;
  }

  // Root routing: serve active root app (or single loaded app) directly at /
  const rootApp =
    (registry.activeRootSlug && registry.apps.find((a) => a.slug === registry.activeRootSlug)) ||
    (registry.apps.length === 1 ? registry.apps[0] : null);

  if (rootApp) {
    dispatchToApp(rootApp, pathname, search, req, res);
    return;
  }

  res.writeHead(200, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(renderDashboardHtml(registry));
});

server.listen(config.port, "127.0.0.1", () => {
  if (config.pidfile) {
    try {
      fs.mkdirSync(path.dirname(config.pidfile), { recursive: true });
      fs.writeFileSync(config.pidfile, String(process.pid), "utf8");
    } catch {}
  }
  console.log(`[beacon-node-host] Listening on http://127.0.0.1:${config.port} (PID ${process.pid}, Node ${process.version})`);
});

function shutdown() {
  if (config.pidfile) {
    try {
      fs.unlinkSync(config.pidfile);
    } catch {}
  }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 500).unref();
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
