import { Download, Search, Trash2 } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import type { LogEntry, LogLevel, LogSource } from '../types.ts';

interface ActivityLogPanelProps {
  logs: LogEntry[];
  logFilePath: string;
  logFileBytes: number;
  loading: boolean;
  onClearLogs: () => Promise<void>;
}

const SOURCE_FILTERS: Array<{ id: 'all' | LogSource; label: string }> = [
  { id: 'all', label: 'All' },
  { id: 'vite', label: 'Vite' },
  { id: 'git', label: 'Git' },
  { id: 'ollama', label: 'Ollama' },
  { id: 'claude', label: 'Claude' },
  { id: 'email', label: 'Email' },
];

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function formatLogTime(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleTimeString([], {
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

function getSourceColor(source: LogSource): string {
  switch (source) {
    case 'vite':
      return 'text-sky-400';
    case 'git':
      return 'text-violet-400';
    case 'ollama':
      return 'text-emerald-400';
    case 'claude':
      return 'text-orange-400';
    case 'email':
      return 'text-amber-400';
    default:
      return 'text-[#9BA3B0]';
  }
}

function getLevelColor(level: LogLevel): string {
  switch (level) {
    case 'error':
      return 'text-rose-400';
    case 'warn':
      return 'text-amber-400';
    default:
      return 'text-[#7B8494]';
  }
}

export function ActivityLogPanel({
  logs,
  logFilePath,
  logFileBytes,
  loading,
  onClearLogs,
}: ActivityLogPanelProps) {
  const [sourceFilter, setSourceFilter] = useState<'all' | LogSource>('all');
  const [levelFilter, setLevelFilter] = useState<'all' | LogLevel>('all');
  const [query, setQuery] = useState('');
  const [autoScroll, setAutoScroll] = useState(true);
  const feedRef = useRef<HTMLDivElement | null>(null);

  const filteredLogs = useMemo(() => {
    const q = query.trim().toLowerCase();
    return logs.filter((entry) => {
      if (sourceFilter !== 'all' && entry.source !== sourceFilter) return false;
      if (levelFilter !== 'all' && entry.level !== levelFilter) return false;
      if (q && !entry.message.toLowerCase().includes(q) && !entry.source.includes(q)) return false;
      return true;
    });
  }, [logs, sourceFilter, levelFilter, query]);

  useEffect(() => {
    if (autoScroll && feedRef.current) {
      feedRef.current.scrollTop = feedRef.current.scrollHeight;
    }
  }, [filteredLogs, autoScroll]);

  return (
    <section
      id="activity-log"
      aria-label="Real-time flat-file activity log"
      className="bg-[#13161B] border border-white/[0.08] rounded-xl overflow-hidden"
    >
      {/* Header Toolbar */}
      <div className="px-5 py-4 border-b border-white/[0.07] flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-base font-semibold text-[#F3F5F8]">Real-Time Activity Log</h2>
          <p className="text-xs text-[#9BA3B0] font-mono tabular-nums mt-0.5 truncate">
            {logFilePath}
            <span aria-hidden="true" className="mx-2 text-white/20">·</span>
            {formatBytes(logFileBytes)}
            <span aria-hidden="true" className="mx-2 text-white/20">·</span>
            {filteredLogs.length} entries
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {/* Interactive segmented source filter */}
          <div
            className="inline-flex items-center p-0.5 bg-[#0B0D10] border border-white/[0.08] rounded-lg"
            role="group"
            aria-label="Filter log source"
          >
            {SOURCE_FILTERS.map((item) => (
              <button
                key={item.id}
                type="button"
                onClick={() => setSourceFilter(item.id)}
                className={`px-2.5 py-1.5 text-xs font-medium rounded-md transition-colors whitespace-nowrap shrink-0 cursor-pointer ${
                  sourceFilter === item.id
                    ? 'bg-[#1D222B] text-[#F3F5F8]'
                    : 'text-[#8B94A4] hover:text-[#F3F5F8]'
                }`}
              >
                {item.label}
              </button>
            ))}
          </div>

          <select
            aria-label="Filter log severity"
            value={levelFilter}
            onChange={(e) => setLevelFilter(e.target.value as 'all' | LogLevel)}
            className="px-2.5 py-1.5 text-xs text-[#F3F5F8] bg-[#0B0D10] border border-white/[0.08] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400 cursor-pointer"
          >
            <option value="all" className="bg-[#13161B]">All Levels</option>
            <option value="info" className="bg-[#13161B]">Info</option>
            <option value="warn" className="bg-[#13161B]">Warning</option>
            <option value="error" className="bg-[#13161B]">Error</option>
          </select>

          <div className="relative flex-1 sm:flex-initial">
            <Search className="w-3.5 h-3.5 text-[#7B8494] absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search logs..."
              aria-label="Search activity logs"
              className="w-full sm:w-44 pl-8 pr-2.5 py-1.5 text-xs text-[#F3F5F8] placeholder:text-[#6B7280] bg-[#0B0D10] border border-white/[0.08] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400"
            />
          </div>

          <a
            href="/api/logs/download"
            download="beacon-activity.log"
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap shrink-0"
          >
            <Download className="w-3.5 h-3.5" />
            Export .log
          </a>

          <button
            type="button"
            onClick={() => void onClearLogs()}
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium text-[#9BA3B0] hover:text-rose-400 bg-[#1B1F27] hover:bg-rose-500/10 border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap shrink-0 cursor-pointer"
            title="Clear flat-file log"
          >
            <Trash2 className="w-3.5 h-3.5" />
            Clear
          </button>
        </div>
      </div>

      {/* Streaming Monospace Log Feed */}
      <div
        ref={feedRef}
        onScroll={() => {
          if (!feedRef.current) return;
          const { scrollTop, scrollHeight, clientHeight } = feedRef.current;
          setAutoScroll(scrollHeight - scrollTop - clientHeight < 48);
        }}
        className="h-72 sm:h-80 overflow-y-auto bg-[#0D1014] font-mono text-xs divide-y divide-white/[0.04]"
      >
        {loading ? (
          <div className="p-5 space-y-2.5">
            {[0, 1, 2, 3, 4].map((row) => (
              <div key={row} className="h-5 rounded bg-white/[0.04] animate-pulse" />
            ))}
          </div>
        ) : filteredLogs.length === 0 ? (
          <div className="h-full flex flex-col items-center justify-center text-center px-6 py-10">
            <p className="text-sm font-sans font-medium text-[#D4D9E2]">No matching log entries</p>
            <p className="text-xs font-sans text-[#7B8494] mt-1">
              Events from Vite watchdog, Git auto-deploy, Ollama health, and email alerts stream directly into {logFilePath}.
            </p>
          </div>
        ) : (
          filteredLogs.map((entry) => (
            <div
              key={entry.id}
              className="px-4 sm:px-5 py-2 flex flex-col sm:flex-row sm:items-baseline gap-1 sm:gap-3 hover:bg-white/[0.02] transition-colors"
            >
              <div className="flex items-center gap-2.5 shrink-0 tabular-nums">
                <span className="text-[#6B7280]">{formatLogTime(entry.timestamp)}</span>
                <span className={`w-12 font-medium ${getSourceColor(entry.source)}`}>
                  {entry.source}
                </span>
                <span className={`w-10 ${getLevelColor(entry.level)}`}>{entry.level}</span>
              </div>
              <span className="text-[#D9DFE8] break-words leading-relaxed">{entry.message}</span>
            </div>
          ))
        )}
      </div>
    </section>
  );
}
