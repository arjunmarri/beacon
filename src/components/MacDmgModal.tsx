import { Check, Code2, Copy, Download, HardDrive, Terminal, X } from 'lucide-react';
import { useState } from 'react';

interface MacDmgModalProps {
  open: boolean;
  onClose: () => void;
}

type ExportMode = 'swift' | 'dmg';

const SWIFT_TERMINAL_CMD =
  'cd ~/Downloads/BeaconMac && chmod +x Scripts/*.sh && ./Scripts/generate-xcode-project.sh';

const DMG_TERMINAL_CMD =
  'xattr -dr com.apple.quarantine ~/Downloads/Beacon-Mac && cd ~/Downloads/Beacon-Mac && bash Build-Mac-DMG.command';

export function MacDmgModal({ open, onClose }: MacDmgModalProps) {
  const [mode, setMode] = useState<ExportMode>('swift');
  const [downloading, setDownloading] = useState(false);
  const [downloadedMode, setDownloadedMode] = useState<ExportMode | null>(null);
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!open) return null;

  const terminalCmd = mode === 'swift' ? SWIFT_TERMINAL_CMD : DMG_TERMINAL_CMD;

  async function handleDownload() {
    setDownloading(true);
    setError(null);
    setDownloadedMode(null);
    try {
      const endpoint = mode === 'swift' ? '/api/mac-swift-kit' : '/api/mac-dmg-kit';
      const filename =
        mode === 'swift' ? 'Beacon-Swift-Xcode-Project.zip' : 'Beacon-Mac-DMG-Kit.zip';

      const res = await fetch(endpoint);
      if (!res.ok) {
        let msg = `Download failed (HTTP ${res.status}).`;
        try {
          const data = (await res.json()) as { error?: string };
          if (data.error) msg = data.error;
        } catch {
          // ignore non-JSON body
        }
        throw new Error(msg);
      }
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 5000);
      setDownloadedMode(mode);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unable to download macOS export.');
    } finally {
      setDownloading(false);
    }
  }

  async function handleCopyCommand() {
    try {
      await navigator.clipboard.writeText(terminalCmd);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard API may be restricted in some contexts
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-xs p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="mac-dmg-title"
      onClick={onClose}
    >
      <div
        className="w-full max-w-xl bg-[#13161B] border border-white/[0.1] rounded-xl overflow-hidden shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-4 border-b border-white/[0.08] flex items-center justify-between gap-4">
          <div className="flex items-center gap-2.5">
            {mode === 'swift' ? (
              <Code2 className="w-4 h-4 text-sky-400" />
            ) : (
              <HardDrive className="w-4 h-4 text-sky-400" />
            )}
            <h2 id="mac-dmg-title" className="text-base font-semibold text-[#F3F5F8]">
              Native macOS App Export
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

        {/* Mode Selector */}
        <div className="px-5 pt-4 flex items-center gap-2">
          <button
            type="button"
            onClick={() => {
              setMode('swift');
              setCopied(false);
              setError(null);
            }}
            className={`flex-1 px-3 py-2 text-xs font-medium rounded-lg border transition-colors whitespace-nowrap cursor-pointer ${
              mode === 'swift'
                ? 'bg-sky-500/15 text-[#F3F5F8] border-sky-400/40'
                : 'bg-[#0B0D10] text-[#9BA3B0] hover:text-[#F3F5F8] border-white/[0.08]'
            }`}
          >
            SwiftUI / Xcode (App Store)
          </button>
          <button
            type="button"
            onClick={() => {
              setMode('dmg');
              setCopied(false);
              setError(null);
            }}
            className={`flex-1 px-3 py-2 text-xs font-medium rounded-lg border transition-colors whitespace-nowrap cursor-pointer ${
              mode === 'dmg'
                ? 'bg-sky-500/15 text-[#F3F5F8] border-sky-400/40'
                : 'bg-[#0B0D10] text-[#9BA3B0] hover:text-[#F3F5F8] border-white/[0.08]'
            }`}
          >
            Electron .dmg (Direct Install)
          </button>
        </div>

        <div className="p-5 space-y-5 text-sm text-[#C4CBD6]">
          {mode === 'swift' ? (
            <>
              <p className="leading-relaxed">
                Complete native <span className="text-[#F3F5F8] font-medium">Swift 5.10 + SwiftUI</span>{' '}
                macOS 14+ project configured with{' '}
                <span className="font-mono text-xs text-[#F3F5F8]">App Sandbox</span>,{' '}
                <span className="font-mono text-xs text-[#F3F5F8]">macOS Keychain</span> secret
                storage, Menu Bar companion, flat-file logs, and{' '}
                <span className="font-mono text-xs text-[#F3F5F8]">NSUserUnixTask</span> restart
                hooks for Apple App Store submission.
              </p>

              <div className="space-y-2.5 text-xs text-[#9BA3B0]">
                <div className="flex items-start gap-2.5">
                  <span className="font-mono text-[#F3F5F8] shrink-0">01.</span>
                  <span>
                    Download &amp; unzip{' '}
                    <span className="font-mono text-[#F3F5F8]">Beacon-Swift-Xcode-Project.zip</span>{' '}
                    into <span className="font-mono text-[#F3F5F8]">~/Downloads/BeaconMac</span>.
                  </span>
                </div>
                <div className="flex items-start gap-2.5">
                  <span className="font-mono text-[#F3F5F8] shrink-0">02.</span>
                  <span>
                    Run the Terminal command below to generate{' '}
                    <span className="font-mono text-[#F3F5F8]">Beacon.xcodeproj</span> and open it
                    in Xcode (or open <span className="font-mono text-[#F3F5F8]">Package.swift</span>{' '}
                    directly).
                  </span>
                </div>
                <div className="flex items-start gap-2.5">
                  <span className="font-mono text-[#F3F5F8] shrink-0">03.</span>
                  <span>
                    Select your Apple Developer Team &amp; Bundle ID in{' '}
                    <span className="text-[#F3F5F8]">Signing &amp; Capabilities</span>, add a
                    1024×1024 AppIcon, then click{' '}
                    <span className="text-[#F3F5F8]">Product → Archive → Distribute App</span> to
                    upload to App Store Connect.
                  </span>
                </div>
              </div>
            </>
          ) : (
            <>
              <p className="leading-relaxed">
                macOS quarantines unsigned scripts downloaded from a browser (&ldquo;Apple could not
                verify&rdquo;). Run the single Terminal command below after unzipping to clear the
                quarantine flag and build your local{' '}
                <span className="font-mono text-xs text-[#F3F5F8]">.dmg</span> cleanly.
              </p>

              <div className="space-y-2.5 text-xs text-[#9BA3B0]">
                <div className="flex items-start gap-2.5">
                  <span className="font-mono text-[#F3F5F8] shrink-0">01.</span>
                  <span>
                    Download and unzip{' '}
                    <span className="font-mono text-[#F3F5F8]">Beacon-Mac-DMG-Kit.zip</span> in{' '}
                    <span className="font-mono text-[#F3F5F8]">~/Downloads</span>.
                  </span>
                </div>
                <div className="flex items-start gap-2.5">
                  <span className="font-mono text-[#F3F5F8] shrink-0">02.</span>
                  <span>Open Terminal and paste the command below to build the installer.</span>
                </div>
                <div className="flex items-start gap-2.5">
                  <span className="font-mono text-[#F3F5F8] shrink-0">03.</span>
                  <span>
                    Open <span className="font-mono text-[#F3F5F8]">release/Beacon-1.0.0-*.dmg</span>{' '}
                    and drag <span className="font-mono text-[#F3F5F8]">Beacon.app</span> into
                    Applications.
                  </span>
                </div>
              </div>
            </>
          )}

          <div className="bg-[#0B0D10] border border-white/[0.08] rounded-lg p-3.5 space-y-2.5">
            <div className="flex items-center justify-between gap-2">
              <span className="inline-flex items-center gap-1.5 text-xs text-[#9BA3B0]">
                <Terminal className="w-3.5 h-3.5 text-sky-400" />
                {mode === 'swift'
                  ? 'macOS Terminal (generate Beacon.xcodeproj & open Xcode)'
                  : 'macOS Terminal (clears Gatekeeper quarantine & builds .dmg)'}
              </span>
              <button
                type="button"
                onClick={() => void handleCopyCommand()}
                className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium text-[#D9DFE8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-md transition-colors whitespace-nowrap shrink-0 cursor-pointer"
              >
                {copied ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
                {copied ? 'Copied' : 'Copy'}
              </button>
            </div>
            <pre className="font-mono text-xs text-[#D9DFE8] whitespace-pre-wrap break-all select-all">
              {terminalCmd}
            </pre>
          </div>

          {error && (
            <div
              role="alert"
              className="px-3.5 py-2.5 text-xs text-rose-200 bg-rose-500/10 border border-rose-500/25 rounded-lg"
            >
              {error}
            </div>
          )}

          <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-end gap-2 pt-2 border-t border-white/[0.07]">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs font-medium text-[#9BA3B0] hover:text-[#F3F5F8] bg-[#1B1F27] hover:bg-[#232934] border border-white/[0.08] rounded-lg transition-colors whitespace-nowrap cursor-pointer"
            >
              Close
            </button>
            <button
              type="button"
              disabled={downloading}
              onClick={() => void handleDownload()}
              className="inline-flex items-center justify-center gap-2 px-4 py-2 text-xs font-semibold text-[#0B0D10] bg-[#38BDF8] hover:bg-[#7DD3FC] rounded-lg transition-colors whitespace-nowrap cursor-pointer disabled:opacity-60"
            >
              {downloadedMode === mode ? (
                <Check className="w-3.5 h-3.5" />
              ) : (
                <Download className="w-3.5 h-3.5" />
              )}
              {downloading
                ? 'Packaging...'
                : mode === 'swift'
                  ? downloadedMode === 'swift'
                    ? 'Downloaded Swift Xcode Project'
                    : 'Download Swift Xcode Project (.zip)'
                  : downloadedMode === 'dmg'
                    ? 'Downloaded Mac .dmg Kit'
                    : 'Download Mac .dmg Kit (.zip)'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
