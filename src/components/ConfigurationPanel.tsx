import { Check, Mail, Save } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { BeaconConfig, EmailAlertConfig, ViteCommandPreset } from '../types.ts';

interface ConfigurationPanelProps {
  config: BeaconConfig;
  emailStatus: EmailAlertConfig;
  configFilePath: string;
  onSaveConfig: (next: BeaconConfig) => Promise<void>;
  onSendTestEmail: () => Promise<void>;
}

export function ConfigurationPanel({
  config,
  emailStatus,
  configFilePath,
  onSaveConfig,
  onSendTestEmail,
}: ConfigurationPanelProps) {
  const [draft, setDraft] = useState<BeaconConfig>(config);
  const [saving, setSaving] = useState(false);
  const [savedNotice, setSavedNotice] = useState(false);
  const [testingEmail, setTestingEmail] = useState(false);

  useEffect(() => {
    setDraft(config);
  }, [config]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      await onSaveConfig(draft);
      setSavedNotice(true);
      setTimeout(() => setSavedNotice(false), 2200);
    } finally {
      setSaving(false);
    }
  }

  async function handleTestEmail() {
    setTestingEmail(true);
    try {
      await onSendTestEmail();
    } finally {
      setTestingEmail(false);
    }
  }

  const inputClass =
    'w-full px-3 py-2 text-xs text-[#F3F5F8] bg-[#0B0D10] border border-white/[0.1] rounded-lg focus:outline-none focus:ring-2 focus:ring-sky-400 placeholder:text-[#6B7280]';

  return (
    <section
      id="configuration"
      aria-label="Flat-file settings and email alerts"
      className="bg-[#13161B] border border-white/[0.08] rounded-xl overflow-hidden"
    >
      <form onSubmit={handleSubmit}>
        <div className="px-5 py-4 border-b border-white/[0.07] flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h2 className="text-base font-semibold text-[#F3F5F8]">Configuration &amp; Alerts</h2>
            <p className="text-xs text-[#9BA3B0] font-mono mt-0.5">
              Stored in {configFilePath}
              <span aria-hidden="true" className="mx-2 text-white/20">·</span>
              {emailStatus.smtpConfiguredOnServer
                ? 'SMTP_PASS active on server'
                : 'Flat-file alert audit mode (set SMTP_PASS for live SMTP)'}
            </p>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <button
              type="button"
              disabled={testingEmail}
              onClick={() => void handleTestEmail()}
              className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap shrink-0 cursor-pointer disabled:opacity-50"
            >
              <Mail className="w-3.5 h-3.5 text-amber-400" />
              {testingEmail ? 'Sending...' : 'Test Email Alert'}
            </button>

            <button
              type="submit"
              disabled={saving}
              className="inline-flex items-center gap-1.5 px-4 py-2 text-xs font-semibold text-[#0B0D10] bg-[#38BDF8] hover:bg-[#7DD3FC] rounded-lg transition-colors whitespace-nowrap shrink-0 cursor-pointer disabled:opacity-50"
            >
              {savedNotice ? <Check className="w-3.5 h-3.5" /> : <Save className="w-3.5 h-3.5" />}
              {savedNotice ? 'Saved' : saving ? 'Saving...' : 'Save Settings'}
            </button>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 divide-y lg:divide-y-0 lg:divide-x divide-white/[0.07]">
          {/* Column 1: Vite Local Folder & Watchdog */}
          <div className="p-5 space-y-3.5">
            <h3 className="text-sm font-semibold text-[#F3F5F8]">Vite / Node.js Folder</h3>

            <div>
              <label htmlFor="cfg-vite-dir" className="block text-xs text-[#9BA3B0] mb-1">
                Local Mac project folder
              </label>
              <input
                id="cfg-vite-dir"
                type="text"
                value={draft.vite.workingDir}
                onChange={(e) =>
                  setDraft({ ...draft, vite: { ...draft.vite, workingDir: e.target.value } })
                }
                placeholder="/Users/you/projects/vite-app"
                className={`${inputClass} font-mono`}
              />
            </div>

            <div>
              <label htmlFor="cfg-vite-monitor-url" className="block text-xs text-[#9BA3B0] mb-1">
                Localhost URL to monitor
              </label>
              <input
                id="cfg-vite-monitor-url"
                type="url"
                value={draft.vite.monitorUrl}
                onChange={(e) =>
                  setDraft({ ...draft, vite: { ...draft.vite, monitorUrl: e.target.value } })
                }
                placeholder="http://localhost:5173"
                className={`${inputClass} font-mono`}
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label htmlFor="cfg-vite-preset" className="block text-xs text-[#9BA3B0] mb-1">
                  Start command
                </label>
                <select
                  id="cfg-vite-preset"
                  value={draft.vite.commandPreset}
                  onChange={(e) =>
                    setDraft({
                      ...draft,
                      vite: { ...draft.vite, commandPreset: e.target.value as ViteCommandPreset },
                    })
                  }
                  className={`${inputClass} font-mono cursor-pointer`}
                >
                  <option value="demo-worker" className="bg-[#13161B]">Built-in Worker</option>
                  <option value="npm-dev" className="bg-[#13161B]">npm run dev</option>
                  <option value="npx-vite" className="bg-[#13161B]">npx vite</option>
                </select>
              </div>
              <div>
                <label htmlFor="cfg-vite-port" className="block text-xs text-[#9BA3B0] mb-1">
                  Port
                </label>
                <input
                  id="cfg-vite-port"
                  type="number"
                  min={1024}
                  max={65535}
                  value={draft.vite.port}
                  onChange={(e) =>
                    setDraft({
                      ...draft,
                      vite: { ...draft.vite, port: Number(e.target.value) || 5173 },
                    })
                  }
                  className={`${inputClass} font-mono tabular-nums`}
                />
              </div>
            </div>

            <div>
              <label htmlFor="cfg-vite-retries" className="block text-xs text-[#9BA3B0] mb-1">
                Max consecutive auto-restarts
              </label>
              <input
                id="cfg-vite-retries"
                type="number"
                min={1}
                max={100}
                value={draft.vite.maxRestarts}
                onChange={(e) =>
                  setDraft({
                    ...draft,
                    vite: { ...draft.vite, maxRestarts: Number(e.target.value) || 10 },
                  })
                }
                className={`${inputClass} font-mono tabular-nums`}
              />
            </div>
          </div>

          {/* Column 2: Git Auto-Deploy & Ollama */}
          <div className="p-5 space-y-3.5">
            <h3 className="text-sm font-semibold text-[#F3F5F8]">Git &amp; Ollama Endpoint</h3>

            <div>
              <label htmlFor="cfg-git-url" className="block text-xs text-[#9BA3B0] mb-1">
                Remote Git repository URL
              </label>
              <input
                id="cfg-git-url"
                type="text"
                value={draft.git.repoUrl}
                onChange={(e) =>
                  setDraft({ ...draft, git: { ...draft.git, repoUrl: e.target.value } })
                }
                placeholder="https://github.com/org/repo.git"
                className={`${inputClass} font-mono`}
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label htmlFor="cfg-git-branch" className="block text-xs text-[#9BA3B0] mb-1">
                  Branch
                </label>
                <input
                  id="cfg-git-branch"
                  type="text"
                  value={draft.git.branch}
                  onChange={(e) =>
                    setDraft({ ...draft, git: { ...draft.git, branch: e.target.value } })
                  }
                  className={`${inputClass} font-mono`}
                />
              </div>
              <div>
                <label htmlFor="cfg-git-poll" className="block text-xs text-[#9BA3B0] mb-1">
                  Poll interval (sec)
                </label>
                <input
                  id="cfg-git-poll"
                  type="number"
                  min={15}
                  max={3600}
                  value={draft.git.pollIntervalSec}
                  onChange={(e) =>
                    setDraft({
                      ...draft,
                      git: { ...draft.git, pollIntervalSec: Number(e.target.value) || 60 },
                    })
                  }
                  className={`${inputClass} font-mono tabular-nums`}
                />
              </div>
            </div>

            <div>
              <label htmlFor="cfg-ollama-url" className="block text-xs text-[#9BA3B0] mb-1">
                Local Ollama URL (loopback ports 11434–11440)
              </label>
              <input
                id="cfg-ollama-url"
                type="text"
                value={draft.ollama.endpoint}
                onChange={(e) =>
                  setDraft({ ...draft, ollama: { ...draft.ollama, endpoint: e.target.value } })
                }
                placeholder="http://127.0.0.1:11434"
                className={`${inputClass} font-mono`}
              />
            </div>
          </div>

          {/* Column 3: Automated Email Notifications */}
          <div className="p-5 space-y-3.5">
            <div className="flex items-center justify-between gap-2">
              <h3 className="text-sm font-semibold text-[#F3F5F8]">Email Notifications</h3>
              <span className="text-xs font-mono tabular-nums text-[#7B8494]">
                {emailStatus.sentCount} sent
              </span>
            </div>

            <div>
              <label htmlFor="cfg-email-to" className="block text-xs text-[#9BA3B0] mb-1">
                Recipient email
              </label>
              <input
                id="cfg-email-to"
                type="email"
                value={draft.email.recipientEmail}
                onChange={(e) =>
                  setDraft({ ...draft, email: { ...draft.email, recipientEmail: e.target.value } })
                }
                placeholder="you@domain.com"
                className={inputClass}
              />
            </div>

            <div className="grid grid-cols-3 gap-2">
              <div className="col-span-2">
                <label htmlFor="cfg-smtp-host" className="block text-xs text-[#9BA3B0] mb-1">
                  SMTP Host
                </label>
                <input
                  id="cfg-smtp-host"
                  type="text"
                  value={draft.email.smtpHost}
                  onChange={(e) =>
                    setDraft({ ...draft, email: { ...draft.email, smtpHost: e.target.value } })
                  }
                  placeholder="smtp.gmail.com"
                  className={`${inputClass} font-mono`}
                />
              </div>
              <div>
                <label htmlFor="cfg-smtp-port" className="block text-xs text-[#9BA3B0] mb-1">
                  Port
                </label>
                <input
                  id="cfg-smtp-port"
                  type="number"
                  value={draft.email.smtpPort}
                  onChange={(e) =>
                    setDraft({
                      ...draft,
                      email: { ...draft.email, smtpPort: Number(e.target.value) || 587 },
                    })
                  }
                  className={`${inputClass} font-mono tabular-nums`}
                />
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-x-4 gap-y-2 pt-1 text-xs text-[#9BA3B0]">
              <label className="inline-flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={draft.email.notifyOnCrash}
                  onChange={(e) =>
                    setDraft({
                      ...draft,
                      email: { ...draft.email, notifyOnCrash: e.target.checked },
                    })
                  }
                  className="accent-sky-400 rounded"
                />
                Crash alerts
              </label>
              <label className="inline-flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={draft.email.notifyOnDeploy}
                  onChange={(e) =>
                    setDraft({
                      ...draft,
                      email: { ...draft.email, notifyOnDeploy: e.target.checked },
                    })
                  }
                  className="accent-sky-400 rounded"
                />
                Git deploys
              </label>
              <label className="inline-flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={draft.email.notifyOnOllamaDown}
                  onChange={(e) =>
                    setDraft({
                      ...draft,
                      email: { ...draft.email, notifyOnOllamaDown: e.target.checked },
                    })
                  }
                  className="accent-sky-400 rounded"
                />
                Ollama offline
              </label>
            </div>
          </div>
        </div>
      </form>
    </section>
  );
}
