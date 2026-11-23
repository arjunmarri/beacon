import { Download } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { ActivityLogPanel } from './components/ActivityLogPanel.tsx';
import { ConfigurationPanel } from './components/ConfigurationPanel.tsx';
import { GitAuthModal } from './components/GitAuthModal.tsx';
import { MacDmgModal } from './components/MacDmgModal.tsx';
import { ServiceTrafficLights } from './components/ServiceTrafficLights.tsx';
import type { BeaconConfig, LogEntry, SystemSnapshot } from './types.ts';

export default function App() {
  const [snapshot, setSnapshot] = useState<SystemSnapshot | null>(null);
  const [config, setConfig] = useState<BeaconConfig | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [dmgModalOpen, setDmgModalOpen] = useState(false);
  const [gitAuthOpen, setGitAuthOpen] = useState(false);

  const loadInitialData = useCallback(async () => {
    try {
      const [statusRes, configRes, logsRes] = await Promise.all([
        fetch('/api/status'),
        fetch('/api/config'),
        fetch('/api/logs'),
      ]);
      if (!statusRes.ok || !configRes.ok || !logsRes.ok) {
        throw new Error('Could not connect to Beacon local monitor backend.');
      }
      const [statusData, configData, logsData] = await Promise.all([
        statusRes.json() as Promise<SystemSnapshot>,
        configRes.json() as Promise<BeaconConfig>,
        logsRes.json() as Promise<{ entries: LogEntry[] }>,
      ]);
      setSnapshot(statusData);
      setConfig(configData);
      setLogs(logsData.entries || []);
      setErrorMessage(null);
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : 'Unable to load Beacon state.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadInitialData();
  }, [loadInitialData]);

  // Real-time Server-Sent Events stream for flat-file logs and traffic light states
  useEffect(() => {
    const source = new EventSource('/api/logs/stream');

    source.addEventListener('snapshot', (event) => {
      try {
        const next = JSON.parse((event as MessageEvent).data) as SystemSnapshot;
        setSnapshot(next);
        setErrorMessage(null);
      } catch {
        // Ignore malformed frame
      }
    });

    source.addEventListener('log', (event) => {
      try {
        const entry = JSON.parse((event as MessageEvent).data) as LogEntry;
        setLogs((prev) => {
          if (prev.some((existing) => existing.id === entry.id)) return prev;
          const next = [...prev, entry];
          return next.length > 400 ? next.slice(-400) : next;
        });
      } catch {
        // Ignore malformed frame
      }
    });

    return () => {
      source.close();
    };
  }, []);

  const handleAction = useCallback(
    async (actionKey: string, endpoint: string, body?: Record<string, unknown>): Promise<boolean> => {
      setBusyAction(actionKey);
      setErrorMessage(null);
      try {
        const res = await fetch(endpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: body ? JSON.stringify(body) : undefined,
        });
        const data = await res.json();
        const nextSnap: SystemSnapshot | null = data.snapshot
          ? (data.snapshot as SystemSnapshot)
          : data.vite && data.git && data.ollama
            ? (data as SystemSnapshot)
            : null;
        if (nextSnap) {
          setSnapshot(nextSnap);
          setConfig((prev) =>
            prev
              ? {
                  ...prev,
                  vite: {
                    ...prev.vite,
                    monitorUrl: nextSnap.vite.monitorUrl,
                    port: nextSnap.vite.port,
                    autoRestart: nextSnap.vite.autoRestart,
                  },
                }
              : prev,
          );
        }
        if (!res.ok) {
          throw new Error(data.error || 'Action failed.');
        }
        return true;
      } catch (err) {
        setErrorMessage(err instanceof Error ? err.message : 'Action failed.');
        return false;
      } finally {
        setBusyAction(null);
      }
    },
    [],
  );

  const handleSaveConfig = useCallback(async (nextConfig: BeaconConfig) => {
    setErrorMessage(null);
    const res = await fetch('/api/config', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(nextConfig),
    });
    const data = await res.json();
    if (!res.ok) {
      throw new Error(data.error || 'Failed to save configuration.');
    }
    setConfig(data.config as BeaconConfig);
    if (data.snapshot) {
      setSnapshot(data.snapshot as SystemSnapshot);
    }
  }, []);

  const handleSendTestEmail = useCallback(async () => {
    setErrorMessage(null);
    const res = await fetch('/api/email/test', { method: 'POST' });
    const data = await res.json();
    if (!res.ok) {
      setErrorMessage(data.error || 'Failed to dispatch test alert.');
      return;
    }
    if (data.snapshot) {
      setSnapshot(data.snapshot as SystemSnapshot);
    }
  }, []);

  const handleClearLogs = useCallback(async () => {
    const res = await fetch('/api/logs', { method: 'DELETE' });
    if (res.ok) {
      const data = (await res.json()) as { entries: LogEntry[] };
      setLogs(data.entries || []);
    }
  }, []);

  return (
    <div className="min-h-screen bg-[#0B0D10] text-[#F3F5F8] flex flex-col">
      {/* Strict 3-Zone Top Bar */}
      <header className="sticky top-0 z-30 bg-[#0B0D10]/90 backdrop-blur-md border-b border-white/[0.08]">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 h-14 flex items-center justify-between gap-8">
          {/* Zone 1: Single-line Brand Wordmark */}
          <a
            href="#services"
            className="text-base font-bold tracking-tight text-[#F3F5F8] whitespace-nowrap shrink-0"
          >
            Beacon
          </a>

          {/* Zone 2: Clean single-line section links */}
          <nav
            aria-label="Primary dashboard sections"
            className="hidden sm:flex items-center gap-6 text-sm font-medium text-[#9BA3B0]"
          >
            <a
              href="#services"
              className="hover:text-[#F3F5F8] transition-colors whitespace-nowrap shrink-0"
            >
              Services
            </a>
            <a
              href="#activity-log"
              className="hover:text-[#F3F5F8] transition-colors whitespace-nowrap shrink-0"
            >
              Activity Log
            </a>
            <a
              href="#configuration"
              className="hover:text-[#F3F5F8] transition-colors whitespace-nowrap shrink-0"
            >
              Configuration
            </a>
          </nav>

          {/* Zone 3: Single Primary Action */}
          <div className="flex items-center shrink-0">
            <button
              type="button"
              onClick={() => setDmgModalOpen(true)}
              className="inline-flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold text-[#0B0D10] bg-[#38BDF8] hover:bg-[#7DD3FC] rounded-lg transition-colors whitespace-nowrap shrink-0 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400"
            >
              <Download className="w-3.5 h-3.5" />
              Swift / Mac App
            </button>
          </div>
        </div>
      </header>

      {/* Main Minimalist Dashboard Viewport */}
      <main className="flex-1 w-full max-w-6xl mx-auto px-4 sm:px-6 py-6 sm:py-8 space-y-6">
        {errorMessage && (
          <div
            role="alert"
            className="px-4 py-3 text-xs text-rose-200 bg-rose-500/10 border border-rose-500/25 rounded-lg flex items-center justify-between gap-4"
          >
            <span>{errorMessage}</span>
            <button
              type="button"
              onClick={() => setErrorMessage(null)}
              className="text-rose-300 hover:text-white underline whitespace-nowrap shrink-0 cursor-pointer"
            >
              Dismiss
            </button>
          </div>
        )}

        {loading || !snapshot ? (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {[0, 1, 2, 3].map((idx) => (
              <div
                key={idx}
                className="h-64 bg-[#13161B] border border-white/[0.08] rounded-xl animate-pulse"
              />
            ))}
          </div>
        ) : (
          <>
            <ServiceTrafficLights
              snapshot={snapshot}
              busyAction={busyAction}
              onAction={handleAction}
              onOpenGitAuth={() => setGitAuthOpen(true)}
            />

            <ActivityLogPanel
              logs={logs}
              logFilePath={snapshot.logFilePath}
              logFileBytes={snapshot.logFileBytes}
              loading={loading}
              onClearLogs={handleClearLogs}
            />

            {config && (
              <ConfigurationPanel
                config={config}
                emailStatus={snapshot.email}
                configFilePath={snapshot.configFilePath}
                onSaveConfig={handleSaveConfig}
                onSendTestEmail={handleSendTestEmail}
              />
            )}
          </>
        )}
      </main>

      <footer className="max-w-6xl w-full mx-auto px-4 sm:px-6 py-5 border-t border-white/[0.06] flex flex-col sm:flex-row items-center justify-between gap-2 text-xs text-[#6B7280]">
        <span>Beacon — Lightweight macOS Process, Git, Ollama &amp; Claude Monitor</span>
        <button
          type="button"
          onClick={() => setDmgModalOpen(true)}
          className="text-[#9BA3B0] hover:text-[#F3F5F8] transition-colors cursor-pointer"
        >
          Export Swift Xcode Project / Mac .dmg
        </button>
      </footer>

      <MacDmgModal open={dmgModalOpen} onClose={() => setDmgModalOpen(false)} />

      {snapshot && (
        <GitAuthModal
          open={gitAuthOpen}
          onClose={() => setGitAuthOpen(false)}
          git={snapshot.git}
          gitAccount={snapshot.gitAccount}
          onSnapshotUpdate={(next) => {
            setSnapshot(next);
            setConfig((prev) =>
              prev
                ? {
                    ...prev,
                    git: {
                      ...prev.git,
                      repoUrl: next.git.repoUrl,
                      branch: next.git.branch,
                    },
                  }
                : prev,
            );
          }}
        />
      )}
    </div>
  );
}
