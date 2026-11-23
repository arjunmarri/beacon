export type TrafficLightColor = 'green' | 'amber' | 'red';

export type LogSource = 'vite' | 'git' | 'ollama' | 'claude' | 'email' | 'system';
export type LogLevel = 'info' | 'warn' | 'error';

export interface LogEntry {
  id: string;
  timestamp: string;
  source: LogSource;
  level: LogLevel;
  message: string;
}

export interface ViteProcessStatus {
  light: TrafficLightColor;
  state: 'running' | 'restarting' | 'crashed' | 'stopped';
  pid: number | null;
  port: number;
  monitorUrl: string;
  httpStatus: number | null;
  responseTimeMs: number | null;
  probeHealthy: boolean;
  lastProbeAt: string | null;
  uptimeSeconds: number;
  memoryMb: number;
  restartCount: number;
  lastCrashAt: string | null;
  lastExitCode: number | null;
  workingDir: string;
  commandPreset: ViteCommandPreset;
  autoRestart: boolean;
}

export type ViteCommandPreset = 'demo-worker' | 'npm-dev' | 'npx-vite';

export interface GitRepoSummary {
  fullName: string;
  cloneUrl: string;
  defaultBranch: string;
  private: boolean;
  permissions: string[];
}

export interface GitAccountStatus {
  connected: boolean;
  provider: 'github' | 'local-git' | null;
  method: 'oauth' | 'gh-cli' | 'osxkeychain' | 'token' | 'env' | null;
  username: string | null;
  displayName: string | null;
  email: string | null;
  scopes: string[];
  connectedAt: string | null;
  keyHint: string | null;
  oauthConfigured: boolean;
  callbackUrl: string;
  repos: GitRepoSummary[];
}

export interface GitDeployStatus {
  light: TrafficLightColor;
  state: 'synced' | 'deploying' | 'error' | 'paused';
  repoUrl: string;
  branch: string;
  commitHash: string;
  commitMessage: string;
  lastCheckedAt: string | null;
  lastDeployedAt: string | null;
  autoDeploy: boolean;
  pollIntervalSec: number;
  deployCount: number;
  mode: 'git' | 'simulated-local';
  remoteConfigured: boolean;
  lastError: string | null;
}

export interface OllamaModelInfo {
  name: string;
  parameterSize: string;
  quantization: string;
  sizeGb: number;
  contextLength: number;
  family: string;
}

export interface OllamaStatus {
  light: TrafficLightColor;
  state: 'connected' | 'switching' | 'disconnected';
  endpoint: string;
  connectedMode: 'live' | 'local-preview';
  activeModel: string;
  models: OllamaModelInfo[];
  latencyMs: number;
  vramUsedGb: number;
  vramTotalGb: number;
  tokensPerSec: number;
  contextLength: number;
  lastCheckedAt: string | null;
}

export interface ClaudeModelInfo {
  id: string;
  displayName: string;
  createdAt: string | null;
}

export interface ClaudeStatus {
  light: TrafficLightColor;
  state: 'connected' | 'checking' | 'error' | 'unconfigured';
  connected: boolean;
  keyHint: string | null;
  keySource: 'manual' | 'env' | null;
  httpStatus: number | null;
  latencyMs: number | null;
  activeModel: string;
  models: ClaudeModelInfo[];
  lastCheckedAt: string | null;
  lastError: string | null;
}

export interface EmailAlertConfig {
  enabled: boolean;
  recipientEmail: string;
  smtpHost: string;
  smtpPort: number;
  smtpUser: string;
  smtpFrom: string;
  smtpConfiguredOnServer: boolean;
  notifyOnCrash: boolean;
  notifyOnDeploy: boolean;
  notifyOnOllamaDown: boolean;
  sentCount: number;
  lastSentAt: string | null;
}

export interface BeaconConfig {
  vite: {
    workingDir: string;
    commandPreset: ViteCommandPreset;
    port: number;
    monitorUrl: string;
    autoRestart: boolean;
    maxRestarts: number;
  };
  git: {
    repoUrl: string;
    branch: string;
    autoDeploy: boolean;
    pollIntervalSec: number;
  };
  ollama: {
    endpoint: string;
    activeModel: string;
  };
  email: {
    enabled: boolean;
    recipientEmail: string;
    smtpHost: string;
    smtpPort: number;
    smtpUser: string;
    smtpFrom: string;
    notifyOnCrash: boolean;
    notifyOnDeploy: boolean;
    notifyOnOllamaDown: boolean;
  };
}

export interface SystemSnapshot {
  platform: string;
  hostname: string;
  logFilePath: string;
  logFileBytes: number;
  logEntryCount: number;
  configFilePath: string;
  vite: ViteProcessStatus;
  git: GitDeployStatus;
  gitAccount: GitAccountStatus;
  ollama: OllamaStatus;
  claude: ClaudeStatus;
  email: EmailAlertConfig;
}
