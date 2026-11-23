# Changelog

All notable changes to **BeaconMac** are documented in this file.  
Versioning follows [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`).

---

## [1.0.0] — 2026-11-23

### Added
- **Multi-App Local Deployment & Monitoring Hub**: Monitor and deploy unlimited locally hosted Vite, Node.js, Next.js, and custom applications across any localhost or `.local` port.
- **Clone → Check Deps → Build → Deploy Pipeline**: Automatically checks `git`/`node`/`npm`/`pnpm`/`yarn`/`bun`, clones or pulls remote Git repositories, installs missing `node_modules`, builds, and launches locally.
- **Apple `launchd` Background Supervision**: Install, load, inspect, and unload `~/Library/LaunchAgents/com.beaconmac.app.supervisor.plist` directly from BeaconMac or the Menu Bar.
- **Persistent Live Logs**: Streams supervisor logs to `~/beaconmac/server.log` and per-app logs to `~/beaconmac/logs/<app>-<port>.log` with one-click `tail -f` Terminal launch.
- **Native macOS Sleep Prevention**: Holds an App-Sandbox-safe IOKit power assertion while running, invokes `caffeinate -s` automatically under `launchd`, and links directly to macOS Energy Settings.
- **Encrypted macOS Keychain Storage**: Direct in-app key paste for GitHub Personal Access Tokens and Anthropic Claude API keys (`/v1/models` zero-token health check), plus local Ollama LLM monitoring and model switching.
- **Versioned Universal DMG Pipeline**: Automated macOS `.dmg` packaging (`Scripts/build-dmg.sh`) and GitHub Actions `macos-14` release workflow (`release-dmg.yml`).
