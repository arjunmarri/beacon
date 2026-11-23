# Project Context — BeaconMac

This document captures the problem statement, product philosophy, and architectural trade-offs that shaped **BeaconMac** so contributors and future sessions can make consistent engineering decisions.

---

## Problem Statement
Local macOS developers building and running multiple Vite & Node.js applications alongside remote Git repositories, local Ollama LLMs, and Anthropic Claude integrations often juggle terminal tabs, manual `git clone` / `npm install` / `npm run build` commands, and startup scripts without a single glanceable control surface. BeaconMac solves this with an XAMPP-inspired traffic-light monitor and local deployer built natively for macOS.

---

## Key Product Decisions

| Decision | Choice Made | Rationale |
| :--- | :--- | :--- |
| **Platform & Runtime** | Native Swift 5.10 + SwiftUI (macOS 14+) | Zero Electron/Chromium memory overhead, instant startup, native Menu Bar extra, and direct Apple App Store eligibility. |
| **Multi-App Model** | Array of `ManagedApp` records in `config.json` | Developers run multiple Vite/Node apps simultaneously; BeaconMac monitors external local apps on any local URL/port and never assumes or monitors itself. |
| **Clone, Deps & Local Deploy** | App-Sandbox `NSUserUnixTask` scripts (`beacon-deploy.sh`, `beacon-check-deps.sh`) | Preserves `com.apple.security.app-sandbox = true` compliance for App Review while checking `git`/`node`/`npm`/`pnpm`/`yarn`/`bun`, installing libraries, building, and deploying locally. |
| **Terminal Integration** | In-app stdout/stderr console + `NSWorkspace` handoff to `Terminal.app` | Lets users inspect live build output inside BeaconMac or jump straight into macOS `Terminal.app` at any app's folder / log tail. |
| **Startup & Background Daemon** | Apple `launchd` (`~/Library/LaunchAgents`) + `SMAppService.mainApp` | Tightly coupled with macOS's native process manager (`launchctl load`/`unload`) with live `~/beaconmac/server.log` output, plus optional legacy `crontab`. |
| **Sleep Prevention** | Native IOKit `IOPMAssertion` + headless `caffeinate -s` + Energy Settings link | Keeps local Vite/Node servers reachable while the display is off without violating Mac App Store Sandbox rules. |
| **Database & Login** | None — flat files (`activity.log`, `config.json`) | Keeps the app lightweight, inspectable with standard macOS tools, and frictionless on a personal workstation. |
| **Secret Storage** | Native macOS Keychain (`Security.framework`) | Users paste GitHub and Claude keys directly into the app once; no `.env` files needed and secrets stay encrypted at rest. |
| **Claude Health Check** | `GET https://api.anthropic.com/v1/models` | Verifies API key validity, reachability, latency, and model availability at zero token cost. |
| **Web Preview Portal** | Plain self-contained `index.html` + minimal `server.ts` | Zero Vite/React build bloat in the repo; serves only the BeaconMac description, GitHub link, and Swift Xcode project ZIP download. |

---

## Design Language
- **Palette**: Dark obsidian canvas (`#080A0F` / `#0B0D10`), elevated charcoal cards (`#13161B`), hairline borders (`rgba(255,255,255,0.08)`), sky-blue primary actions (`#38BDF8`), and semantic traffic-light indicators (emerald green, amber, rose red).
- **Typography**: System SF Pro / sans-serif UI headings paired with monospaced tabular numerals (`monospacedDigit()`) for ports, latencies, HTTP status codes, and timestamps.
- **Minimalism**: No decorative pill tags, no telemetry bloat — every managed app and service card exposes direct, actionable controls.

---

## Repository & Attribution
- **App Name**: BeaconMac
- **Repository**: https://github.com/arjunmarri/beacon
- **Designed by**: [SoroAI](https://soroai.com)
