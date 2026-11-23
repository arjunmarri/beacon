# Project Context — BeaconMac

This document captures the problem statement, product philosophy, and architectural trade-offs that shaped **BeaconMac** so contributors and future sessions can make consistent engineering decisions.

---

## Problem Statement
Local macOS developers running Node.js / Vite applications alongside remote Git repositories, local Ollama LLMs, and Anthropic Claude integrations often juggle multiple terminal tabs without a single glanceable control surface. BeaconMac solves this with an XAMPP-inspired traffic-light monitor built natively for macOS.

---

## Key Product Decisions

| Decision | Choice Made | Rationale |
| :--- | :--- | :--- |
| **Platform & Runtime** | Native Swift 5.10 + SwiftUI (macOS 14+) | Zero Electron/Chromium memory overhead, instant startup, native Menu Bar extra, and direct Apple App Store eligibility. |
| **Database** | None — flat files (`activity.log`, `config.json`) | Keeps the app lightweight, inspectable with standard macOS tools, and portable with zero database setup. |
| **Authentication / Login** | None | Single-user local Mac utility; adding an app login screen adds friction without security value on a personal workstation. |
| **Secret Storage** | Native macOS Keychain (`Security.framework`) | Users paste GitHub and Claude keys directly into the app once; no `.env` files needed and secrets are encrypted at rest. |
| **App Store Process Execution** | `NSUserUnixTask` scripts in `~/Library/Application Scripts/<bundle-id>/` | Preserves `com.apple.security.app-sandbox = true` compliance required by Apple App Review while still supporting local Vite restarts and `git pull`. |
| **Claude Health Check** | `GET https://api.anthropic.com/v1/models` | Verifies API key validity, network reachability, latency, and model availability at zero token cost. |
| **Multi-Port Localhost Monitoring** | Editable inline URL field (`http://localhost:<port>`) | Developers frequently run multiple local apps across ports (3000, 4173, 5173, 8080) and need fast switching. |
| **Web Preview Portal** | Plain self-contained `index.html` + minimal `server.ts` | No Vite/React build bloat in the repo; serves only the BeaconMac description, GitHub link, and Swift Xcode project ZIP download. |

---

## Design Language
- **Palette**: Dark obsidian canvas (`#080A0F` / `#0B0D10`), elevated charcoal cards (`#13161B`), hairline borders (`rgba(255,255,255,0.08)`), sky-blue primary actions (`#38BDF8`), and semantic traffic-light indicators (emerald green, amber, rose red).
- **Typography**: System SF Pro / sans-serif UI headings paired with monospaced tabular numerals (`monospacedDigit()`) for ports, latencies, HTTP status codes, and timestamps.
- **Minimalism**: No decorative pill tags, no telemetry bloat, no nested modal mazes — every traffic light has its inline controls directly accessible.

---

## Repository & Attribution
- **App Name**: BeaconMac
- **Repository**: https://github.com/arjunmarri/beacon
- **Designed by**: [SoroAI](https://soroai.com)
