const { app, BrowserWindow, Tray, Menu, nativeImage, dialog } = require('electron');
const http = require('node:http');
const net = require('node:net');
const path = require('node:path');
const { spawn } = require('node:child_process');

let mainWindow = null;
let tray = null;
let serverProcess = null;
let activePort = 3000;
let serverStderr = '';

function findFreePort(preferredPort) {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on('error', () => {
      const fallback = net.createServer();
      fallback.unref();
      fallback.on('error', reject);
      fallback.listen(0, '127.0.0.1', () => {
        const addr = fallback.address();
        const port = typeof addr === 'object' && addr ? addr.port : 3030;
        fallback.close(() => resolve(port));
      });
    });
    server.listen(preferredPort, '127.0.0.1', () => {
      server.close(() => resolve(preferredPort));
    });
  });
}

function startEmbeddedServer(port) {
  const appRoot = path.resolve(__dirname, '..');
  const serverEntry = path.join(appRoot, 'dist-server', 'server.cjs');
  const dataDir = path.join(app.getPath('userData'), 'data');

  serverProcess = spawn(process.execPath, [serverEntry], {
    cwd: appRoot,
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: '1',
      NODE_ENV: 'production',
      PORT: String(port),
      BEACON_APP_ROOT: appRoot,
      BEACON_DATA_DIR: dataDir,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  serverProcess.stderr.on('data', (chunk) => {
    serverStderr += chunk.toString('utf-8');
    if (serverStderr.length > 4000) {
      serverStderr = serverStderr.slice(-4000);
    }
  });
}

function waitForServer(port, retries = 50) {
  return new Promise((resolve, reject) => {
    const attempt = (remaining) => {
      const req = http.get(`http://127.0.0.1:${port}/api/status`, (res) => {
        res.resume();
        if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
          resolve();
        } else if (remaining > 0) {
          setTimeout(() => attempt(remaining - 1), 200);
        } else {
          reject(new Error(`Beacon backend returned HTTP ${res.statusCode}`));
        }
      });
      req.on('error', () => {
        if (remaining > 0) {
          setTimeout(() => attempt(remaining - 1), 200);
        } else {
          reject(new Error(serverStderr || 'Beacon local backend failed to start in time.'));
        }
      });
      req.end();
    };
    attempt(retries);
  });
}

function postLocal(endpoint) {
  const req = http.request({
    hostname: '127.0.0.1',
    port: activePort,
    path: endpoint,
    method: 'POST',
  });
  req.on('error', () => {});
  req.end();
}

function createWindow(port) {
  mainWindow = new BrowserWindow({
    width: 1180,
    height: 780,
    minWidth: 380,
    minHeight: 620,
    backgroundColor: '#0B0D10',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadURL(`http://127.0.0.1:${port}`);
  mainWindow.on('close', (event) => {
    if (!app.isQuitting) {
      event.preventDefault();
      mainWindow.hide();
    }
  });
}

function createTray() {
  try {
    const icon = nativeImage.createEmpty();
    tray = new Tray(icon);
    if (process.platform === 'darwin') {
      tray.setTitle('Beacon');
    }
    tray.setToolTip('Beacon — Local Vite, Git & Ollama Monitor');

    const contextMenu = Menu.buildFromTemplate([
      { label: 'Open Beacon Dashboard', click: () => mainWindow && mainWindow.show() },
      { type: 'separator' },
      { label: 'Start All Services', click: () => postLocal('/api/services/all/start') },
      { label: 'Restart All Services', click: () => postLocal('/api/services/all/restart') },
      { label: 'Stop All Services', click: () => postLocal('/api/services/all/stop') },
      { type: 'separator' },
      {
        label: 'Quit Beacon',
        click: () => {
          app.isQuitting = true;
          app.quit();
        },
      },
    ]);

    tray.setContextMenu(contextMenu);
  } catch {
    // Tray is optional if OS environment does not expose a status bar
  }
}

app.whenReady().then(async () => {
  try {
    activePort = await findFreePort(3000);
    startEmbeddedServer(activePort);
    await waitForServer(activePort);
    createWindow(activePort);
    createTray();
  } catch (err) {
    dialog.showErrorBox(
      'Beacon Startup Error',
      err instanceof Error ? err.message : String(err),
    );
    app.quit();
  }

  app.on('activate', () => {
    if (mainWindow) {
      mainWindow.show();
    } else {
      createWindow(activePort);
    }
  });
});

app.on('before-quit', () => {
  app.isQuitting = true;
  if (serverProcess) {
    serverProcess.kill('SIGTERM');
  }
});
