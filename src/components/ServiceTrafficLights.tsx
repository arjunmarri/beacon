import {
  Activity,
  GitBranch,
  Globe,
  KeyRound,
  Play,
  Power,
  RefreshCw,
  RotateCcw,
  ShieldCheck,
  Square,
  Trash2,
  Zap,
} from 'lucide-react';
import { useEffect, useState } from 'react';
import type { SystemSnapshot } from '../types.ts';
import { TrafficLightLamp } from './TrafficLightLamp.tsx';

interface ServiceTrafficLightsProps {
  snapshot: SystemSnapshot;
  busyAction: string | null;
  onAction: (actionKey: string, endpoint: string, body?: Record<string, unknown>) => Promise<boolean>;
  onOpenGitAuth: () => void;
}

function formatUptime(seconds: number): string {
  if (seconds <= 0) return '0s';
  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  if (hrs > 0) return `${hrs}h ${String(mins).padStart(2, '0')}m`;
  if (mins > 0) return `${mins}m ${String(secs).padStart(2, '0')}s`;
  return `${secs}s`;
}

function formatShortTime(iso: string | null): string {
  if (!iso) return 'Never';
  const date = new Date(iso);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

function getClaudeLabel(state: SystemSnapshot['claude']['state']): string {
  if (state === 'unconfigured') return 'No Key';
  if (state === 'checking') return 'Checking';
  if (state === 'connected') return 'Healthy';
  return 'Error';
}

export function ServiceTrafficLights({
  snapshot,
  busyAction,
  onAction,
  onOpenGitAuth,
}: ServiceTrafficLightsProps) {
  const { vite, git, gitAccount, ollama, claude } = snapshot;
  const isViteRunning = vite.state === 'running';
  const isOllamaConnected = ollama.state === 'connected';
  const hasClaudeKey = Boolean(claude.keyHint);

  const [monitorUrlInput, setMonitorUrlInput] = useState(vite.monitorUrl);
  const [gitKeyInput, setGitKeyInput] = useState('');
  const [editingGitKey, setEditingGitKey] = useState(false);
  const [claudeKeyInput, setClaudeKeyInput] = useState('');
  const [editingClaudeKey, setEditingClaudeKey] = useState(false);

  useEffect(() => {
    setMonitorUrlInput(vite.monitorUrl);
  }, [vite.monitorUrl]);

  function handleMonitorUrlSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = monitorUrlInput.trim();
    if (!trimmed) return;
    void onAction('vite-monitor-url', '/api/vite/monitor-url', { monitorUrl: trimmed });
  }

  async function handleGitKeySubmit(e: React.FormEvent) {
    e.preventDefault();
    const token = gitKeyInput.trim();
    if (!token) return;
    const ok = await onAction('git-inline-token', '/api/git/auth/token', { token });
    if (ok) {
      setGitKeyInput('');
      setEditingGitKey(false);
    }
  }

  async function handleClaudeKeySubmit(e: React.FormEvent) {
    e.preventDefault();
    const apiKey = claudeKeyInput.trim();
    if (!apiKey) return;
    const ok = await onAction('claude-connect', '/api/claude/connect', { apiKey });
    setClaudeKeyInput('');
    if (ok) {
      setEditingClaudeKey(false);
    }
  }

  return (
    <section id="services" aria-label="Core traffic light services" className="space-y-4">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-[#F3F5F8] text-balance">
            Local Service Control
          </h1>
          <p className="text-xs sm:text-sm text-[#9BA3B0] mt-0.5">
            {snapshot.platform}
            <span aria-hidden="true" className="mx-2 text-white/20">·</span>
            <span className="font-mono text-xs text-[#9BA3B0]">{snapshot.hostname}</span>
            <span aria-hidden="true" className="mx-2 text-white/20">·</span>
            Flat-file logging active
          </p>
        </div>

        <div className="flex items-center gap-2 shrink-0">
          <button
            type="button"
            disabled={busyAction !== null}
            onClick={() => void onAction('all-start', '/api/services/all/start')}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#161A20] hover:bg-[#1D222B] border border-white/[0.09] rounded-lg transition-colors whitespace-nowrap shrink-0 disabled:opacity-50 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400"
          >
            <Play className="w-3.5 h-3.5 text-emerald-400" />
            Start All
          </button>
          <button
            type="button"
            disabled={busyAction !== null}
            onClick={() => void onAction('all-restart', '/api/services/all/restart')}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#161A20] hover:bg-[#1D222B] border border-white/[0.09] rounded-lg transition-colors whitespace-nowrap shrink-0 disabled:opacity-50 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400"
          >
            <RotateCcw className="w-3.5 h-3.5 text-amber-400" />
            Restart All
          </button>
          <button
            type="button"
            disabled={busyAction !== null}
            onClick={() => void onAction('all-stop', '/api/services/all/stop')}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#161A20] hover:bg-[#1D222B] border border-white/[0.09] rounded-lg transition-colors whitespace-nowrap shrink-0 disabled:opacity-50 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400"
          >
            <Square className="w-3.5 h-3.5 text-rose-400" />
            Stop All
          </button>
        </div>
      </div>

      {/* Balanced 2x2 Traffic Light Panels */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 items-stretch">
        {/* 1. Vite / Node.js Process Watchdog */}
        <article className="bg-[#13161B] border border-white/[0.08] rounded-xl p-5 flex flex-col justify-between gap-5">
          <div className="space-y-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <h2 className="text-base font-semibold text-[#F3F5F8] truncate">
                  Vite / Node.js Server
                </h2>
                <p className="text-xs text-[#9BA3B0] font-mono truncate mt-0.5" title={vite.monitorUrl}>
                  :{vite.port} · {vite.commandPreset}
                </p>
              </div>
              <TrafficLightLamp active={vite.light} label={capitalize(vite.state)} />
            </div>

            {/* Inline Localhost URL Selector for multi-port monitoring */}
            <form onSubmit={handleMonitorUrlSubmit} className="space-y-1.5">
              <label htmlFor="vite-monitor-url-inline" className="block text-xs text-[#9BA3B0]">
                Localhost URL to monitor
              </label>
              <div className="flex items-center gap-1.5">
                <div className="relative flex-1 min-w-0">
                  <Globe className="w-3.5 h-3.5 text-[#7B8494] absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                  <input
                    id="vite-monitor-url-inline"
                    type="url"
                    value={monitorUrlInput}
                    onChange={(e) => setMonitorUrlInput(e.target.value)}
                    placeholder="http://localhost:5173"
                    className="w-full pl-8 pr-2.5 py-1.5 text-xs font-mono text-[#F3F5F8] placeholder:text-[#6B7280] bg-[#0B0D10] border border-white/[0.12] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400"
                  />
                </div>
                <button
                  type="submit"
                  disabled={busyAction !== null || !monitorUrlInput.trim()}
                  className="px-3 py-1.5 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.1] rounded-lg transition-colors whitespace-nowrap shrink-0 cursor-pointer disabled:opacity-50"
                >
                  {busyAction === 'vite-monitor-url' ? 'Probing...' : 'Monitor'}
                </button>
              </div>
            </form>

            <dl className="grid grid-cols-2 gap-x-4 gap-y-3 pt-3 border-t border-white/[0.07] text-xs">
              <div>
                <dt className="text-[#7B8494]">HTTP Probe</dt>
                <dd className="font-mono tabular-nums text-sm mt-0.5 truncate">
                  {vite.probeHealthy && vite.httpStatus ? (
                    <span className="text-emerald-400">
                      {vite.httpStatus} · {vite.responseTimeMs ?? 1} ms
                    </span>
                  ) : (
                    <span className="text-rose-400">Unreachable</span>
                  )}
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Process ID</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {vite.pid ? `#${vite.pid}` : vite.probeHealthy ? 'External' : '—'}
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Uptime / RSS</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {formatUptime(vite.uptimeSeconds)} · {vite.memoryMb.toFixed(0)} MB
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Auto-Restarts</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {vite.restartCount}
                </dd>
              </div>
            </dl>
          </div>

          <div className="space-y-3 pt-3 border-t border-white/[0.07]">
            <label className="flex items-center justify-between gap-3 cursor-pointer select-none">
              <span className="text-xs text-[#9BA3B0]">Auto-restart on crash</span>
              <button
                type="button"
                role="switch"
                aria-checked={vite.autoRestart}
                onClick={() =>
                  void onAction('vite-autorestart', '/api/vite/auto-restart', { enabled: !vite.autoRestart })
                }
                className={`relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400 ${
                  vite.autoRestart ? 'bg-emerald-500/80' : 'bg-white/15'
                }`}
              >
                <span
                  className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white transition-transform duration-150 ${
                    vite.autoRestart ? 'translate-x-4.5' : 'translate-x-1'
                  }`}
                />
              </button>
            </label>

            <div className="flex flex-wrap items-center gap-2">
              {isViteRunning ? (
                <button
                  type="button"
                  disabled={busyAction !== null}
                  onClick={() => void onAction('vite-stop', '/api/vite/stop')}
                  className="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
                >
                  <Square className="w-3.5 h-3.5 text-rose-400" />
                  Stop
                </button>
              ) : (
                <button
                  type="button"
                  disabled={busyAction !== null}
                  onClick={() => void onAction('vite-start', '/api/vite/start')}
                  className="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-[#0B0D10] bg-[#38BDF8] hover:bg-[#7DD3FC] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
                >
                  <Play className="w-3.5 h-3.5" />
                  Start
                </button>
              )}

              <button
                type="button"
                disabled={busyAction !== null}
                onClick={() => void onAction('vite-restart', '/api/vite/restart')}
                className="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
              >
                <RotateCcw className="w-3.5 h-3.5" />
                Restart
              </button>

              <button
                type="button"
                disabled={!isViteRunning || !vite.pid || busyAction !== null}
                onClick={() => void onAction('vite-crash', '/api/vite/simulate-crash')}
                title="Kill the managed worker process to verify automatic crash detection and restart"
                className="inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-amber-300 bg-amber-500/10 hover:bg-amber-500/20 border border-amber-500/20 rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-40"
              >
                <Zap className="w-3.5 h-3.5" />
                Test Crash
              </button>
            </div>
          </div>
        </article>

        {/* 2. Git Auto-Deploy Watcher & Direct Key Paste */}
        <article className="bg-[#13161B] border border-white/[0.08] rounded-xl p-5 flex flex-col justify-between gap-5">
          <div className="space-y-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <h2 className="text-base font-semibold text-[#F3F5F8] truncate">
                  Git Auto-Deploy
                </h2>
                <p className="text-xs text-[#9BA3B0] font-mono truncate mt-0.5" title={git.repoUrl}>
                  {git.branch} · {git.commitHash}
                  {gitAccount.connected && gitAccount.username ? ` · @${gitAccount.username}` : ''}
                </p>
              </div>
              <TrafficLightLamp active={git.light} label={capitalize(git.state)} />
            </div>

            {/* Inline Git Key / Personal Access Token Paste */}
            {gitAccount.connected && !editingGitKey ? (
              <div className="space-y-1.5">
                <span className="block text-xs text-[#9BA3B0]">Git key (runtime memory only)</span>
                <div className="flex items-center justify-between gap-2 px-3 py-1.5 bg-[#0B0D10] border border-white/[0.1] rounded-lg">
                  <div className="flex items-center gap-2 min-w-0">
                    <KeyRound className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
                    <span className="text-xs font-mono text-[#D4D9E2] truncate">
                      {gitAccount.keyHint || `@${gitAccount.username}`}
                    </span>
                  </div>
                  <button
                    type="button"
                    onClick={() => setEditingGitKey(true)}
                    className="text-xs font-medium text-sky-400 hover:text-sky-300 whitespace-nowrap shrink-0 cursor-pointer"
                  >
                    Replace Key
                  </button>
                </div>
              </div>
            ) : (
              <form onSubmit={(e) => void handleGitKeySubmit(e)} className="space-y-1.5">
                <label htmlFor="git-key-inline" className="block text-xs text-[#9BA3B0]">
                  Paste Git key / token (held in memory only)
                </label>
                <div className="flex items-center gap-1.5">
                  <div className="relative flex-1 min-w-0">
                    <KeyRound className="w-3.5 h-3.5 text-[#7B8494] absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input
                      id="git-key-inline"
                      type="password"
                      autoComplete="off"
                      spellCheck={false}
                      value={gitKeyInput}
                      onChange={(e) => setGitKeyInput(e.target.value)}
                      placeholder="ghp_... or github_pat_..."
                      className="w-full pl-8 pr-2.5 py-1.5 text-xs font-mono text-[#F3F5F8] placeholder:text-[#6B7280] bg-[#0B0D10] border border-white/[0.12] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400"
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={busyAction !== null || !gitKeyInput.trim()}
                    className="px-3 py-1.5 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.1] rounded-lg transition-colors whitespace-nowrap shrink-0 cursor-pointer disabled:opacity-50"
                  >
                    {busyAction === 'git-inline-token' ? 'Verifying...' : 'Connect'}
                  </button>
                  {editingGitKey && (
                    <button
                      type="button"
                      onClick={() => {
                        setEditingGitKey(false);
                        setGitKeyInput('');
                      }}
                      className="px-2.5 py-1.5 text-xs text-[#9BA3B0] hover:text-[#F3F5F8] whitespace-nowrap shrink-0 cursor-pointer"
                    >
                      Cancel
                    </button>
                  )}
                </div>
              </form>
            )}

            <dl className="grid grid-cols-2 gap-x-4 gap-y-3 pt-3 border-t border-white/[0.07] text-xs">
              <div>
                <dt className="text-[#7B8494]">Last Deploy</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {formatShortTime(git.lastDeployedAt)}
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Git Account</dt>
                <dd className="font-mono text-sm mt-0.5 truncate">
                  {gitAccount.connected ? (
                    <span className="text-emerald-400">@{gitAccount.username}</span>
                  ) : (
                    <span className="text-amber-400">Not synced</span>
                  )}
                </dd>
              </div>
              <div className="col-span-2">
                <dt className="text-[#7B8494]">
                  {git.lastError ? 'Last Sync Issue' : 'Latest Commit'}
                </dt>
                <dd
                  className={`text-xs mt-1 truncate ${
                    git.lastError ? 'text-rose-300' : 'text-[#D4D9E2]'
                  }`}
                  title={git.lastError || git.commitMessage}
                >
                  {git.lastError || git.commitMessage}
                </dd>
              </div>
            </dl>
          </div>

          <div className="space-y-3 pt-3 border-t border-white/[0.07]">
            <div className="flex items-center justify-between gap-3">
              <span className="text-xs text-[#9BA3B0]">
                Auto-pull every {git.pollIntervalSec}s
              </span>
              <button
                type="button"
                role="switch"
                aria-checked={git.autoDeploy}
                onClick={() =>
                  void onAction('git-toggle', '/api/git/toggle', { enabled: !git.autoDeploy })
                }
                className={`relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400 ${
                  git.autoDeploy ? 'bg-emerald-500/80' : 'bg-white/15'
                }`}
              >
                <span
                  className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white transition-transform duration-150 ${
                    git.autoDeploy ? 'translate-x-4.5' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>

            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                disabled={busyAction !== null}
                onClick={() => void onAction('git-deploy', '/api/git/deploy')}
                className="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-[#0B0D10] bg-[#38BDF8] hover:bg-[#7DD3FC] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${busyAction === 'git-deploy' ? 'animate-spin' : ''}`} />
                Pull &amp; Redeploy
              </button>

              <button
                type="button"
                onClick={onOpenGitAuth}
                className={`inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium rounded-lg border transition-colors whitespace-nowrap cursor-pointer ${
                  gitAccount.connected
                    ? 'text-emerald-300 bg-emerald-500/10 hover:bg-emerald-500/20 border-emerald-500/25'
                    : 'text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border-white/[0.1]'
                }`}
              >
                <ShieldCheck className="w-3.5 h-3.5" />
                {gitAccount.connected ? 'Repos & Scopes' : 'Git Permissions'}
              </button>

              <button
                type="button"
                disabled={busyAction !== null}
                onClick={() => void onAction('git-webhook', '/api/git/webhook')}
                title="Trigger Git push webhook manually"
                className="inline-flex items-center justify-center p-2 text-xs font-medium text-[#9BA3B0] hover:text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors shrink-0 cursor-pointer disabled:opacity-50"
              >
                <GitBranch className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        </article>

        {/* 3. Local LLM (Ollama) Health & Model Switcher */}
        <article className="bg-[#13161B] border border-white/[0.08] rounded-xl p-5 flex flex-col justify-between gap-5">
          <div className="space-y-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <h2 className="text-base font-semibold text-[#F3F5F8] truncate">
                  Local LLM (Ollama)
                </h2>
                <p className="text-xs text-[#9BA3B0] font-mono truncate mt-0.5">
                  {ollama.connectedMode === 'live' ? 'Live macOS daemon' : 'Local preview'} · 11434
                </p>
              </div>
              <TrafficLightLamp active={ollama.light} label={capitalize(ollama.state)} />
            </div>

            <dl className="grid grid-cols-2 gap-x-4 gap-y-3 pt-3 border-t border-white/[0.07] text-xs">
              <div>
                <dt className="text-[#7B8494]">Latency</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {isOllamaConnected ? `${ollama.latencyMs} ms` : '—'}
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Throughput</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {isOllamaConnected ? `${ollama.tokensPerSec} tok/s` : '—'}
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Memory / VRAM</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {isOllamaConnected
                    ? `${ollama.vramUsedGb.toFixed(1)} / ${ollama.vramTotalGb.toFixed(0)} GB`
                    : '0.0 GB'}
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Context Window</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {isOllamaConnected ? ollama.contextLength.toLocaleString() : '—'}
                </dd>
              </div>
            </dl>
          </div>

          <div className="space-y-3 pt-3 border-t border-white/[0.07]">
            <div>
              <label htmlFor="ollama-model-select" className="block text-xs text-[#9BA3B0] mb-1.5">
                Active local model
              </label>
              <select
                id="ollama-model-select"
                value={ollama.activeModel}
                disabled={busyAction !== null}
                onChange={(e) =>
                  void onAction('ollama-model', '/api/ollama/model', { model: e.target.value })
                }
                className="w-full px-3 py-2 text-xs font-mono text-[#F3F5F8] bg-[#0B0D10] border border-white/[0.12] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400 cursor-pointer"
              >
                {ollama.models.map((m) => (
                  <option key={m.name} value={m.name} className="bg-[#13161B] text-[#F3F5F8]">
                    {m.name} ({m.parameterSize} · {m.sizeGb} GB)
                  </option>
                ))}
              </select>
            </div>

            <div className="flex items-center gap-2">
              <button
                type="button"
                disabled={busyAction !== null}
                onClick={() => void onAction('ollama-health', '/api/ollama/health')}
                className="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
              >
                <Activity className="w-3.5 h-3.5 text-sky-400" />
                Health Check
              </button>

              <button
                type="button"
                disabled={busyAction !== null}
                onClick={() =>
                  void onAction('ollama-toggle', '/api/ollama/toggle', {
                    connected: !isOllamaConnected,
                  })
                }
                className="inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
              >
                <Power className={`w-3.5 h-3.5 ${isOllamaConnected ? 'text-rose-400' : 'text-emerald-400'}`} />
                {isOllamaConnected ? 'Disconnect' : 'Reconnect'}
              </button>
            </div>
          </div>
        </article>

        {/* 4. Claude API Health Checker */}
        <article className="bg-[#13161B] border border-white/[0.08] rounded-xl p-5 flex flex-col justify-between gap-5">
          <div className="space-y-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <h2 className="text-base font-semibold text-[#F3F5F8] truncate">
                  Claude API
                </h2>
                <p className="text-xs text-[#9BA3B0] font-mono truncate mt-0.5">
                  api.anthropic.com ·{' '}
                  {claude.keySource === 'env'
                    ? 'Server env'
                    : claude.keySource === 'manual'
                      ? 'Runtime key'
                      : 'Not configured'}
                </p>
              </div>
              <TrafficLightLamp active={claude.light} label={getClaudeLabel(claude.state)} />
            </div>

            {/* Inline Claude API Key Paste */}
            {claude.connected && !editingClaudeKey ? (
              <div className="space-y-1.5">
                <span className="block text-xs text-[#9BA3B0]">Claude API key (runtime memory only)</span>
                <div className="flex items-center justify-between gap-2 px-3 py-1.5 bg-[#0B0D10] border border-white/[0.1] rounded-lg">
                  <div className="flex items-center gap-2 min-w-0">
                    <KeyRound className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
                    <span className="text-xs font-mono text-[#D4D9E2] truncate">
                      {claude.keyHint}
                    </span>
                  </div>
                  <button
                    type="button"
                    onClick={() => setEditingClaudeKey(true)}
                    className="text-xs font-medium text-sky-400 hover:text-sky-300 whitespace-nowrap shrink-0 cursor-pointer"
                  >
                    Replace Key
                  </button>
                </div>
              </div>
            ) : (
              <form onSubmit={(e) => void handleClaudeKeySubmit(e)} className="space-y-1.5">
                <label htmlFor="claude-key-inline" className="block text-xs text-[#9BA3B0]">
                  Paste Claude API key (verified via /v1/models)
                </label>
                <div className="flex items-center gap-1.5">
                  <div className="relative flex-1 min-w-0">
                    <KeyRound className="w-3.5 h-3.5 text-[#7B8494] absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input
                      id="claude-key-inline"
                      type="password"
                      autoComplete="off"
                      spellCheck={false}
                      value={claudeKeyInput}
                      onChange={(e) => setClaudeKeyInput(e.target.value)}
                      placeholder="sk-ant-api03-..."
                      className="w-full pl-8 pr-2.5 py-1.5 text-xs font-mono text-[#F3F5F8] placeholder:text-[#6B7280] bg-[#0B0D10] border border-white/[0.12] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400"
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={busyAction !== null || !claudeKeyInput.trim()}
                    className="px-3 py-1.5 text-xs font-medium text-[#0B0D10] bg-[#38BDF8] hover:bg-[#7DD3FC] rounded-lg transition-colors whitespace-nowrap shrink-0 cursor-pointer disabled:opacity-50"
                  >
                    {busyAction === 'claude-connect' ? 'Checking...' : 'Check Key'}
                  </button>
                  {editingClaudeKey && (
                    <button
                      type="button"
                      onClick={() => {
                        setEditingClaudeKey(false);
                        setClaudeKeyInput('');
                      }}
                      className="px-2.5 py-1.5 text-xs text-[#9BA3B0] hover:text-[#F3F5F8] whitespace-nowrap shrink-0 cursor-pointer"
                    >
                      Cancel
                    </button>
                  )}
                </div>
              </form>
            )}

            <dl className="grid grid-cols-2 gap-x-4 gap-y-3 pt-3 border-t border-white/[0.07] text-xs">
              <div>
                <dt className="text-[#7B8494]">HTTP Status</dt>
                <dd className="font-mono tabular-nums text-sm mt-0.5 truncate">
                  {claude.connected && claude.httpStatus ? (
                    <span className="text-emerald-400">{claude.httpStatus} OK</span>
                  ) : claude.httpStatus ? (
                    <span className="text-rose-400">HTTP {claude.httpStatus}</span>
                  ) : claude.state === 'error' ? (
                    <span className="text-rose-400">Unreachable</span>
                  ) : (
                    <span className="text-[#9BA3B0]">—</span>
                  )}
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Latency</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {claude.latencyMs !== null ? `${claude.latencyMs} ms` : '—'}
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Accessible Models</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {claude.models.length > 0 ? `${claude.models.length}` : '—'}
                </dd>
              </div>
              <div>
                <dt className="text-[#7B8494]">Last Checked</dt>
                <dd className="font-mono tabular-nums text-[#F3F5F8] text-sm mt-0.5">
                  {formatShortTime(claude.lastCheckedAt)}
                </dd>
              </div>
              {claude.lastError && (
                <div className="col-span-2">
                  <dt className="text-[#7B8494]">Last Check Error</dt>
                  <dd className="text-xs text-rose-300 mt-1 truncate" title={claude.lastError}>
                    {claude.lastError}
                  </dd>
                </div>
              )}
            </dl>
          </div>

          <div className="space-y-3 pt-3 border-t border-white/[0.07]">
            <div>
              <label htmlFor="claude-model-select" className="block text-xs text-[#9BA3B0] mb-1.5">
                Verified Claude model
              </label>
              <select
                id="claude-model-select"
                value={claude.activeModel}
                disabled={busyAction !== null || claude.models.length === 0}
                onChange={(e) =>
                  void onAction('claude-model', '/api/claude/model', { model: e.target.value })
                }
                className="w-full px-3 py-2 text-xs font-mono text-[#F3F5F8] bg-[#0B0D10] border border-white/[0.12] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {claude.models.length === 0 ? (
                  <option value="" className="bg-[#13161B] text-[#9BA3B0]">
                    Paste Claude API key to fetch models
                  </option>
                ) : (
                  claude.models.map((m) => (
                    <option key={m.id} value={m.id} className="bg-[#13161B] text-[#F3F5F8]">
                      {m.displayName !== m.id ? `${m.displayName} (${m.id})` : m.id}
                    </option>
                  ))
                )}
              </select>
            </div>

            <div className="flex items-center gap-2">
              <button
                type="button"
                disabled={busyAction !== null || !hasClaudeKey}
                onClick={() => void onAction('claude-health', '/api/claude/health')}
                className="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
              >
                <Activity className="w-3.5 h-3.5 text-orange-400" />
                Health Check
              </button>

              <button
                type="button"
                disabled={busyAction !== null || !hasClaudeKey}
                onClick={() => {
                  setEditingClaudeKey(false);
                  setClaudeKeyInput('');
                  void onAction('claude-disconnect', '/api/claude/disconnect');
                }}
                className="inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
              >
                <Trash2 className="w-3.5 h-3.5 text-rose-400" />
                Clear Key
              </button>
            </div>
          </div>
        </article>
      </div>
    </section>
  );
}
