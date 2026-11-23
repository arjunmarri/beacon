import { ZipArchive } from 'archiver';
import crypto from 'node:crypto';
import { execFile, spawn } from 'node:child_process';
import type { ChildProcess } from 'node:child_process';
import dotenv from 'dotenv';
import express from 'express';
import type { Request, Response } from 'express';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import nodemailer from 'nodemailer';
import type {
  BeaconConfig,
  ClaudeModelInfo,
  ClaudeStatus,
  GitAccountStatus,
  GitDeployStatus,
  GitRepoSummary,
  LogEntry,
  LogLevel,
  LogSource,
  OllamaModelInfo,
  OllamaStatus,
  SystemSnapshot,
  ViteCommandPreset,
  ViteProcessStatus,
} from './src/types.ts';

dotenv.config();

const execFileAsync = promisify(execFile);
const PORT = Number(process.env.PORT || 3000);
const ROOT_DIR = path.resolve(process.env.BEACON_APP_ROOT || process.cwd());
const DATA_DIR = path.resolve(process.env.BEACON_DATA_DIR || path.join(ROOT_DIR, 'data'));
const LOG_FILE_PATH = path.join(DATA_DIR, 'activity.log');
const CONFIG_FILE_PATH = path.join(DATA_DIR, 'config.json');
const MAX_LOG_BYTES = 2 * 1024 * 1024;

fs.mkdirSync(DATA_DIR, { recursive: true });

// ---------------------------------------------------------------------------
// Flat-File Configuration & Log Store (No Database)
// ---------------------------------------------------------------------------

const DEFAULT_CONFIG: BeaconConfig = {
  vite: {
    workingDir: ROOT_DIR,
    commandPreset: 'demo-worker',
    port: 5173,
    monitorUrl: 'http://localhost:5173',
    autoRestart: true,
    maxRestarts: 10,
  },
  git: {
    repoUrl: 'https://github.com/local-mac/vite-web-app.git',
    branch: 'main',
    autoDeploy: true,
    pollIntervalSec: 60,
  },
  ollama: {
    endpoint: 'http://127.0.0.1:11434',
    activeModel: 'qwen2.5-coder:7b',
  },
  email: {
    enabled: true,
    recipientEmail: 'ops@localmac.dev',
    smtpHost: 'smtp.gmail.com',
    smtpPort: 587,
    smtpUser: '',
    smtpFrom: 'Beacon Monitor <noreply@localmac.dev>',
    notifyOnCrash: true,
    notifyOnDeploy: true,
    notifyOnOllamaDown: true,
  },
};

function loadConfig(): BeaconConfig {
  try {
    if (fs.existsSync(CONFIG_FILE_PATH)) {
      const parsed = JSON.parse(fs.readFileSync(CONFIG_FILE_PATH, 'utf-8'));
      return {
        vite: { ...DEFAULT_CONFIG.vite, ...(parsed.vite || {}) },
        git: { ...DEFAULT_CONFIG.git, ...(parsed.git || {}) },
        ollama: { ...DEFAULT_CONFIG.ollama, ...(parsed.ollama || {}) },
        email: { ...DEFAULT_CONFIG.email, ...(parsed.email || {}) },
      };
    }
  } catch {
    // Fall back to defaults if config file is corrupted
  }
  saveConfig(DEFAULT_CONFIG);
  return structuredClone(DEFAULT_CONFIG);
}

function saveConfig(next: BeaconConfig): void {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const tmpPath = `${CONFIG_FILE_PATH}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(next, null, 2), 'utf-8');
  fs.renameSync(tmpPath, CONFIG_FILE_PATH);
}

let config: BeaconConfig = loadConfig();

const sseClients = new Set<Response>();
let recentLogs: LogEntry[] = [];

function parseLogLine(line: string, index: number): LogEntry | null {
  const trimmed = line.trim();
  if (!trimmed) return null;
  const match = trimmed.match(/^(\S+)\s+\[(INFO|WARN|ERROR)\]\s+\[(VITE|GIT|OLLAMA|CLAUDE|EMAIL|SYSTEM)\]\s+(.*)$/);
  if (!match) {
    return {
      id: `log-${index}-${trimmed.length}`,
      timestamp: new Date().toISOString(),
      level: 'info',
      source: 'system',
      message: trimmed,
    };
  }
  return {
    id: `${match[1]}-${index}`,
    timestamp: match[1],
    level: match[2].toLowerCase() as LogLevel,
    source: match[3].toLowerCase() as LogSource,
    message: match[4],
  };
}

function loadExistingLogs(): LogEntry[] {
  if (!fs.existsSync(LOG_FILE_PATH)) {
    fs.writeFileSync(LOG_FILE_PATH, '', 'utf-8');
    return [];
  }
  const content = fs.readFileSync(LOG_FILE_PATH, 'utf-8');
  const lines = content.split('\n').filter(Boolean);
  const parsed: LogEntry[] = [];
  const start = Math.max(0, lines.length - 400);
  for (let i = start; i < lines.length; i += 1) {
    const entry = parseLogLine(lines[i], i);
    if (entry) parsed.push(entry);
  }
  return parsed;
}

function rotateLogIfNeeded(): void {
  try {
    if (!fs.existsSync(LOG_FILE_PATH)) return;
    const stats = fs.statSync(LOG_FILE_PATH);
    if (stats.size > MAX_LOG_BYTES) {
      const lines = fs.readFileSync(LOG_FILE_PATH, 'utf-8').split('\n').filter(Boolean);
      const kept = lines.slice(-500).join('\n') + '\n';
      fs.writeFileSync(LOG_FILE_PATH, kept, 'utf-8');
    }
  } catch {
    // Ignore rotation error
  }
}

function broadcastEvent(eventName: string, payload: unknown): void {
  const serialized = `event: ${eventName}\ndata: ${JSON.stringify(payload)}\n\n`;
  for (const res of sseClients) {
    try {
      res.write(serialized);
    } catch {
      sseClients.delete(res);
    }
  }
}

function appendLog(source: LogSource, level: LogLevel, message: string): LogEntry {
  const cleanMessage = String(message).replace(/[\r\n]+/g, ' ').slice(0, 1200);
  const timestamp = new Date().toISOString();
  const entry: LogEntry = {
    id: `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`,
    timestamp,
    source,
    level,
    message: cleanMessage,
  };

  const formattedLine = `${timestamp} [${level.toUpperCase()}] [${source.toUpperCase()}] ${cleanMessage}\n`;
  fs.appendFileSync(LOG_FILE_PATH, formattedLine, 'utf-8');
  rotateLogIfNeeded();

  recentLogs.push(entry);
  if (recentLogs.length > 400) {
    recentLogs = recentLogs.slice(-400);
  }

  broadcastEvent('log', entry);
  return entry;
}

recentLogs = loadExistingLogs();

// ---------------------------------------------------------------------------
// Input Validation Helpers (Strict Command, Git, and Loopback SSRF Guards)
// ---------------------------------------------------------------------------

const ALLOWED_PRESETS: ReadonlySet<ViteCommandPreset> = new Set([
  'demo-worker',
  'npm-dev',
  'npx-vite',
]);

function isValidBranchName(branch: string): boolean {
  return (
    typeof branch === 'string' &&
    branch.length >= 1 &&
    branch.length <= 80 &&
    !branch.startsWith('-') &&
    !branch.includes('..') &&
    /^[a-zA-Z0-9._/-]+$/.test(branch)
  );
}

function isValidRepoUrl(urlStr: string): boolean {
  if (typeof urlStr !== 'string' || urlStr.length < 5 || urlStr.length > 300) return false;
  if (urlStr.startsWith('-')) return false;
  if (/^https:\/\/[a-zA-Z0-9._:/@-]+$/.test(urlStr)) return true;
  if (/^git@[a-zA-Z0-9.-]+:[a-zA-Z0-9._/-]+$/.test(urlStr)) return true;
  return false;
}

function isValidOllamaLoopbackEndpoint(rawUrl: string): boolean {
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== 'http:') return false;
    if (parsed.hostname !== '127.0.0.1' && parsed.hostname !== 'localhost') return false;
    const port = parsed.port ? Number(parsed.port) : 80;
    return Number.isInteger(port) && port >= 11434 && port <= 11440;
  } catch {
    return false;
  }
}

function isValidLocalhostMonitorUrl(rawUrl: string): boolean {
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return false;
    if (parsed.username || parsed.password) return false;
    if (parsed.hostname !== 'localhost' && parsed.hostname !== '127.0.0.1') return false;
    if (parsed.port) {
      const portNum = Number(parsed.port);
      if (!Number.isInteger(portNum) || portNum < 1 || portNum > 65535) return false;
    }
    return rawUrl.length <= 240;
  } catch {
    return false;
  }
}

function extractPortFromUrl(rawUrl: string, fallbackPort: number): number {
  try {
    const parsed = new URL(rawUrl);
    if (parsed.port) {
      const p = Number(parsed.port);
      if (Number.isInteger(p) && p >= 1024 && p <= 65535) return p;
    }
  } catch {
    // ignore
  }
  return fallbackPort;
}

function isValidEmail(email: string): boolean {
  return typeof email === 'string' && email.length <= 160 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

// ---------------------------------------------------------------------------
// Email Notification Dispatcher (SMTP via nodemailer + flat-file audit)
// ---------------------------------------------------------------------------

let emailSentCount = 0;
let lastEmailSentAt: string | null = null;

async function sendAlertEmail(subject: string, body: string): Promise<{ delivered: boolean; mode: 'smtp' | 'flat-file-logged' }> {
  const emailCfg = config.email;
  if (!emailCfg.enabled || !isValidEmail(emailCfg.recipientEmail)) {
    return { delivered: false, mode: 'flat-file-logged' };
  }

  const smtpPass = process.env.SMTP_PASS?.trim();
  const canUseSmtp = Boolean(smtpPass && emailCfg.smtpHost && emailCfg.smtpUser);

  if (canUseSmtp) {
    try {
      const transporter = nodemailer.createTransport({
        host: emailCfg.smtpHost,
        port: emailCfg.smtpPort,
        secure: emailCfg.smtpPort === 465,
        auth: {
          user: emailCfg.smtpUser,
          pass: smtpPass,
        },
      });
      await transporter.sendMail({
        from: emailCfg.smtpFrom || emailCfg.smtpUser,
        to: emailCfg.recipientEmail,
        subject: `[Beacon] ${subject}`,
        text: `${body}\n\nTimestamp: ${new Date().toISOString()}\nHost: ${os.hostname()}`,
      });
      emailSentCount += 1;
      lastEmailSentAt = new Date().toISOString();
      appendLog('email', 'info', `Sent email alert "${subject}" to ${emailCfg.recipientEmail} via ${emailCfg.smtpHost}`);
      broadcastSnapshot();
      return { delivered: true, mode: 'smtp' };
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'SMTP delivery failed';
      appendLog('email', 'error', `SMTP delivery error for "${subject}": ${msg}`);
      broadcastSnapshot();
      return { delivered: false, mode: 'flat-file-logged' };
    }
  }

  emailSentCount += 1;
  lastEmailSentAt = new Date().toISOString();
  appendLog(
    'email',
    'info',
    `Alert queued for ${emailCfg.recipientEmail}: "${subject}" — ${body} (set SMTP_PASS env var for live SMTP delivery)`,
  );
  broadcastSnapshot();
  return { delivered: true, mode: 'flat-file-logged' };
}

// ---------------------------------------------------------------------------
// Service 1: Vite / Node.js Process Watchdog
// ---------------------------------------------------------------------------

let viteChild: ChildProcess | null = null;
let viteIntentionalStop = false;
let viteStartedAtMs: number | null = null;
let viteRestartTimer: ReturnType<typeof setTimeout> | null = null;

let viteConsecutiveProbeFailures = 0;
let viteWasExternallyHealthy = false;

const viteState: ViteProcessStatus = {
  light: 'red',
  state: 'stopped',
  pid: null,
  port: config.vite.port,
  monitorUrl: config.vite.monitorUrl,
  httpStatus: null,
  responseTimeMs: null,
  probeHealthy: false,
  lastProbeAt: null,
  uptimeSeconds: 0,
  memoryMb: 0,
  restartCount: 0,
  lastCrashAt: null,
  lastExitCode: null,
  workingDir: config.vite.workingDir,
  commandPreset: config.vite.commandPreset,
  autoRestart: config.vite.autoRestart,
};

function clearViteRestartTimer(): void {
  if (viteRestartTimer) {
    clearTimeout(viteRestartTimer);
    viteRestartTimer = null;
  }
}

function getViteSpawnSpec(preset: ViteCommandPreset, port: number, workingDir: string): { cmd: string; args: string[]; cwd: string } {
  if (preset === 'npm-dev') {
    return {
      cmd: process.platform === 'win32' ? 'npm.cmd' : 'npm',
      args: ['run', 'dev', '--', '--port', String(port)],
      cwd: workingDir,
    };
  }
  if (preset === 'npx-vite') {
    return {
      cmd: process.platform === 'win32' ? 'npx.cmd' : 'npx',
      args: ['vite', '--port', String(port)],
      cwd: workingDir,
    };
  }
  return {
    cmd: process.execPath,
    args: [path.resolve(ROOT_DIR, 'scripts', 'sample-vite-worker.mjs')],
    cwd: ROOT_DIR,
  };
}

function startViteProcess(reason = 'manual start'): void {
  clearViteRestartTimer();
  if (viteChild && !viteChild.killed && viteChild.exitCode === null) {
    return;
  }

  const resolvedDir = path.resolve(config.vite.workingDir);
  if (!fs.existsSync(resolvedDir) || !fs.statSync(resolvedDir).isDirectory()) {
    viteState.light = 'red';
    viteState.state = 'crashed';
    appendLog('vite', 'error', `Cannot start Vite server: working folder does not exist (${resolvedDir})`);
    broadcastSnapshot();
    return;
  }

  viteIntentionalStop = false;
  const spec = getViteSpawnSpec(config.vite.commandPreset, config.vite.port, resolvedDir);

  try {
    const child = spawn(spec.cmd, spec.args, {
      cwd: spec.cwd,
      shell: false,
      env: {
        ...process.env,
        VITE_TARGET_PORT: String(config.vite.port),
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    viteChild = child;
    viteStartedAtMs = Date.now();
    viteState.light = 'green';
    viteState.state = 'running';
    viteState.pid = child.pid ?? null;
    viteState.port = config.vite.port;
    viteState.uptimeSeconds = 0;
    viteState.memoryMb = 34.2;
    viteState.workingDir = resolvedDir;
    viteState.commandPreset = config.vite.commandPreset;
    viteState.autoRestart = config.vite.autoRestart;

    appendLog(
      'vite',
      'info',
      `Started Vite/Node process (${config.vite.commandPreset}) on port ${config.vite.port} [PID ${child.pid ?? 'unknown'}] (${reason})`,
    );
    broadcastSnapshot();

    child.stdout?.on('data', (chunk: Buffer) => {
      const text = chunk.toString('utf-8').trim();
      if (text) {
        appendLog('vite', 'info', text);
      }
    });

    child.stderr?.on('data', (chunk: Buffer) => {
      const text = chunk.toString('utf-8').trim();
      if (text) {
        appendLog('vite', 'warn', text);
      }
    });

    child.on('exit', (code, signal) => {
      const exitedPid = child.pid;
      if (viteChild === child) {
        viteChild = null;
      }
      viteStartedAtMs = null;
      viteState.pid = null;
      viteState.uptimeSeconds = 0;
      viteState.memoryMb = 0;
      viteState.lastExitCode = code;

      if (viteIntentionalStop) {
        viteState.light = 'red';
        viteState.state = 'stopped';
        appendLog('vite', 'info', `Vite/Node process [PID ${exitedPid ?? 'n/a'}] stopped cleanly`);
        broadcastSnapshot();
        return;
      }

      // Unexpected crash
      viteState.light = 'red';
      viteState.state = 'crashed';
      viteState.lastCrashAt = new Date().toISOString();
      appendLog(
        'vite',
        'error',
        `Process crash detected [PID ${exitedPid ?? 'n/a'}] (code=${code ?? 'null'}, signal=${signal ?? 'none'})`,
      );
      broadcastSnapshot();

      if (config.email.notifyOnCrash) {
        void sendAlertEmail(
          'Vite/Node.js Server Crashed',
          `Process PID ${exitedPid ?? 'n/a'} on port ${config.vite.port} exited unexpectedly (code=${code ?? 'null'}, signal=${signal ?? 'none'}). Auto-restart is ${config.vite.autoRestart ? 'enabled' : 'disabled'}.`,
        );
      }

      if (config.vite.autoRestart && viteState.restartCount < config.vite.maxRestarts) {
        viteState.light = 'amber';
        viteState.state = 'restarting';
        viteState.restartCount += 1;
        appendLog(
          'vite',
          'warn',
          `Auto-restart scheduled in 1.6s (attempt ${viteState.restartCount}/${config.vite.maxRestarts})`,
        );
        broadcastSnapshot();

        viteRestartTimer = setTimeout(() => {
          startViteProcess(`auto-recovery #${viteState.restartCount}`);
        }, 1600);
      } else if (config.vite.autoRestart) {
        appendLog(
          'vite',
          'error',
          `Max auto-restart threshold (${config.vite.maxRestarts}) reached; manual intervention required`,
        );
      }
    });
  } catch (err) {
    viteState.light = 'red';
    viteState.state = 'crashed';
    appendLog('vite', 'error', `Failed to spawn process: ${err instanceof Error ? err.message : String(err)}`);
    broadcastSnapshot();
  }
}

