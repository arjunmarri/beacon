import {
  Check,
  ExternalLink,
  GitBranch,
  KeyRound,
  Link2,
  LogOut,
  RefreshCw,
  ShieldCheck,
  Terminal,
  X,
} from 'lucide-react';
import { useEffect, useState } from 'react';
import type { GitAccountStatus, GitDeployStatus, SystemSnapshot } from '../types.ts';

interface GitAuthModalProps {
  open: boolean;
  onClose: () => void;
  git: GitDeployStatus;
  gitAccount: GitAccountStatus;
  onSnapshotUpdate: (snapshot: SystemSnapshot) => void;
}

export function GitAuthModal({
  open,
  onClose,
  git,
  gitAccount,
  onSnapshotUpdate,
}: GitAuthModalProps) {
  const [patToken, setPatToken] = useState('');
  const [selectedRepoUrl, setSelectedRepoUrl] = useState(git.repoUrl);
  const [selectedBranch, setSelectedBranch] = useState(git.branch);
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  useEffect(() => {
    setSelectedRepoUrl(git.repoUrl);
    setSelectedBranch(git.branch);
  }, [git.repoUrl, git.branch]);

  // Listen for OAuth popup completion via postMessage
  useEffect(() => {
    if (!open) return;

    function handleMessage(event: MessageEvent) {
      const origin = event.origin;
      const isTrustedOrigin =
        origin === window.location.origin ||
        origin.endsWith('.run.app') ||
        origin.startsWith('http://localhost') ||
        origin.startsWith('http://127.0.0.1');
      if (!isTrustedOrigin) return;

      if (event.data?.type === 'OAUTH_AUTH_SUCCESS') {
        setBusy(null);
        setNotice({
          type: 'success',
          text: 'GitHub account authorized with repository permissions. Select your repo below to link origin.',
        });
        void fetch('/api/status')
          .then((res) => (res.ok ? res.json() : null))
          .then((snap) => {
            if (snap) onSnapshotUpdate(snap as SystemSnapshot);
          });
      } else if (event.data?.type === 'OAUTH_AUTH_ERROR') {
        setBusy(null);
        setNotice({
          type: 'error',
          text: String(event.data?.message || 'GitHub OAuth authorization was cancelled or failed.'),
        });
      }
    }

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, [open, onSnapshotUpdate]);

  if (!open) return null;

  async function handleOAuthConnect() {
    setBusy('oauth');
    setNotice(null);
    try {
      const res = await fetch('/api/git/auth/url');
      const data = (await res.json()) as { url?: string; error?: string };
      if (!res.ok || !data.url) {
        throw new Error(
          data.error ||
            'GitHub OAuth Client ID/Secret not configured yet. Use Sync Local Mac Login or Personal Access Token below.',
        );
      }
      const popup = window.open(data.url, 'beacon_github_oauth', 'width=600,height=720');
      if (!popup) {
        throw new Error('Popup blocked by browser. Allow popups for this site and click again.');
      }
    } catch (err) {
      setNotice({
        type: 'error',
        text: err instanceof Error ? err.message : 'Unable to start GitHub OAuth flow.',
      });
      setBusy(null);
    }
  }

  async function handleSyncLocalMac() {
    setBusy('local');
    setNotice(null);
    try {
      const res = await fetch('/api/git/auth/sync-local', { method: 'POST' });
      const data = (await res.json()) as { synced?: boolean; message?: string; snapshot?: SystemSnapshot };
      if (data.snapshot) onSnapshotUpdate(data.snapshot);
      setNotice({
        type: data.synced ? 'success' : 'error',
        text: data.message || (data.synced ? 'Synced local Mac Git login.' : 'No local credentials found.'),
      });
    } catch (err) {
      setNotice({
        type: 'error',
        text: err instanceof Error ? err.message : 'Failed to inspect local Mac Git credentials.',
      });
    } finally {
      setBusy(null);
    }
  }

  async function handleTokenConnect(e: React.FormEvent) {
    e.preventDefault();
    if (!patToken.trim()) return;
    setBusy('token');
    setNotice(null);
    try {
      const res = await fetch('/api/git/auth/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: patToken.trim() }),
      });
      const data = (await res.json()) as { error?: string; snapshot?: SystemSnapshot };
      if (!res.ok) {
        throw new Error(data.error || 'Token verification failed.');
      }
      if (data.snapshot) onSnapshotUpdate(data.snapshot);
      setPatToken('');
      setNotice({
        type: 'success',
        text: 'GitHub account connected and permissions verified. Link your repository below.',
      });
    } catch (err) {
      setNotice({
        type: 'error',
        text: err instanceof Error ? err.message : 'Token verification failed.',
      });
    } finally {
      setBusy(null);
    }
  }

  async function handleDisconnect() {
    setBusy('disconnect');
    setNotice(null);
    try {
      const res = await fetch('/api/git/auth/disconnect', { method: 'POST' });
      const data = (await res.json()) as { snapshot?: SystemSnapshot };
      if (data.snapshot) onSnapshotUpdate(data.snapshot);
      setNotice({ type: 'success', text: 'Disconnected GitHub account session.' });
    } finally {
      setBusy(null);
    }
  }

  async function handleLinkRepository(e: React.FormEvent) {
    e.preventDefault();
    setBusy('link');
    setNotice(null);
    try {
      const res = await fetch('/api/git/select-repo', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          repoUrl: selectedRepoUrl.trim(),
          branch: selectedBranch.trim() || 'main',
        }),
      });
      const data = (await res.json()) as {
        verified?: boolean;
        detail?: string;
        error?: string;
        snapshot?: SystemSnapshot;
      };
      if (!res.ok) {
        throw new Error(data.error || 'Failed to link origin remote.');
      }
      if (data.snapshot) onSnapshotUpdate(data.snapshot);
      setNotice({
        type: data.verified ? 'success' : 'error',
        text: data.detail || 'Repository origin updated.',
      });
    } catch (err) {
      setNotice({
        type: 'error',
        text: err instanceof Error ? err.message : 'Failed to link repository.',
      });
    } finally {
      setBusy(null);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-xs p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="git-auth-title"
      onClick={onClose}
    >
      <div
        className="w-full max-w-xl max-h-[90vh] overflow-y-auto bg-[#13161B] border border-white/[0.1] rounded-xl shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-4 border-b border-white/[0.08] flex items-center justify-between gap-4">
          <div className="flex items-center gap-2.5">
            <ShieldCheck className="w-4 h-4 text-sky-400" />
            <h2 id="git-auth-title" className="text-base font-semibold text-[#F3F5F8]">
              Git Account Sync &amp; Repository Permissions
            </h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close modal"
            className="p-1.5 text-[#9BA3B0] hover:text-[#F3F5F8] rounded-lg hover:bg-white/[0.06] transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-5 space-y-5 text-xs">
          {/* Active account summary or sign-in options */}
          {gitAccount.connected ? (
            <div className="p-4 bg-[#0B0D10] border border-emerald-500/25 rounded-lg flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <div className="space-y-1 min-w-0">
                <div className="text-sm font-semibold text-[#F3F5F8] truncate">
                  @{gitAccount.username}
                  {gitAccount.displayName && gitAccount.displayName !== gitAccount.username
                    ? ` · ${gitAccount.displayName}`
                    : ''}
                </div>
                <div className="font-mono text-[#9BA3B0] truncate">
                  Connected via {gitAccount.method}
                  <span aria-hidden="true" className="mx-1.5 text-white/20">·</span>
                  Scopes: {gitAccount.scopes.join(', ')}
                </div>
              </div>
              <button
                type="button"
                disabled={busy !== null}
                onClick={() => void handleDisconnect()}
                className="inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-rose-300 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/25 rounded-lg transition-colors whitespace-nowrap shrink-0 cursor-pointer disabled:opacity-50"
              >
                <LogOut className="w-3.5 h-3.5" />
                Disconnect
              </button>
            </div>
          ) : (
            <div className="space-y-4">
              <p className="text-[#C4CBD6] leading-relaxed text-sm">
                Authorize GitHub (<span className="font-mono text-xs text-[#F3F5F8]">repo</span>,{' '}
                <span className="font-mono text-xs text-[#F3F5F8]">read:user</span>) so Beacon can
                authenticate private repositories and automatically configure the{' '}
                <span className="font-mono text-xs text-[#F3F5F8]">origin</span> remote on your Mac.
              </p>

              {/* Action row: OAuth Popup + Sync Local Mac Keychain/gh */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                <button
                  type="button"
                  disabled={busy !== null}
                  onClick={() => void handleOAuthConnect()}
                  className="inline-flex items-center justify-center gap-2 px-4 py-2.5 text-xs font-semibold text-[#0B0D10] bg-[#38BDF8] hover:bg-[#7DD3FC] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
                >
                  <ExternalLink className="w-3.5 h-3.5" />
                  {busy === 'oauth' ? 'Waiting for GitHub...' : 'Authorize with GitHub OAuth'}
                </button>

                <button
                  type="button"
                  disabled={busy !== null}
                  onClick={() => void handleSyncLocalMac()}
                  className="inline-flex items-center justify-center gap-2 px-4 py-2.5 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.1] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
                >
                  <Terminal className="w-3.5 h-3.5 text-emerald-400" />
                  {busy === 'local' ? 'Checking Mac...' : 'Sync Mac Keychain / gh CLI'}
                </button>
              </div>

              {!gitAccount.oauthConfigured && (
                <p className="text-[#8B94A4] leading-relaxed">
                  To enable the one-click OAuth popup, set{' '}
                  <span className="font-mono text-[#D9DFE8]">GITHUB_CLIENT_ID</span> and{' '}
                  <span className="font-mono text-[#D9DFE8]">GITHUB_CLIENT_SECRET</span> with
                  callback URL{' '}
                  <span className="font-mono text-[#D9DFE8] break-all">
                    {gitAccount.callbackUrl}
                  </span>
                  , or connect directly with a GitHub Personal Access Token below.
                </p>
              )}

              {/* Personal Access Token fallback */}
              <form
                onSubmit={handleTokenConnect}
                className="pt-3 border-t border-white/[0.07] space-y-2.5"
              >
                <label htmlFor="git-pat-input" className="block text-[#9BA3B0] font-medium">
                  Connect with GitHub Personal Access Token (kept in server memory only)
                </label>
                <div className="flex flex-col sm:flex-row gap-2">
                  <div className="relative flex-1">
                    <KeyRound className="w-3.5 h-3.5 text-[#7B8494] absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input
                      id="git-pat-input"
                      type="password"
                      autoComplete="off"
                      value={patToken}
                      onChange={(e) => setPatToken(e.target.value)}
                      placeholder="ghp_... or github_pat_... (needs repo read access)"
                      className="w-full pl-9 pr-3 py-2 text-xs font-mono text-[#F3F5F8] placeholder:text-[#6B7280] bg-[#0B0D10] border border-white/[0.1] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400"
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={busy !== null || !patToken.trim()}
                    className="inline-flex items-center justify-center gap-1.5 px-4 py-2 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.1] rounded-lg transition-colors whitespace-nowrap shrink-0 cursor-pointer disabled:opacity-50"
                  >
                    <Check className="w-3.5 h-3.5 text-sky-400" />
                    {busy === 'token' ? 'Verifying...' : 'Verify & Connect'}
                  </button>
                </div>
              </form>
            </div>
          )}

          {/* Repository picker & automatic 'origin' remote binding */}
          <form
            onSubmit={handleLinkRepository}
            className="pt-4 border-t border-white/[0.08] space-y-3"
          >
            <div className="flex items-center justify-between gap-2">
              <h3 className="text-sm font-semibold text-[#F3F5F8]">
                Link Repository &amp; Configure <span className="font-mono text-xs">origin</span> Remote
              </h3>
              <span className="font-mono text-[#7B8494]">
                {git.remoteConfigured ? 'origin set' : 'origin missing'}
              </span>
            </div>

            {gitAccount.repos.length > 0 && (
              <div>
                <label htmlFor="git-repo-picker" className="block text-[#9BA3B0] mb-1">
                  Your authorized GitHub repositories ({gitAccount.repos.length})
                </label>
                <select
                  id="git-repo-picker"
                  value={
                    gitAccount.repos.some((r) => r.cloneUrl === selectedRepoUrl)
                      ? selectedRepoUrl
                      : ''
                  }
                  onChange={(e) => {
                    const chosen = gitAccount.repos.find((r) => r.cloneUrl === e.target.value);
                    if (chosen) {
                      setSelectedRepoUrl(chosen.cloneUrl);
                      setSelectedBranch(chosen.defaultBranch || 'main');
                    }
                  }}
                  className="w-full px-3 py-2 text-xs font-mono text-[#F3F5F8] bg-[#0B0D10] border border-white/[0.12] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400 cursor-pointer"
                >
                  <option value="" className="bg-[#13161B]">
                    Select a repository from @{gitAccount.username}...
                  </option>
                  {gitAccount.repos.map((repo) => (
                    <option key={repo.fullName} value={repo.cloneUrl} className="bg-[#13161B]">
                      {repo.fullName} ({repo.private ? 'private' : 'public'} · {repo.defaultBranch})
                    </option>
                  ))}
                </select>
              </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
              <div className="sm:col-span-2">
                <label htmlFor="git-origin-url" className="block text-[#9BA3B0] mb-1">
                  Remote <span className="font-mono">origin</span> URL
                </label>
                <input
                  id="git-origin-url"
                  type="text"
                  value={selectedRepoUrl}
                  onChange={(e) => setSelectedRepoUrl(e.target.value)}
                  placeholder="https://github.com/username/repo.git"
                  className="w-full px-3 py-2 text-xs font-mono text-[#F3F5F8] placeholder:text-[#6B7280] bg-[#0B0D10] border border-white/[0.1] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400"
                />
              </div>
              <div>
                <label htmlFor="git-origin-branch" className="block text-[#9BA3B0] mb-1">
                  Branch
                </label>
                <div className="relative">
                  <GitBranch className="w-3.5 h-3.5 text-[#7B8494] absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                  <input
                    id="git-origin-branch"
                    type="text"
                    value={selectedBranch}
                    onChange={(e) => setSelectedBranch(e.target.value)}
                    placeholder="main"
                    className="w-full pl-8 pr-3 py-2 text-xs font-mono text-[#F3F5F8] bg-[#0B0D10] border border-white/[0.1] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400"
                  />
                </div>
              </div>
            </div>

            {notice && (
              <div
                role="status"
                className={`px-3.5 py-2.5 rounded-lg border leading-relaxed ${
                  notice.type === 'success'
                    ? 'text-emerald-200 bg-emerald-500/10 border-emerald-500/25'
                    : 'text-rose-200 bg-rose-500/10 border-rose-500/25'
                }`}
              >
                {notice.text}
              </div>
            )}

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 text-xs font-medium text-[#9BA3B0] hover:text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap cursor-pointer"
              >
                Close
              </button>
              <button
                type="submit"
                disabled={busy !== null || !selectedRepoUrl.trim()}
                className="inline-flex items-center gap-1.5 px-4 py-2 text-xs font-semibold text-[#0B0D10] bg-[#38BDF8] hover:bg-[#7DD3FC] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-50"
              >
                {busy === 'link' ? (
                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                ) : (
                  <Link2 className="w-3.5 h-3.5" />
                )}
                {busy === 'link' ? 'Linking & Verifying...' : 'Save & Link Origin Remote'}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
