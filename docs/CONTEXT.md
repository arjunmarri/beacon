# Project Context — BeaconMac

This document captures the problem statement, product philosophy, and architectural trade-offs that shaped **BeaconMac** so contributors and future sessions can make consistent engineering decisions.

---

## Problem Statement
Local macOS developers building and running multiple Vite & Node.js applications alongside remote Git repositories, reverse proxies, local Ollama LLMs, and cloud AI/edge platforms (ChatGPT, Gemini, Claude, Cloudflare, Vercel, Supabase) often juggle terminal tabs, manual `git clone` / `npm install` / `npm run build` commands, NGINX configs, and startup scripts without a single glanceable control surface. BeaconMac solves this with an XAMPP-inspired traffic-light monitor, Built-In Node.js Server, Inbuilt NGINX Reverse Proxy, and local deployer built natively for macOS.

---

## Key Product Decisions

| Decision | Choice Made | Rationale |
| :--- | :--- | :--- |
| **Platform & Runtime** | Native Swift 5.10 + SwiftUI (macOS 14+) | Zero Electron/Chromium memory overhead, instant startup, native Menu Bar extra, and direct Apple App Store eligibility. |
| **Multi-App Model** | Array of `ManagedApp` records in `config.json` | Developers run multiple Vite/Node apps simultaneously; BeaconMac monitors external local apps on any local URL/port and never assumes or monitors itself. |
| **Built-In Node.js Server** | Zero-dependency `beacon-node-host.mjs` on `127.0.0.1:4173` | Lets developers load any static/built folder (`dist/`, `build/`, `out/`, `public/`) or local port proxy immediately without configuring external servers. |
| **Inbuilt NGINX Reverse Proxy** | User-space `beacon-nginx.sh` rooted at `~/beaconmac/nginx/` | Exposes any local app via path prefixes, `*.localhost` virtual hosts, WebSocket/HMR upgrades, or optional LAN (`0.0.0.0`) with zero `sudo` and zero impact on system NGINX files. |
| **Clone, Deps & Local Deploy** | App-Sandbox `NSUserUnixTask` scripts (10 embedded scripts) | Preserves `com.apple.security.app-sandbox = true` compliance for App Review while auditing/installing `git`/`node`/`npm`/`pnpm`/`yarn`/`bun`/`python3`/`uv`/`go`/`nginx`, building, and deploying locally. |
| **Logs, Auto-Scroll & Export** | In-app chronological consoles + Pause/Resume + per-entry Copy + `.txt`/`.json` Export + `Terminal.app` handoff | Makes debugging high-traffic builds and servers effortless while keeping every exported or copied line secret-redacted. |
| **Startup & Background Daemon** | Apple `launchd` (`~/Library/LaunchAgents`) + `SMAppService.mainApp` | Tightly coupled with macOS's native process manager (`launchctl load`/`unload`) with live `~/beaconmac/server.log` output, plus optional legacy `crontab`. |
| **Sleep Prevention** | Native IOKit `IOPMAssertion` + headless `caffeinate -s` + Energy Settings link | Keeps local servers and NGINX routes reachable while the display is off without violating Mac App Store Sandbox rules. |
| **Database & Login** | None — flat files (`activity.log`, `config.json`) | Keeps the app lightweight, inspectable with standard macOS tools, and frictionless on a personal workstation. |
| **Secret Storage & Cloud APIs** | Native macOS Keychain (`Security.framework`, `com.beaconmac.app`) | Users connect GitHub, OpenAI (ChatGPT), Gemini, Claude, OpenRouter, Groq, Custom OpenAI, Cloudflare, Vercel, and Supabase once inside Settings; zero `.env` files needed, zero-token verification probes, and all Cloud AI providers power **AI Help**. |
| **Web Preview Portal** | Plain self-contained `index.html` + minimal `server.ts` | Zero Vite/React build bloat in the repo; serves only the BeaconMac description, interactive preview, FAQ, versioned DMG downloads, and Swift Xcode project ZIP. |

---

## Design Language
- **Real-Time Dark & White (Light) Themes (`BeaconTheme.swift`)**:
  - **Dark Mode**: Obsidian canvas (`#080A0F` / `#0B0D10`), elevated charcoal cards (`#13161B`), hairline borders (`rgba(255,255,255,0.08)`).
  - **White (Light) Mode**: Clean bright canvas (`#F7F9FC`), crisp white cards (`#FFFFFF`), soft slate hairline borders (`#DDE4EE`).
- **Blue Section Headers**: High-contrast **Blue** section titles paired with a left accent bar (`BeaconSectionHeaderText`) across all main sections and modal sheets for effortless visual scanning in both themes.
- **Typography & Signals**: System SF Pro UI headings paired with monospaced tabular numerals (`monospacedDigit()`) for ports, latencies, HTTP status codes, and timestamps, plus semantic traffic-light indicators (emerald green, amber, rose red).
- **Minimalism**: No decorative pill clutter, no telemetry bloat — every managed app, proxy route, and service card exposes direct, actionable controls.

---

## Repository & Attribution
- **App Name**: BeaconMac
- **Repository**: https://github.com/arjunmarri/beacon
- **Designed by**: [SoroAI](https://soroai.com)