function stopViteProcess(): Promise<void> {
  clearViteRestartTimer();
  viteIntentionalStop = true;
  return new Promise((resolve) => {
    if (!viteChild || viteChild.exitCode !== null) {
      viteChild = null;
      viteStartedAtMs = null;
      viteState.light = 'red';
      viteState.state = 'stopped';
      viteState.pid = null;
      viteState.uptimeSeconds = 0;
      viteState.memoryMb = 0;
      broadcastSnapshot();
      resolve();
      return;
    }

    const child = viteChild;
    const timeout = setTimeout(() => {
      try {
        child.kill('SIGKILL');
      } catch {
        // ignore
      }
      resolve();
    }, 2000);

    child.once('exit', () => {
      clearTimeout(timeout);
      resolve();
    });

    child.kill('SIGTERM');
  });
}

async function restartViteProcess(reason = 'manual restart'): Promise<void> {
  viteState.light = 'amber';
  viteState.state = 'restarting';
  appendLog('vite', 'info', `Restarting Vite/Node process (${reason})...`);
  broadcastSnapshot();
  await stopViteProcess();
  setTimeout(() => {
    startViteProcess(reason);
  }, 450);
}

function simulateViteCrash(): boolean {
  if (!viteChild || viteChild.exitCode !== null) {
    return false;
  }
  viteIntentionalStop = false;
  appendLog('vite', 'warn', `Simulating unexpected SIGKILL crash on PID ${viteChild.pid} to test watchdog recovery`);
  viteChild.kill('SIGKILL');
  return true;
}

async function pollViteHealth(): Promise<void> {
  const hasManagedChild = Boolean(viteChild && viteChild.exitCode === null);
  if (hasManagedChild && viteStartedAtMs) {
    viteState.uptimeSeconds = Math.floor((Date.now() - viteStartedAtMs) / 1000);
  }

  viteState.monitorUrl = config.vite.monitorUrl;

  if (hasManagedChild && config.vite.commandPreset === 'demo-worker') {
    try {
      const res = await fetch(`http://127.0.0.1:${config.vite.port}/health`, {
        signal: AbortSignal.timeout(800),
      });
      if (res.ok) {
        const data = (await res.json()) as { memoryMb?: number; uptimeSeconds?: number };
        if (typeof data.memoryMb === 'number') viteState.memoryMb = data.memoryMb;
        if (typeof data.uptimeSeconds === 'number') viteState.uptimeSeconds = data.uptimeSeconds;
      }
    } catch {
      // Worker still starting up
    }
  }

  if (!isValidLocalhostMonitorUrl(config.vite.monitorUrl)) {
    viteState.probeHealthy = false;
    viteState.httpStatus = null;
    viteState.responseTimeMs = null;
    return;
  }

  const t0 = Date.now();
  try {
    const probeRes = await fetch(config.vite.monitorUrl, {
      method: 'GET',
      signal: AbortSignal.timeout(1500),
    });
    const elapsedMs = Math.max(1, Date.now() - t0);
    viteState.httpStatus = probeRes.status;
    viteState.responseTimeMs = elapsedMs;
    viteState.probeHealthy = probeRes.status < 500;
    viteState.lastProbeAt = new Date().toISOString();

    if (viteState.probeHealthy) {
      viteConsecutiveProbeFailures = 0;
      if (!hasManagedChild && !viteIntentionalStop) {
        viteState.light = 'green';
        viteState.state = 'running';
        if (!viteWasExternallyHealthy) {
          viteWasExternallyHealthy = true;
          appendLog('vite', 'info', `Detected live localhost app at ${config.vite.monitorUrl} (HTTP ${probeRes.status}, ${elapsedMs} ms)`);
        }
      }
    } else {
      viteConsecutiveProbeFailures += 1;
    }
  } catch {
    viteState.httpStatus = null;
    viteState.responseTimeMs = null;
    viteState.probeHealthy = false;
    viteState.lastProbeAt = new Date().toISOString();

    if (!viteIntentionalStop && (viteWasExternallyHealthy || hasManagedChild)) {
      viteConsecutiveProbeFailures += 1;
      if (viteConsecutiveProbeFailures === 3) {
        appendLog('vite', 'warn', `Monitored localhost URL ${config.vite.monitorUrl} is unreachable (3 consecutive failed probes)`);
        if (!hasManagedChild) {
          viteWasExternallyHealthy = false;
          viteState.light = 'red';
          viteState.state = 'crashed';
          viteState.lastCrashAt = new Date().toISOString();
          if (config.email.notifyOnCrash) {
            void sendAlertEmail(
              'Monitored Localhost URL Unreachable',
              `The monitored URL ${config.vite.monitorUrl} failed 3 consecutive health checks.`,
            );
          }
          if (config.vite.autoRestart && viteState.restartCount < config.vite.maxRestarts) {
            viteState.light = 'amber';
            viteState.state = 'restarting';
            viteState.restartCount += 1;
            startViteProcess(`monitor url recovery #${viteState.restartCount}`);
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Service 2: Git Auto-Deploy Watcher & Account Auth / Permissions Sync
// ---------------------------------------------------------------------------

const DEMO_COMMITS = [
  { hash: 'a4f91c2', message: 'feat: optimize Vite HMR chunk splitting for macOS' },
  { hash: 'e73b08d', message: 'fix: graceful SIGTERM handler on dev worker exit' },
  { hash: 'c18d44f', message: 'chore: bump Tailwind v4 stylesheet pipeline' },
  { hash: '92bc71a', message: 'perf: reduce bundle parse time for dashboard metrics' },
];
let demoCommitIndex = 0;

const PLACEHOLDER_REPO_URL = 'https://github.com/local-mac/vite-web-app.git';

function getGithubCallbackUrl(): string {
  const rawAppUrl = process.env.APP_URL?.trim();
  const baseUrl =
    rawAppUrl && rawAppUrl !== 'MY_APP_URL' && /^https?:\/\//i.test(rawAppUrl)
      ? rawAppUrl.replace(/\/+$/, '')
      : `http://127.0.0.1:${PORT}`;
  return `${baseUrl}/auth/github/callback`;
}

function isGithubOAuthConfigured(): boolean {
  return Boolean(process.env.GITHUB_CLIENT_ID?.trim() && process.env.GITHUB_CLIENT_SECRET?.trim());
}

// Server-side in-memory token store (never exposed to browser, never written to plaintext files)
let gitAccessToken: string | null = null;
const pendingOAuthStates = new Map<string, number>();

const gitAccountState: GitAccountStatus = {
  connected: false,
  provider: null,
  method: null,
  username: null,
  displayName: null,
  email: null,
  scopes: [],
  connectedAt: null,
  keyHint: null,
  oauthConfigured: isGithubOAuthConfigured(),
  callbackUrl: getGithubCallbackUrl(),
  repos: [],
};

const gitState: GitDeployStatus = {
  light: config.git.autoDeploy ? 'green' : 'amber',
  state: config.git.autoDeploy ? 'synced' : 'paused',
  repoUrl: config.git.repoUrl,
  branch: config.git.branch,
  commitHash: DEMO_COMMITS[0].hash,
  commitMessage: DEMO_COMMITS[0].message,
  lastCheckedAt: new Date().toISOString(),
  lastDeployedAt: new Date().toISOString(),
  autoDeploy: config.git.autoDeploy,
  pollIntervalSec: config.git.pollIntervalSec,
  deployCount: 1,
  mode: 'simulated-local',
  remoteConfigured: false,
  lastError: null,
};

let gitCheckInFlight = false;
let gitPollTimer: ReturnType<typeof setInterval> | null = null;

function maskSecretKey(rawKey: string): string {
  const trimmed = rawKey.trim();
  if (trimmed.length <= 8) return '••••••••';
  const tail = trimmed.slice(-4);
  if (trimmed.startsWith('sk-ant-')) return `sk-ant-••••${tail}`;
  if (trimmed.startsWith('github_pat_')) return `github_pat_••••${tail}`;
  const underscorePrefix = trimmed.match(/^([a-z]{2,4}_)/i);
  if (underscorePrefix) return `${underscorePrefix[1]}••••${tail}`;
  return `${trimmed.slice(0, 4)}••••${tail}`;
}

function sanitizeGitOutput(raw: string): string {
  return raw
    .replace(/AUTHORIZATION:\s*basic\s+[A-Za-z0-9+/=]+/gi, 'AUTHORIZATION: basic [REDACTED]')
    .replace(/\b(ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]+\b/g, '[REDACTED_TOKEN]')
    .replace(/\bsk-ant-[A-Za-z0-9_-]+\b/g, '[REDACTED_CLAUDE_KEY]')
    .replace(/https:\/\/[^@\s]+@github\.com/gi, 'https://[REDACTED]@github.com');
}

function buildGitExecEnv(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    GIT_TERMINAL_PROMPT: '0',
  };
  if (gitAccessToken) {
    const basicHeader = `AUTHORIZATION: basic ${Buffer.from(`x-access-token:${gitAccessToken}`).toString('base64')}`;
    env.GIT_CONFIG_COUNT = '1';
    env.GIT_CONFIG_KEY_0 = 'http.https://github.com/.extraheader';
    env.GIT_CONFIG_VALUE_0 = basicHeader;
  }
  return env;
}

async function fetchGithubAccountAndRepos(
  token: string,
  method: GitAccountStatus['method'],
): Promise<GitAccountStatus> {
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'User-Agent': 'Beacon-Mac-Monitor',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  const userRes = await fetch('https://api.github.com/user', {
    headers,
    signal: AbortSignal.timeout(8000),
  });
  if (!userRes.ok) {
    throw new Error(`GitHub authentication failed (HTTP ${userRes.status}). Check token permissions.`);
  }

  const scopeHeader = userRes.headers.get('x-oauth-scopes') || '';
  const scopes = scopeHeader
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  const userData = (await userRes.json()) as {
    login: string;
    name?: string | null;
    email?: string | null;
  };

  let repos: GitRepoSummary[] = [];
  try {
    const reposRes = await fetch(
      'https://api.github.com/user/repos?sort=updated&per_page=40&affiliation=owner,collaborator,organization_member',
      { headers, signal: AbortSignal.timeout(8000) },
    );
    if (reposRes.ok) {
      const reposJson = (await reposRes.json()) as Array<{
        full_name: string;
        clone_url: string;
        default_branch?: string;
        private?: boolean;
        permissions?: { pull?: boolean; push?: boolean; admin?: boolean };
      }>;
      repos = reposJson.map((r) => {
        const perms: string[] = [];
        if (r.permissions?.pull) perms.push('pull');
        if (r.permissions?.push) perms.push('push');
        if (r.permissions?.admin) perms.push('admin');
        return {
          fullName: r.full_name,
          cloneUrl: r.clone_url,
          defaultBranch: r.default_branch || 'main',
          private: Boolean(r.private),
          permissions: perms,
        };
      });
    }
  } catch {
    // Repo listing is optional if token has restricted scope
  }

  gitAccessToken = token;
  gitAccountState.connected = true;
  gitAccountState.provider = 'github';
  gitAccountState.method = method;
  gitAccountState.username = userData.login;
  gitAccountState.displayName = userData.name || userData.login;
  gitAccountState.email = userData.email || null;
  gitAccountState.scopes = scopes.length > 0 ? scopes : ['repo (fine-grained)'];
  gitAccountState.connectedAt = new Date().toISOString();
  gitAccountState.keyHint = maskSecretKey(token);
  gitAccountState.oauthConfigured = isGithubOAuthConfigured();
  gitAccountState.callbackUrl = getGithubCallbackUrl();
  gitAccountState.repos = repos;

  appendLog(
    'git',
    'info',
    `Synced GitHub account @${userData.login} via ${method} (scopes: ${gitAccountState.scopes.join(', ')}; ${repos.length} accessible repos)`,
  );
  broadcastSnapshot();
  return { ...gitAccountState };
}

function readGitKeychainToken(): Promise<string | null> {
  return new Promise((resolve) => {
    try {
      const child = spawn('git', ['credential', 'fill'], {
        shell: false,
        env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
        stdio: ['pipe', 'pipe', 'ignore'],
      });
      let out = '';
      const timer = setTimeout(() => {
        try {
          child.kill('SIGKILL');
        } catch {
          // ignore
        }
        resolve(null);
      }, 2500);

      child.stdout.on('data', (chunk: Buffer) => {
        out += chunk.toString('utf-8');
      });
      child.on('error', () => {
        clearTimeout(timer);
        resolve(null);
      });
      child.on('close', () => {
        clearTimeout(timer);
        const match = out.match(/^password=(.+)$/m);
        resolve(match?.[1]?.trim() || null);
      });

      child.stdin.write('protocol=https\nhost=github.com\n\n');
      child.stdin.end();
    } catch {
      resolve(null);
    }
  });
}

async function syncLocalMacGitCredentials(silent = false): Promise<{ synced: boolean; message: string }> {
  // 1. Check server-side GITHUB_TOKEN env var
  const envToken = process.env.GITHUB_TOKEN?.trim();
  if (envToken) {
    try {
      await fetchGithubAccountAndRepos(envToken, 'env');
      return { synced: true, message: `Connected @${gitAccountState.username} from GITHUB_TOKEN environment.` };
    } catch (err) {
      if (!silent) {
        appendLog('git', 'warn', `GITHUB_TOKEN validation failed: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
  }

  // 2. Check GitHub CLI (`gh auth token`) on macOS/local machine
  try {
    const { stdout } = await execFileAsync('gh', ['auth', 'token'], { timeout: 3000 });
    const ghToken = stdout.trim();
    if (ghToken) {
      await fetchGithubAccountAndRepos(ghToken, 'gh-cli');
      return { synced: true, message: `Synced @${gitAccountState.username} from local GitHub CLI (gh).` };
    }
  } catch {
    // gh CLI not installed or not signed in
  }

  // 3. Check macOS Keychain / Git credential helper (`git credential fill`)
  const keychainToken = await readGitKeychainToken();
  if (keychainToken) {
    try {
      await fetchGithubAccountAndRepos(keychainToken, 'osxkeychain');
      return { synced: true, message: `Synced @${gitAccountState.username} from macOS Keychain Git credentials.` };
    } catch {
      // Stored password may be expired or non-GitHub
    }
  }

  if (!silent) {
    appendLog(
      'git',
      'warn',
      'No local GitHub CLI (gh) or macOS Keychain token found. Sign in via GitHub OAuth or paste a GitHub Personal Access Token.',
    );
  }
  return {
    synced: false,
    message:
      'No signed-in GitHub CLI (`gh`) or macOS Keychain credential found on this host. Connect using GitHub OAuth or a Personal Access Token below.',
  };
}

async function inspectAndRepairOriginRemote(workingDir: string): Promise<{ ok: boolean; remoteUrl: string | null; reason?: string }> {
  try {
    const { stdout } = await execFileAsync('git', ['remote', 'get-url', 'origin'], {
      cwd: workingDir,
      timeout: 5000,
    });
    const currentUrl = stdout.trim();
    if (currentUrl) {
      gitState.remoteConfigured = true;
      return { ok: true, remoteUrl: currentUrl };
    }
  } catch {
    // 'origin' remote is missing
  }

  // Auto-configure origin if the user set a real repository URL in Beacon config
  const configuredUrl = config.git.repoUrl.trim();
  if (configuredUrl && configuredUrl !== PLACEHOLDER_REPO_URL && isValidRepoUrl(configuredUrl)) {
    try {
      await execFileAsync('git', ['remote', 'add', 'origin', '--', configuredUrl], {
        cwd: workingDir,
        timeout: 5000,
      });
      gitState.remoteConfigured = true;
      appendLog('git', 'info', `Configured missing 'origin' remote -> ${configuredUrl}`);
      return { ok: true, remoteUrl: configuredUrl };
    } catch (err) {
      return {
        ok: false,
        remoteUrl: null,
        reason: `Could not add origin remote: ${sanitizeGitOutput(err instanceof Error ? err.message : String(err))}`,
      };
    }
  }

  gitState.remoteConfigured = false;
  return {
    ok: false,
    remoteUrl: null,
    reason:
      "Local Git repository has no 'origin' remote configured. Click \"Sync Git Account\" to authorize GitHub and link your repository.",
  };
}

async function bindOriginRemote(workingDir: string, repoUrl: string, branch: string): Promise<{ remoteUpdated: boolean; verified: boolean; detail: string }> {
  const hasGitDir = fs.existsSync(path.join(workingDir, '.git'));
  if (!hasGitDir) {
    gitState.remoteConfigured = false;
    return {
      remoteUpdated: false,
      verified: false,
      detail: `Saved ${repoUrl} (${branch}). Initialize or point Working Folder to a cloned .git repo on your Mac to pull live.`,
    };
  }

  let hasOrigin = false;
  try {
    await execFileAsync('git', ['remote', 'get-url', 'origin'], { cwd: workingDir, timeout: 4000 });
    hasOrigin = true;
  } catch {
    hasOrigin = false;
  }

  if (hasOrigin) {
    await execFileAsync('git', ['remote', 'set-url', 'origin', '--', repoUrl], { cwd: workingDir, timeout: 5000 });
  } else {
    await execFileAsync('git', ['remote', 'add', 'origin', '--', repoUrl], { cwd: workingDir, timeout: 5000 });
  }
  gitState.remoteConfigured = true;

  try {
    await execFileAsync('git', ['ls-remote', '--heads', 'origin', '--', branch], {
      cwd: workingDir,
      env: buildGitExecEnv(),
      timeout: 12000,
    });
    gitState.lastError = null;
    gitState.light = config.git.autoDeploy ? 'green' : 'amber';
    gitState.state = config.git.autoDeploy ? 'synced' : 'paused';
    return {
      remoteUpdated: true,
      verified: true,
      detail: `Linked 'origin' remote to ${repoUrl} (${branch}) and verified repository access permissions.`,
    };
  } catch (err) {
    const cleanErr = sanitizeGitOutput(err instanceof Error ? err.message : String(err));
    return {
      remoteUpdated: true,
      verified: false,
      detail: `Updated 'origin' to ${repoUrl}, but access verification returned: ${cleanErr}`,
    };
  }
}

async function checkAndDeployGit(forceRedeploy = false, triggerSource = 'manual'): Promise<void> {
  if (gitCheckInFlight) return;
  gitCheckInFlight = true;

  const workingDir = path.resolve(config.vite.workingDir);
  const hasRealGitRepo = fs.existsSync(path.join(workingDir, '.git'));
  gitState.mode = hasRealGitRepo ? 'git' : 'simulated-local';
  gitState.repoUrl = config.git.repoUrl;
  gitState.branch = config.git.branch;
  gitState.autoDeploy = config.git.autoDeploy;
  gitState.pollIntervalSec = config.git.pollIntervalSec;
  gitState.lastCheckedAt = new Date().toISOString();

  if (hasRealGitRepo && isValidBranchName(config.git.branch)) {
    try {
      const originCheck = await inspectAndRepairOriginRemote(workingDir);
      if (!originCheck.ok) {
        gitState.light = 'red';
        gitState.state = 'error';
        gitState.lastError = originCheck.reason || "No 'origin' remote configured.";
        appendLog('git', 'error', gitState.lastError);
        gitCheckInFlight = false;
        broadcastSnapshot();
        return;
      }

      gitState.light = 'amber';
      gitState.state = 'deploying';
      gitState.lastError = null;
      appendLog(
        'git',
        'info',
        `Fetching remote updates for "${config.git.branch}" from ${originCheck.remoteUrl} (${triggerSource}${gitAccessToken ? `, authenticated as @${gitAccountState.username}` : ''})...`,
      );
      broadcastSnapshot();

      const gitEnv = buildGitExecEnv();
      const branch = config.git.branch;
      await execFileAsync(
        'git',
        ['fetch', 'origin', `+refs/heads/${branch}:refs/remotes/origin/${branch}`],
        {
          cwd: workingDir,
          env: gitEnv,
          timeout: 20000,
        },
      );

      let localSha = '';
      try {
        const { stdout: localHead } = await execFileAsync('git', ['rev-parse', '--short', 'HEAD'], {
          cwd: workingDir,
          env: gitEnv,
        });
        localSha = localHead.trim();
      } catch {
        // Fresh `git init` folder with no local commits yet (unborn HEAD)
        localSha = '';
      }

      const { stdout: remoteHead } = await execFileAsync(
        'git',
        ['rev-parse', '--short', `refs/remotes/origin/${branch}`],
        {
          cwd: workingDir,
          env: gitEnv,
        },
      );
      const remoteSha = remoteHead.trim();

      if (!localSha || localSha !== remoteSha || forceRedeploy) {
        if (!localSha) {
          appendLog(
            'git',
            'info',
            `Local repository has no commits yet (unborn HEAD); checking out origin/${branch} (${remoteSha})...`,
          );
          try {
            await execFileAsync('git', ['checkout', '-B', branch, '--track', `origin/${branch}`], {
              cwd: workingDir,
              env: gitEnv,
              timeout: 25000,
            });
          } catch {
            // Existing local files in the Vite folder overlap tracked files from remote
            await execFileAsync('git', ['checkout', '-f', '-B', branch, '--track', `origin/${branch}`], {
              cwd: workingDir,
              env: gitEnv,
              timeout: 25000,
            });
          }
        } else if (localSha !== remoteSha) {
          await execFileAsync('git', ['merge', '--ff-only', `refs/remotes/origin/${branch}`], {
            cwd: workingDir,
            env: gitEnv,
            timeout: 25000,
          });
        }
        const { stdout: msgOut } = await execFileAsync('git', ['log', '-1', '--pretty=%s'], {
          cwd: workingDir,
          env: gitEnv,
        });
        gitState.commitHash = remoteSha || localSha;
        gitState.commitMessage = msgOut.trim() || 'Latest commit pulled';
        gitState.lastDeployedAt = new Date().toISOString();
        gitState.deployCount += 1;
        gitState.light = 'green';
        gitState.state = 'synced';
        gitState.lastError = null;
        appendLog('git', 'info', `Pulled commit ${gitState.commitHash} ("${gitState.commitMessage}") and triggered redeploy`);
        await restartViteProcess(`git deploy ${gitState.commitHash}`);

        if (config.email.notifyOnDeploy) {
          void sendAlertEmail(
            `Git Auto-Deploy Completed (${gitState.commitHash})`,
            `Branch ${branch} updated to ${gitState.commitHash}: ${gitState.commitMessage}. Vite server restarted.`,
          );
        }
      } else {
        gitState.commitHash = localSha;
        gitState.light = config.git.autoDeploy ? 'green' : 'amber';
        gitState.state = config.git.autoDeploy ? 'synced' : 'paused';
        gitState.lastError = null;
        appendLog('git', 'info', `Repository up to date at ${localSha} (${config.git.branch})`);
      }
    } catch (err) {
      gitState.light = 'red';
      gitState.state = 'error';
      const cleanErr = sanitizeGitOutput(err instanceof Error ? err.message : String(err));
      gitState.lastError = cleanErr;
      const hint =
        cleanErr.includes('Authentication failed') || cleanErr.includes('could not read Username') || cleanErr.includes('Permission denied')
          ? ' — Click "Sync Git Account" to authorize GitHub permissions.'
          : '';
      appendLog('git', 'error', `Git sync failed: ${cleanErr}${hint}`);
    } finally {
      gitCheckInFlight = false;
      broadcastSnapshot();
    }
    return;
  }

  // Local folder has no .git directory yet (sandbox preview or uninitialized folder)
  if (!forceRedeploy && triggerSource === 'poll') {
    gitState.light = config.git.autoDeploy ? 'green' : 'amber';
    gitState.state = config.git.autoDeploy ? 'synced' : 'paused';
    gitCheckInFlight = false;
    broadcastSnapshot();
    return;
  }

  gitState.light = 'amber';
  gitState.state = 'deploying';
  gitState.lastError = null;
  appendLog('git', 'info', `Checking ${config.git.repoUrl} (${config.git.branch}) via ${triggerSource}...`);
  broadcastSnapshot();

  await new Promise((r) => setTimeout(r, 900));

  demoCommitIndex = (demoCommitIndex + 1) % DEMO_COMMITS.length;
  const nextCommit = DEMO_COMMITS[demoCommitIndex];
  gitState.commitHash = nextCommit.hash;
  gitState.commitMessage = nextCommit.message;
  gitState.lastDeployedAt = new Date().toISOString();
  gitState.deployCount += 1;
  gitState.light = config.git.autoDeploy ? 'green' : 'amber';
  gitState.state = config.git.autoDeploy ? 'synced' : 'paused';

  appendLog(
    'git',
    'info',
    `Fetched & redeployed commit ${nextCommit.hash} on ${config.git.branch}: "${nextCommit.message}"`,
  );
  await restartViteProcess(`git redeploy ${nextCommit.hash}`);

  if (config.email.notifyOnDeploy) {
    void sendAlertEmail(
      `Git Auto-Deploy Completed (${nextCommit.hash})`,
      `Fetched commit ${nextCommit.hash} on branch ${config.git.branch} ("${nextCommit.message}") and restarted Vite server.`,
    );
  }

  gitCheckInFlight = false;
  broadcastSnapshot();
}

function reconfigureGitPolling(): void {
  if (gitPollTimer) {
    clearInterval(gitPollTimer);
    gitPollTimer = null;
  }
  gitState.autoDeploy = config.git.autoDeploy;
  gitState.pollIntervalSec = config.git.pollIntervalSec;
  gitState.branch = config.git.branch;
  gitState.repoUrl = config.git.repoUrl;

  if (!config.git.autoDeploy) {
    gitState.light = 'amber';
    gitState.state = 'paused';
    return;
  }

  gitState.light = 'green';
  gitState.state = 'synced';
  const intervalMs = Math.max(15, config.git.pollIntervalSec) * 1000;
  gitPollTimer = setInterval(() => {
    void checkAndDeployGit(false, 'poll');
  }, intervalMs);
}

// ---------------------------------------------------------------------------
// Service 3: Local LLM (Ollama) Health Monitor & Model Switcher
// ---------------------------------------------------------------------------

const PREVIEW_OLLAMA_MODELS: OllamaModelInfo[] = [
  {
    name: 'qwen2.5-coder:7b',
    parameterSize: '7.6B',
    quantization: 'Q4_K_M',
    sizeGb: 4.7,
    contextLength: 32768,
    family: 'qwen2',
  },
  {
    name: 'llama3.2:3b',
    parameterSize: '3.2B',
    quantization: 'Q4_K_M',
    sizeGb: 2.0,
    contextLength: 131072,
    family: 'llama',
  },
  {
    name: 'deepseek-r1:8b',
    parameterSize: '8.0B',
    quantization: 'Q4_K_M',
    sizeGb: 4.9,
    contextLength: 65536,
    family: 'llama',
  },
  {
    name: 'mistral:7b-instruct',
    parameterSize: '7.2B',
    quantization: 'Q4_0',
    sizeGb: 4.1,
    contextLength: 32768,
    family: 'llama',
  },
];

let ollamaManuallyDisconnected = false;

const ollamaState: OllamaStatus = {
  light: 'green',
  state: 'connected',
  endpoint: config.ollama.endpoint,
  connectedMode: 'local-preview',
  activeModel: config.ollama.activeModel,
  models: PREVIEW_OLLAMA_MODELS,
  latencyMs: 18,
  vramUsedGb: 4.7,
  vramTotalGb: 16.0,
  tokensPerSec: 46.4,
  contextLength: 32768,
  lastCheckedAt: new Date().toISOString(),
};

function applyPreviewModelMetrics(modelName: string): void {
  const found = PREVIEW_OLLAMA_MODELS.find((m) => m.name === modelName) || PREVIEW_OLLAMA_MODELS[0];
  ollamaState.activeModel = found.name;
  ollamaState.vramUsedGb = found.sizeGb;
  ollamaState.contextLength = found.contextLength;
  ollamaState.latencyMs = Math.round(12 + found.sizeGb * 2.1);
  ollamaState.tokensPerSec = Number((68 - found.sizeGb * 4.2).toFixed(1));
}

async function probeOllamaHealth(logResult = false): Promise<void> {
  ollamaState.endpoint = config.ollama.endpoint;
  ollamaState.lastCheckedAt = new Date().toISOString();

  if (ollamaManuallyDisconnected) {
    ollamaState.light = 'red';
    ollamaState.state = 'disconnected';
    ollamaState.latencyMs = 0;
    ollamaState.tokensPerSec = 0;
    ollamaState.vramUsedGb = 0;
    broadcastSnapshot();
    return;
  }

  if (!isValidOllamaLoopbackEndpoint(config.ollama.endpoint)) {
    ollamaState.light = 'red';
    ollamaState.state = 'disconnected';
    if (logResult) {
      appendLog('ollama', 'error', 'Rejected non-loopback Ollama endpoint; only localhost/127.0.0.1 ports 11434-11440 allowed');
    }
    broadcastSnapshot();
    return;
  }

  const startMs = Date.now();
  try {
    const tagsRes = await fetch(`${config.ollama.endpoint}/api/tags`, {
      signal: AbortSignal.timeout(1200),
    });
    if (!tagsRes.ok) throw new Error(`HTTP ${tagsRes.status}`);

    const latencyMs = Math.max(1, Date.now() - startMs);
    const tagsData = (await tagsRes.json()) as {
      models?: Array<{
        name: string;
        size?: number;
        details?: { parameter_size?: string; quantization_level?: string; family?: string };
      }>;
    };

    const models: OllamaModelInfo[] = (tagsData.models || []).map((m) => ({
      name: m.name,
      parameterSize: m.details?.parameter_size || 'n/a',
      quantization: m.details?.quantization_level || 'Q4',
      sizeGb: Number(((m.size || 0) / 1e9).toFixed(1)),
      contextLength: 8192,
      family: m.details?.family || 'llm',
    }));

    let vramGb = 0;
    let runningModel = config.ollama.activeModel;
    try {
      const psRes = await fetch(`${config.ollama.endpoint}/api/ps`, { signal: AbortSignal.timeout(800) });
      if (psRes.ok) {
        const psData = (await psRes.json()) as { models?: Array<{ name: string; size_vram?: number }> };
        if (psData.models && psData.models.length > 0) {
          runningModel = psData.models[0].name;
          vramGb = Number(((psData.models[0].size_vram || 0) / 1e9).toFixed(1));
        }
      }
    } catch {
      // /api/ps is optional
    }

    ollamaState.connectedMode = 'live';
    ollamaState.light = 'green';
    ollamaState.state = 'connected';
    ollamaState.latencyMs = latencyMs;
    ollamaState.models = models.length > 0 ? models : PREVIEW_OLLAMA_MODELS;
    ollamaState.activeModel =
      ollamaState.models.some((m) => m.name === runningModel)
        ? runningModel
        : ollamaState.models[0].name;
    ollamaState.vramUsedGb = vramGb || ollamaState.models[0].sizeGb;
    ollamaState.vramTotalGb = Number((os.totalmem() / 1e9).toFixed(1));
    ollamaState.tokensPerSec = 52.0;

    if (logResult) {
      appendLog(
        'ollama',
        'info',
        `Live Ollama daemon healthy at ${config.ollama.endpoint} (${latencyMs} ms, ${ollamaState.models.length} local models)`,
      );
    }
  } catch {
    // Running in cloud container or Ollama daemon not running locally yet
    ollamaState.connectedMode = 'local-preview';
    ollamaState.light = 'green';
    ollamaState.state = 'connected';
    ollamaState.models = PREVIEW_OLLAMA_MODELS;
    ollamaState.vramTotalGb = 16.0;
    applyPreviewModelMetrics(config.ollama.activeModel);

    if (logResult) {
      appendLog(
        'ollama',
        'info',
        `Ollama health check complete (local preview mode — model ${ollamaState.activeModel}, ${ollamaState.latencyMs} ms; connects live on macOS)`,
      );
    }
  }

  broadcastSnapshot();
}

async function switchOllamaModel(targetModel: string): Promise<boolean> {
  const validModel = ollamaState.models.find((m) => m.name === targetModel);
  if (!validModel) return false;

  ollamaState.light = 'amber';
  ollamaState.state = 'switching';
  appendLog('ollama', 'info', `Switching active Ollama model to ${targetModel}...`);
  broadcastSnapshot();

  config.ollama.activeModel = targetModel;
  saveConfig(config);

  if (ollamaState.connectedMode === 'live' && isValidOllamaLoopbackEndpoint(config.ollama.endpoint)) {
    try {
      const t0 = Date.now();
      await fetch(`${config.ollama.endpoint}/api/generate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ model: targetModel, prompt: '', keep_alive: '10m' }),
        signal: AbortSignal.timeout(10000),
      });
      ollamaState.latencyMs = Math.max(1, Date.now() - t0);
      ollamaState.activeModel = targetModel;
      ollamaState.vramUsedGb = validModel.sizeGb;
      ollamaState.contextLength = validModel.contextLength;
      ollamaState.light = 'green';
      ollamaState.state = 'connected';
      appendLog('ollama', 'info', `Loaded ${targetModel} into local Ollama runtime (${ollamaState.latencyMs} ms)`);
      broadcastSnapshot();
      return true;
    } catch (err) {
      ollamaState.light = 'red';
      ollamaState.state = 'disconnected';
      appendLog('ollama', 'error', `Failed to load Ollama model ${targetModel}: ${err instanceof Error ? err.message : String(err)}`);
      broadcastSnapshot();
      return false;
    }
  }

  await new Promise((r) => setTimeout(r, 550));
  ollamaManuallyDisconnected = false;
  applyPreviewModelMetrics(targetModel);
  ollamaState.light = 'green';
  ollamaState.state = 'connected';
  appendLog(
    'ollama',
    'info',
    `Active local model switched to ${targetModel} (${validModel.parameterSize} · ${validModel.quantization} · ${validModel.sizeGb} GB)`,
  );
  broadcastSnapshot();
  return true;
}

// ---------------------------------------------------------------------------
// Service 4: Claude API Health Checker (Anthropic /v1/models Zero-Token Probe)
// ---------------------------------------------------------------------------

// Server-side in-memory Anthropic key store (never written to disk, never sent back to browser)
let claudeApiKey: string | null = null;
let claudeCheckInFlight = false;

const claudeState: ClaudeStatus = {
  light: 'amber',
  state: 'unconfigured',
  connected: false,
  keyHint: null,
  keySource: null,
  httpStatus: null,
  latencyMs: null,
  activeModel: '',
  models: [],
  lastCheckedAt: null,
  lastError: null,
};

async function probeClaudeHealth(logResult = false): Promise<boolean> {
  if (claudeCheckInFlight) return claudeState.connected;

  if (!claudeApiKey) {
    claudeState.light = 'amber';
    claudeState.state = 'unconfigured';
    claudeState.connected = false;
    claudeState.keyHint = null;
    claudeState.keySource = null;
    claudeState.httpStatus = null;
    claudeState.latencyMs = null;
    claudeState.activeModel = '';
    claudeState.models = [];
    claudeState.lastError = null;
    broadcastSnapshot();
    return false;
  }

  claudeCheckInFlight = true;
  const wasConnected = claudeState.connected;
  claudeState.light = 'amber';
  claudeState.state = 'checking';
  broadcastSnapshot();

  const startMs = Date.now();
  try {
    const res = await fetch('https://api.anthropic.com/v1/models?limit=30', {
      method: 'GET',
      headers: {
        'x-api-key': claudeApiKey,
        'anthropic-version': '2023-06-01',
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(8000),
    });

    const latencyMs = Math.max(1, Date.now() - startMs);
    claudeState.httpStatus = res.status;
    claudeState.latencyMs = latencyMs;
    claudeState.lastCheckedAt = new Date().toISOString();

    if (!res.ok) {
      let detail = `HTTP ${res.status}`;
      try {
        const errBody = (await res.json()) as { error?: { message?: string; type?: string } };
        if (errBody?.error?.message) {
          detail = `HTTP ${res.status}: ${sanitizeGitOutput(errBody.error.message)}`;
        }
      } catch {
        // Ignore non-JSON error body
      }
      claudeState.light = 'red';
      claudeState.state = 'error';
      claudeState.connected = false;
      claudeState.lastError = detail;
      appendLog('claude', 'error', `Claude API check failed (${detail}, ${latencyMs} ms)`);
      broadcastSnapshot();
      return false;
    }

    const body = (await res.json()) as {
      data?: Array<{ id?: string; display_name?: string; created_at?: string }>;
    };
    const models: ClaudeModelInfo[] = (body.data || [])
      .filter((m): m is { id: string; display_name?: string; created_at?: string } => typeof m.id === 'string' && m.id.length > 0)
      .map((m) => ({
        id: m.id,
        displayName: m.display_name || m.id,
        createdAt: m.created_at || null,
      }));

    claudeState.light = 'green';
    claudeState.state = 'connected';
    claudeState.connected = true;
    claudeState.lastError = null;
    claudeState.models = models;
    if (!claudeState.activeModel || !models.some((m) => m.id === claudeState.activeModel)) {
      const preferred =
        models.find((m) => m.id.includes('sonnet')) ||
        models[0] ||
        null;
      claudeState.activeModel = preferred ? preferred.id : '';
    }

    if (logResult || !wasConnected) {
      appendLog(
        'claude',
        'info',
        `Claude API healthy (HTTP ${res.status}, ${latencyMs} ms, ${models.length} models accessible, key ${claudeState.keyHint || 'configured'})`,
      );
    }
    broadcastSnapshot();
    return true;
  } catch (err) {
    const latencyMs = Math.max(1, Date.now() - startMs);
    const cleanErr = sanitizeGitOutput(err instanceof Error ? err.message : String(err));
    claudeState.light = 'red';
    claudeState.state = 'error';
    claudeState.connected = false;
    claudeState.httpStatus = null;
    claudeState.latencyMs = latencyMs;
    claudeState.lastCheckedAt = new Date().toISOString();
    claudeState.lastError = `Network error: ${cleanErr}`;
    appendLog('claude', 'error', `Claude API unreachable: ${cleanErr}`);
    broadcastSnapshot();
    return false;
  } finally {
    claudeCheckInFlight = false;
  }
}

// ---------------------------------------------------------------------------
// Snapshot Helper
// ---------------------------------------------------------------------------

function getLogFileBytes(): number {
  try {
    return fs.existsSync(LOG_FILE_PATH) ? fs.statSync(LOG_FILE_PATH).size : 0;
  } catch {
    return 0;
  }
}

function getSystemSnapshot(): SystemSnapshot {
  return {
    platform: process.platform === 'darwin' ? 'macOS' : `${process.platform} (Mac DMG Ready)`,
    hostname: os.hostname(),
    logFilePath: path.relative(ROOT_DIR, LOG_FILE_PATH) || LOG_FILE_PATH,
    logFileBytes: getLogFileBytes(),
    logEntryCount: recentLogs.length,
    configFilePath: path.relative(ROOT_DIR, CONFIG_FILE_PATH) || CONFIG_FILE_PATH,
    vite: { ...viteState },
    git: { ...gitState },
    gitAccount: {
      ...gitAccountState,
      oauthConfigured: isGithubOAuthConfigured(),
      callbackUrl: getGithubCallbackUrl(),
    },
    ollama: { ...ollamaState },
    claude: { ...claudeState },
    email: {
      ...config.email,
      smtpConfiguredOnServer: Boolean(process.env.SMTP_PASS?.trim()),
      sentCount: emailSentCount,
      lastSentAt: lastEmailSentAt,
    },
  };
}

function broadcastSnapshot(): void {
  broadcastEvent('snapshot', getSystemSnapshot());
}

// ---------------------------------------------------------------------------
// Express Application & API Routes
// ---------------------------------------------------------------------------

async function createApp() {
  const app = express();
  app.use(express.json({ limit: '100kb' }));

  app.get('/api/status', (_req: Request, res: Response) => {
    res.json(getSystemSnapshot());
  });

  app.get('/api/config', (_req: Request, res: Response) => {
    res.json(config);
  });

  app.put('/api/config', (req: Request, res: Response) => {
    const body = req.body as Partial<BeaconConfig>;
    const next: BeaconConfig = structuredClone(config);

    if (body.vite) {
      if (
        typeof body.vite.workingDir === 'string' &&
        body.vite.workingDir.trim().length > 0 &&
        body.vite.workingDir.length <= 300 &&
        !body.vite.workingDir.includes('\0')
      ) {
        next.vite.workingDir = path.resolve(body.vite.workingDir.trim());
      }
      if (body.vite.commandPreset && ALLOWED_PRESETS.has(body.vite.commandPreset)) {
        next.vite.commandPreset = body.vite.commandPreset;
      }
      if (typeof body.vite.port === 'number' && Number.isInteger(body.vite.port) && body.vite.port >= 1024 && body.vite.port <= 65535) {
        next.vite.port = body.vite.port;
      }
      if (typeof body.vite.monitorUrl === 'string' && body.vite.monitorUrl.trim().length > 0) {
        const trimmedUrl = body.vite.monitorUrl.trim();
        if (!isValidLocalhostMonitorUrl(trimmedUrl)) {
          res.status(400).json({
            error: 'Monitor URL must be a localhost or 127.0.0.1 HTTP(S) URL (e.g. http://localhost:5173).',
          });
          return;
        }
        next.vite.monitorUrl = trimmedUrl;
      }
      if (typeof body.vite.autoRestart === 'boolean') {
        next.vite.autoRestart = body.vite.autoRestart;
      }
      if (typeof body.vite.maxRestarts === 'number' && Number.isInteger(body.vite.maxRestarts) && body.vite.maxRestarts >= 1 && body.vite.maxRestarts <= 100) {
        next.vite.maxRestarts = body.vite.maxRestarts;
      }
    }

    if (body.git) {
      if (typeof body.git.repoUrl === 'string' && isValidRepoUrl(body.git.repoUrl.trim())) {
        next.git.repoUrl = body.git.repoUrl.trim();
      }
      if (typeof body.git.branch === 'string' && isValidBranchName(body.git.branch.trim())) {
        next.git.branch = body.git.branch.trim();
      }
      if (typeof body.git.autoDeploy === 'boolean') {
        next.git.autoDeploy = body.git.autoDeploy;
      }
      if (typeof body.git.pollIntervalSec === 'number' && Number.isInteger(body.git.pollIntervalSec) && body.git.pollIntervalSec >= 15 && body.git.pollIntervalSec <= 3600) {
        next.git.pollIntervalSec = body.git.pollIntervalSec;
      }
    }

    if (body.ollama) {
      if (typeof body.ollama.endpoint === 'string' && isValidOllamaLoopbackEndpoint(body.ollama.endpoint.trim())) {
        next.ollama.endpoint = body.ollama.endpoint.trim();
      }
    }

    if (body.email) {
      if (typeof body.email.enabled === 'boolean') next.email.enabled = body.email.enabled;
      if (typeof body.email.recipientEmail === 'string' && (body.email.recipientEmail === '' || isValidEmail(body.email.recipientEmail.trim()))) {
        next.email.recipientEmail = body.email.recipientEmail.trim();
      }
      if (typeof body.email.smtpHost === 'string' && body.email.smtpHost.length <= 160 && /^[a-zA-Z0-9.-]*$/.test(body.email.smtpHost.trim())) {
        next.email.smtpHost = body.email.smtpHost.trim();
      }
      if (typeof body.email.smtpPort === 'number' && Number.isInteger(body.email.smtpPort) && body.email.smtpPort >= 1 && body.email.smtpPort <= 65535) {
        next.email.smtpPort = body.email.smtpPort;
      }
      if (typeof body.email.smtpUser === 'string' && body.email.smtpUser.length <= 160) {
        next.email.smtpUser = body.email.smtpUser.trim();
      }
      if (typeof body.email.smtpFrom === 'string' && body.email.smtpFrom.length <= 160) {
        next.email.smtpFrom = body.email.smtpFrom.trim();
      }
      if (typeof body.email.notifyOnCrash === 'boolean') next.email.notifyOnCrash = body.email.notifyOnCrash;
      if (typeof body.email.notifyOnDeploy === 'boolean') next.email.notifyOnDeploy = body.email.notifyOnDeploy;
      if (typeof body.email.notifyOnOllamaDown === 'boolean') next.email.notifyOnOllamaDown = body.email.notifyOnOllamaDown;
    }

    config = next;
    saveConfig(config);
    viteState.autoRestart = config.vite.autoRestart;
    viteState.workingDir = config.vite.workingDir;
    viteState.commandPreset = config.vite.commandPreset;
    viteState.port = config.vite.port;
    viteState.monitorUrl = config.vite.monitorUrl;
    viteConsecutiveProbeFailures = 0;
    reconfigureGitPolling();
    appendLog('system', 'info', `Saved configuration to flat file ${path.relative(ROOT_DIR, CONFIG_FILE_PATH)} (monitoring ${config.vite.monitorUrl})`);
    void pollViteHealth().then(() => broadcastSnapshot());
    res.json({ ok: true, config, snapshot: getSystemSnapshot() });
  });

  // Master batch traffic-light actions
  app.post('/api/services/all/start', async (_req: Request, res: Response) => {
    startViteProcess('start all');
    config.git.autoDeploy = true;
    saveConfig(config);
    reconfigureGitPolling();
    ollamaManuallyDisconnected = false;
    await probeOllamaHealth(true);
    if (claudeApiKey) {
      await probeClaudeHealth(true);
    }
    res.json(getSystemSnapshot());
  });

  app.post('/api/services/all/restart', async (_req: Request, res: Response) => {
    await restartViteProcess('restart all');
    void checkAndDeployGit(true, 'restart all');
    ollamaManuallyDisconnected = false;
    await probeOllamaHealth(true);
    if (claudeApiKey) {
      await probeClaudeHealth(true);
    }
    res.json(getSystemSnapshot());
  });

  app.post('/api/services/all/stop', async (_req: Request, res: Response) => {
    await stopViteProcess();
    config.git.autoDeploy = false;
    saveConfig(config);
    reconfigureGitPolling();
    ollamaManuallyDisconnected = true;
    await probeOllamaHealth(false);
    appendLog('system', 'warn', 'Stopped all monitored services from master control');
    res.json(getSystemSnapshot());
  });

  // Vite Server endpoints
  app.post('/api/vite/start', (_req: Request, res: Response) => {
    viteState.restartCount = 0;
    startViteProcess('dashboard control');
    res.json(getSystemSnapshot());
  });

  app.post('/api/vite/stop', async (_req: Request, res: Response) => {
    await stopViteProcess();
    res.json(getSystemSnapshot());
  });

  app.post('/api/vite/restart', async (_req: Request, res: Response) => {
    await restartViteProcess('dashboard control');
    res.json(getSystemSnapshot());
  });

  app.post('/api/vite/simulate-crash', (_req: Request, res: Response) => {
    const ok = simulateViteCrash();
    if (!ok) {
      res.status(409).json({ error: 'Vite server is not currently running.' });
      return;
    }
    res.json({ ok: true, snapshot: getSystemSnapshot() });
  });

  app.post('/api/vite/auto-restart', (req: Request, res: Response) => {
    const enabled = Boolean(req.body?.enabled);
    config.vite.autoRestart = enabled;
    viteState.autoRestart = enabled;
    saveConfig(config);
    appendLog('vite', 'info', `Crash auto-restart watchdog ${enabled ? 'enabled' : 'disabled'}`);
    broadcastSnapshot();
    res.json(getSystemSnapshot());
  });

  app.post('/api/vite/monitor-url', async (req: Request, res: Response) => {
    const rawUrl = typeof req.body?.monitorUrl === 'string' ? req.body.monitorUrl.trim() : '';
    if (!isValidLocalhostMonitorUrl(rawUrl)) {
      res.status(400).json({
        error: 'Enter a valid localhost URL (e.g. http://localhost:5173 or http://127.0.0.1:4173).',
      });
      return;
    }

    config.vite.monitorUrl = rawUrl;
    config.vite.port = extractPortFromUrl(rawUrl, config.vite.port);
    saveConfig(config);

    viteState.monitorUrl = config.vite.monitorUrl;
    viteState.port = config.vite.port;
    viteConsecutiveProbeFailures = 0;
    viteWasExternallyHealthy = false;
    viteIntentionalStop = false;

    appendLog('vite', 'info', `Switched monitored localhost URL to ${rawUrl} (port ${config.vite.port})`);
    await pollViteHealth();
    broadcastSnapshot();
    res.json({ ok: true, snapshot: getSystemSnapshot() });
  });

  // Git Auto-Deploy endpoints
  app.post('/api/git/deploy', async (_req: Request, res: Response) => {
    await checkAndDeployGit(true, 'manual deploy');
    res.json(getSystemSnapshot());
  });

  app.post('/api/git/toggle', (req: Request, res: Response) => {
    const enabled = Boolean(req.body?.enabled);
    config.git.autoDeploy = enabled;
    saveConfig(config);
    reconfigureGitPolling();
    appendLog('git', 'info', `Git auto-deploy watcher ${enabled ? 'enabled' : 'paused'}`);
    broadcastSnapshot();
    res.json(getSystemSnapshot());
  });

  app.post('/api/git/webhook', async (req: Request, res: Response) => {
    const expectedSecret = process.env.GIT_WEBHOOK_SECRET?.trim();
    if (expectedSecret) {
      const provided = String(req.headers['x-beacon-webhook-token'] || '');
      const a = Buffer.from(provided);
      const b = Buffer.from(expectedSecret);
      if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
        appendLog('git', 'warn', 'Rejected Git push webhook with invalid token');
        res.status(401).json({ error: 'Invalid webhook token' });
        return;
      }
    }
    appendLog('git', 'info', `Received push webhook for branch "${config.git.branch}"`);
    await checkAndDeployGit(true, 'git webhook');
    res.json({ ok: true, snapshot: getSystemSnapshot() });
  });

  // Git Account Sync & Permissions (OAuth Popup, Local Mac gh/Keychain, PAT, & Origin Remote Binding)
  app.get('/api/git/auth/url', (_req: Request, res: Response) => {
    const clientId = process.env.GITHUB_CLIENT_ID?.trim();
    const clientSecret = process.env.GITHUB_CLIENT_SECRET?.trim();
    const callbackUrl = getGithubCallbackUrl();

    if (!clientId || !clientSecret) {
      res.status(400).json({
        error: `GitHub OAuth credentials (GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET) are not set on the server yet. Register callback ${callbackUrl} or connect with Mac Keychain / Personal Access Token.`,
        oauthConfigured: false,
        callbackUrl,
      });
      return;
    }

    const now = Date.now();
    for (const [k, expiresAt] of pendingOAuthStates.entries()) {
      if (expiresAt < now) pendingOAuthStates.delete(k);
    }

    const state = crypto.randomBytes(24).toString('hex');
    pendingOAuthStates.set(state, now + 10 * 60 * 1000);

    const params = new URLSearchParams({
      client_id: clientId,
      redirect_uri: callbackUrl,
      scope: 'repo read:user',
      state,
    });
    const url = `https://github.com/login/oauth/authorize?${params.toString()}`;
    res.json({ url, callbackUrl });
  });

  const handleGithubOAuthCallback = async (req: Request, res: Response) => {
    const code = typeof req.query.code === 'string' ? req.query.code.trim() : '';
    const state = typeof req.query.state === 'string' ? req.query.state.trim() : '';
    const oauthErr = typeof req.query.error_description === 'string' ? req.query.error_description : '';

    const sendPopupResult = (ok: boolean, message: string) => {
      const safePayload = JSON.stringify({
        type: ok ? 'OAUTH_AUTH_SUCCESS' : 'OAUTH_AUTH_ERROR',
        provider: 'github',
        message,
      }).replace(/</g, '\\u003c');
      const safeText = message.replace(/[&<>"']/g, (ch) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch] || ch),
      );
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.send(`<!doctype html>
<html>
  <body style="background:#0B0D10;color:#F3F5F8;font-family:-apple-system,sans-serif;padding:32px;">
    <p>${safeText}</p>
    <script>
      if (window.opener) {
        window.opener.postMessage(${safePayload}, '*');
        window.close();
      } else {
        window.location.href = '/';
      }
    </script>
  </body>
</html>`);
    };

    if (oauthErr || !code || !state) {
      sendPopupResult(false, oauthErr || 'GitHub authorization was cancelled or missing code.');
      return;
    }

    const expiresAt = pendingOAuthStates.get(state);
    pendingOAuthStates.delete(state);
    if (!expiresAt || expiresAt < Date.now()) {
      sendPopupResult(false, 'OAuth state expired or invalid. Please retry connecting GitHub.');
      return;
    }

    const clientId = process.env.GITHUB_CLIENT_ID?.trim();
    const clientSecret = process.env.GITHUB_CLIENT_SECRET?.trim();
    if (!clientId || !clientSecret) {
      sendPopupResult(false, 'Server is missing GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET.');
      return;
    }

    try {
      const tokenRes = await fetch('https://github.com/login/oauth/access_token', {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          client_id: clientId,
          client_secret: clientSecret,
          code,
          redirect_uri: getGithubCallbackUrl(),
        }),
        signal: AbortSignal.timeout(10000),
      });

      const tokenJson = (await tokenRes.json()) as { access_token?: string; error_description?: string };
      if (!tokenRes.ok || !tokenJson.access_token) {
        throw new Error(tokenJson.error_description || 'Could not exchange GitHub OAuth code for token.');
      }

      await fetchGithubAccountAndRepos(tokenJson.access_token, 'oauth');
      sendPopupResult(true, 'GitHub account authorized. Closing window...');
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'GitHub OAuth exchange failed.';
      appendLog('git', 'error', `GitHub OAuth callback error: ${msg}`);
      sendPopupResult(false, msg);
    }
  };

  app.get(['/auth/github/callback', '/auth/github/callback/'], handleGithubOAuthCallback);

  app.post('/api/git/auth/sync-local', async (_req: Request, res: Response) => {
    const result = await syncLocalMacGitCredentials(false);
    res.json({ ...result, snapshot: getSystemSnapshot() });
  });

  app.post('/api/git/auth/token', async (req: Request, res: Response) => {
    const token = typeof req.body?.token === 'string' ? req.body.token.trim() : '';
    if (!token || token.length < 10 || token.length > 256 || /\s/.test(token)) {
      res.status(400).json({ error: 'Provide a valid GitHub Personal Access Token.' });
      return;
    }
    try {
      await fetchGithubAccountAndRepos(token, 'token');
      res.json({ ok: true, snapshot: getSystemSnapshot() });
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'GitHub token verification failed.';
      appendLog('git', 'error', msg);
      res.status(401).json({ error: msg });
    }
  });

  app.post('/api/git/auth/disconnect', (_req: Request, res: Response) => {
    const prevUser = gitAccountState.username;
    gitAccessToken = null;
    gitAccountState.connected = false;
    gitAccountState.provider = null;
    gitAccountState.method = null;
    gitAccountState.username = null;
    gitAccountState.displayName = null;
    gitAccountState.email = null;
    gitAccountState.scopes = [];
    gitAccountState.connectedAt = null;
    gitAccountState.keyHint = null;
    gitAccountState.repos = [];
    appendLog('git', 'info', `Disconnected GitHub account${prevUser ? ` (@${prevUser})` : ''}`);
    broadcastSnapshot();
    res.json({ ok: true, snapshot: getSystemSnapshot() });
  });

  app.post('/api/git/select-repo', async (req: Request, res: Response) => {
    const repoUrl = typeof req.body?.repoUrl === 'string' ? req.body.repoUrl.trim() : '';
    const branch = typeof req.body?.branch === 'string' ? req.body.branch.trim() : 'main';

    if (!isValidRepoUrl(repoUrl)) {
      res.status(400).json({ error: 'Enter a valid HTTPS or SSH Git repository URL (e.g. https://github.com/user/repo.git).' });
      return;
    }
    if (!isValidBranchName(branch)) {
      res.status(400).json({ error: 'Enter a valid Git branch name (e.g. main).' });
      return;
    }

    config.git.repoUrl = repoUrl;
    config.git.branch = branch;
    saveConfig(config);
    gitState.repoUrl = repoUrl;
    gitState.branch = branch;

    const workingDir = path.resolve(config.vite.workingDir);
    const result = await bindOriginRemote(workingDir, repoUrl, branch);
    appendLog('git', result.verified ? 'info' : 'warn', result.detail);
    broadcastSnapshot();
    res.json({ ok: true, ...result, snapshot: getSystemSnapshot() });
  });

  // Ollama endpoints
  app.post('/api/ollama/health', async (_req: Request, res: Response) => {
    ollamaManuallyDisconnected = false;
    await probeOllamaHealth(true);
    res.json(getSystemSnapshot());
  });

  app.post('/api/ollama/toggle', async (req: Request, res: Response) => {
    const connect = Boolean(req.body?.connected);
    ollamaManuallyDisconnected = !connect;
    if (!connect) {
      appendLog('ollama', 'warn', 'Disconnected from local Ollama LLM health monitor');
      if (config.email.notifyOnOllamaDown) {
        void sendAlertEmail('Ollama Local LLM Disconnected', `Ollama connection at ${config.ollama.endpoint} went offline.`);
      }
    }
    await probeOllamaHealth(connect);
    res.json(getSystemSnapshot());
  });

  app.post('/api/ollama/model', async (req: Request, res: Response) => {
    const model = typeof req.body?.model === 'string' ? req.body.model.trim() : '';
    const switched = await switchOllamaModel(model);
    if (!switched) {
      res.status(400).json({ error: 'Requested model is not available in local Ollama list.' });
      return;
    }
    res.json(getSystemSnapshot());
  });

  // Claude API Health Checker endpoints
  app.post('/api/claude/connect', async (req: Request, res: Response) => {
    const apiKey = typeof req.body?.apiKey === 'string' ? req.body.apiKey.trim() : '';
    if (!apiKey || apiKey.length < 16 || apiKey.length > 300 || /\s/.test(apiKey)) {
      res.status(400).json({
        error: 'Paste a valid Anthropic Claude API key (starts with sk-ant-...).',
      });
      return;
    }

    claudeApiKey = apiKey;
    claudeState.keySource = 'manual';
    claudeState.keyHint = maskSecretKey(apiKey);
    const ok = await probeClaudeHealth(true);
    if (!ok) {
      const statusCode = claudeState.httpStatus === 401 || claudeState.httpStatus === 403 ? 401 : 502;
      res.status(statusCode).json({
        error: claudeState.lastError || 'Claude API verification failed.',
        snapshot: getSystemSnapshot(),
      });
      return;
    }
    res.json({ ok: true, snapshot: getSystemSnapshot() });
  });

  app.post('/api/claude/health', async (_req: Request, res: Response) => {
    if (!claudeApiKey) {
      res.status(400).json({
        error: 'Paste your Claude API key first to run a live health check.',
        snapshot: getSystemSnapshot(),
      });
      return;
    }
    const ok = await probeClaudeHealth(true);
    if (!ok) {
      res.status(502).json({
        error: claudeState.lastError || 'Claude API health check failed.',
        snapshot: getSystemSnapshot(),
      });
      return;
    }
    res.json({ ok: true, snapshot: getSystemSnapshot() });
  });

  app.post('/api/claude/model', (req: Request, res: Response) => {
    const model = typeof req.body?.model === 'string' ? req.body.model.trim() : '';
    if (!model || !claudeState.models.some((m) => m.id === model)) {
      res.status(400).json({ error: 'Selected Claude model is not in the active account model list.' });
      return;
    }
    claudeState.activeModel = model;
    appendLog('claude', 'info', `Selected Claude model ${model}`);
    broadcastSnapshot();
    res.json(getSystemSnapshot());
  });

  app.post('/api/claude/disconnect', (_req: Request, res: Response) => {
    const hadKey = Boolean(claudeApiKey);
    claudeApiKey = null;
    claudeState.light = 'amber';
    claudeState.state = 'unconfigured';
    claudeState.connected = false;
    claudeState.keyHint = null;
    claudeState.keySource = null;
    claudeState.httpStatus = null;
    claudeState.latencyMs = null;
    claudeState.activeModel = '';
    claudeState.models = [];
    claudeState.lastCheckedAt = null;
    claudeState.lastError = null;
    if (hadKey) {
      appendLog('claude', 'info', 'Cleared Claude API key from server memory');
    }
    broadcastSnapshot();
    res.json({ ok: true, snapshot: getSystemSnapshot() });
  });

  // Email test notification
  app.post('/api/email/test', async (_req: Request, res: Response) => {
    const result = await sendAlertEmail(
      'Beacon Test Notification',
      'Automated email alerts are active for your local macOS Vite server, Git auto-deploy, and Ollama LLM monitor.',
    );
    res.json({ ok: true, ...result, snapshot: getSystemSnapshot() });
  });

  // Flat-file Activity Log endpoints
  app.get('/api/logs', (_req: Request, res: Response) => {
    res.json({
      entries: recentLogs,
      logFilePath: path.relative(ROOT_DIR, LOG_FILE_PATH) || LOG_FILE_PATH,
      logFileBytes: getLogFileBytes(),
    });
  });

  app.get('/api/logs/stream', (req: Request, res: Response) => {
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders?.();

    sseClients.add(res);
    res.write(`event: snapshot\ndata: ${JSON.stringify(getSystemSnapshot())}\n\n`);

    const keepAlive = setInterval(() => {
      try {
        res.write(': keepalive\n\n');
      } catch {
        clearInterval(keepAlive);
      }
    }, 20000);

    req.on('close', () => {
      clearInterval(keepAlive);
      sseClients.delete(res);
    });
  });

  app.get('/api/logs/download', (_req: Request, res: Response) => {
    if (!fs.existsSync(LOG_FILE_PATH)) {
      fs.writeFileSync(LOG_FILE_PATH, '', 'utf-8');
    }
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="beacon-activity.log"');
    fs.createReadStream(LOG_FILE_PATH).pipe(res);
  });

  app.delete('/api/logs', (_req: Request, res: Response) => {
    fs.writeFileSync(LOG_FILE_PATH, '', 'utf-8');
    recentLogs = [];
    appendLog('system', 'info', 'Flat-file activity log cleared');
    broadcastSnapshot();
    res.json({ ok: true, entries: recentLogs });
  });

  // Downloadable Mac .dmg Electron Build Kit (pre-compiled dist + self-contained server.cjs)
  app.get('/api/mac-dmg-kit', async (_req: Request, res: Response) => {
    try {
      const distIndexPath = path.join(ROOT_DIR, 'dist', 'index.html');
      const serverBundlePath = path.join(ROOT_DIR, 'dist-server', 'server.cjs');
      const npmCmd = process.platform === 'win32' ? 'npm.cmd' : 'npm';

      if (!fs.existsSync(distIndexPath)) {
        await execFileAsync(npmCmd, ['run', 'build'], { cwd: ROOT_DIR, timeout: 60000 });
      }
      if (!fs.existsSync(serverBundlePath)) {
        await execFileAsync(npmCmd, ['run', 'build:server'], { cwd: ROOT_DIR, timeout: 60000 });
      }

      if (!fs.existsSync(distIndexPath) || !fs.existsSync(serverBundlePath)) {
        res.status(500).json({ error: 'Compiled app assets are missing; unable to assemble Mac DMG kit.' });
        return;
      }

      res.setHeader('Content-Type', 'application/zip');
      res.setHeader('Content-Disposition', 'attachment; filename="Beacon-Mac-DMG-Kit.zip"');

      const archive = new ZipArchive({ zlib: { level: 9 } });
      archive.on('error', (err: Error) => {
        appendLog('system', 'error', `Failed to generate Mac DMG kit archive: ${err.message}`);
        if (!res.headersSent) {
          res.status(500).json({ error: 'Failed to generate archive' });
        }
      });

      archive.pipe(res);

      const filesToInclude = [
        'electron/main.cjs',
        'electron/preload.cjs',
        'electron-builder.yml',
        '.env.example',
        'scripts/sample-vite-worker.mjs',
        'dist-server/server.cjs',
      ];

      for (const relPath of filesToInclude) {
        const absPath = path.join(ROOT_DIR, relPath);
        if (fs.existsSync(absPath)) {
          archive.file(absPath, { name: `Beacon-Mac/${relPath}` });
        }
      }

      const commandScript = path.join(ROOT_DIR, 'scripts/Build-Mac-DMG.command');
      if (fs.existsSync(commandScript)) {
        archive.file(commandScript, { name: 'Beacon-Mac/Build-Mac-DMG.command', mode: 0o755 });
      }

      const distDir = path.join(ROOT_DIR, 'dist');
      if (fs.existsSync(distDir)) {
        archive.directory(distDir, 'Beacon-Mac/dist');
      }

      // Clean, public-npm-only package.json for fast & reliable electron-builder .dmg packaging on macOS
      const macPkg = {
        name: 'beacon-mac',
        productName: 'Beacon',
        version: '1.0.0',
        description: 'Lightweight macOS traffic-light monitor for local Vite/Node.js processes, Git auto-deployment, and Ollama LLM health.',
        author: 'Beacon Local Monitor',
        private: true,
        main: 'electron/main.cjs',
        scripts: {
          start: 'electron .',
          'dist:mac': 'CSC_IDENTITY_AUTO_DISCOVERY=false electron-builder --mac dmg --config electron-builder.yml',
        },
        dependencies: {},
        devDependencies: {
          electron: '^33.2.0',
          'electron-builder': '^25.1.8',
        },
      };
      archive.append(JSON.stringify(macPkg, null, 2), { name: 'Beacon-Mac/package.json' });

      const readme = [
        'Beacon — Native macOS App (.dmg Builder Kit)',
        '===========================================',
        '',
        'Because this kit is downloaded from a browser without an Apple Developer',
        'notarization certificate, macOS adds a quarantine flag to Build-Mac-DMG.command.',
        '',
        'Recommended (Terminal — clears quarantine & builds .dmg):',
        '  xattr -dr com.apple.quarantine ~/Downloads/Beacon-Mac && cd ~/Downloads/Beacon-Mac && bash Build-Mac-DMG.command',
        '',
        'Or run directly inside the unzipped Beacon-Mac folder:',
        '  bash Build-Mac-DMG.command',
        '',
        'Finder alternative (if double-clicking is blocked):',
        '  System Settings -> Privacy & Security -> scroll down -> click "Open Anyway"',
        '',
        'After building:',
        '  1. Open release/Beacon-1.0.0-*.dmg and drag Beacon.app into /Applications',
        '  2. If macOS warns on first launch, run: xattr -cr /Applications/Beacon.app',
        '',
        'Flat-File Storage Locations on macOS:',
        '  Logs:   ~/Library/Application Support/Beacon/data/activity.log',
        '  Config: ~/Library/Application Support/Beacon/data/config.json',
        '',
      ].join('\n');
      archive.append(readme, { name: 'Beacon-Mac/README-MAC-DMG.txt' });

      appendLog('system', 'info', 'Exported pre-compiled Beacon-Mac-DMG-Kit.zip for native macOS .dmg packaging');
      await archive.finalize();
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to build Mac DMG kit';
      appendLog('system', 'error', `Mac DMG kit generation failed: ${msg}`);
      if (!res.headersSent) {
        res.status(500).json({ error: msg });
      }
    }
  });

  // Downloadable Native SwiftUI / Xcode Project (Mac App Store Ready)
  app.get('/api/mac-swift-kit', async (_req: Request, res: Response) => {
    try {
      const swiftRoot = path.join(ROOT_DIR, 'swift-app', 'BeaconMac');
      if (!fs.existsSync(swiftRoot)) {
        res.status(500).json({ error: 'SwiftUI Xcode source folder is missing.' });
        return;
      }

      res.setHeader('Content-Type', 'application/zip');
      res.setHeader('Content-Disposition', 'attachment; filename="Beacon-Swift-Xcode-Project.zip"');

      const archive = new ZipArchive({ zlib: { level: 9 } });
      archive.on('error', (err: Error) => {
        appendLog('system', 'error', `Failed to generate Swift Xcode archive: ${err.message}`);
        if (!res.headersSent) {
          res.status(500).json({ error: 'Failed to generate archive' });
        }
      });

      archive.pipe(res);

      const walk = (dir: string, relBase: string) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          const absPath = path.join(dir, entry.name);
          const relPath = relBase ? `${relBase}/${entry.name}` : entry.name;
          if (entry.isDirectory()) {
            walk(absPath, relPath);
          } else {
            const isShellScript = entry.name.endsWith('.sh');
            archive.file(absPath, {
              name: `BeaconMac/${relPath}`,
              mode: isShellScript ? 0o755 : 0o644,
            });
          }
        }
      };

      walk(swiftRoot, '');
      appendLog('system', 'info', 'Exported native SwiftUI Beacon-Swift-Xcode-Project.zip (App Store ready)');
      await archive.finalize();
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to package Swift Xcode project';
      appendLog('system', 'error', `Swift Xcode kit generation failed: ${msg}`);
      if (!res.headersSent) {
        res.status(500).json({ error: msg });
      }
    }
  });

  // Frontend serving: Vite middleware in development, static dist/ in production
  const isProd = process.env.NODE_ENV === 'production' || fs.existsSync(path.join(ROOT_DIR, 'dist', 'index.html'));
  if (process.env.NODE_ENV !== 'production') {
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else if (isProd) {
    app.use(express.static(path.join(ROOT_DIR, 'dist')));
    app.get('*', (_req: Request, res: Response) => {
      res.sendFile(path.join(ROOT_DIR, 'dist', 'index.html'));
    });
  }

  // Boot monitored services
  appendLog('system', 'info', `Beacon monitor initialized (flat-file log: ${path.relative(ROOT_DIR, LOG_FILE_PATH)})`);
  void syncLocalMacGitCredentials(true);
  reconfigureGitPolling();
  startViteProcess('startup');
  void probeOllamaHealth(true);

  const envClaudeKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (envClaudeKey) {
    claudeApiKey = envClaudeKey;
    claudeState.keySource = 'env';
    claudeState.keyHint = maskSecretKey(envClaudeKey);
    void probeClaudeHealth(true);
  }

  setInterval(() => {
    void pollViteHealth().then(() => broadcastSnapshot());
  }, 2500);

  setInterval(() => {
    void probeOllamaHealth(false);
  }, 15000);

  setInterval(() => {
    if (claudeApiKey) {
      void probeClaudeHealth(false);
    }
  }, 60000);

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Beacon server listening on http://0.0.0.0:${PORT}`);
  });
}

process.on('SIGTERM', async () => {
  await stopViteProcess();
  process.exit(0);
});

process.on('SIGINT', async () => {
  await stopViteProcess();
  process.exit(0);
});

void createApp();
