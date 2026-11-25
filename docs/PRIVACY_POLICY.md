# BeaconMac Privacy Policy (Placeholder)

> **App Store Connect Action Required:** Replace the bracketed placeholders (`[YOUR_COMPANY_OR_DEVELOPER_NAME]`, `[YOUR_SUPPORT_EMAIL]`, `[YOUR_PRIVACY_POLICY_URL]`) and host this policy at a public HTTPS URL before submitting BeaconMac to the Mac App Store.

**Effective Date:** [YYYY-MM-DD]  
**Developer:** [YOUR_COMPANY_OR_DEVELOPER_NAME]  
**Contact:** [YOUR_SUPPORT_EMAIL]  
**Website:** [YOUR_PRIVACY_POLICY_URL]

---

## 1. Overview
BeaconMac is a local-first macOS developer utility designed to monitor local web applications, reverse proxies, and development services on your Mac. We do not collect, sell, rent, or track personal data.

## 2. Data Stored Locally on Your Mac
All configuration files, local application paths, activity logs, and runtime state are stored strictly on your device inside macOS Application Support (`~/Library/Application Support/Beacon/`).

* **Credentials & API Tokens:** Any GitHub, Cloudflare, or cloud provider API tokens you choose to enter are stored encrypted in your macOS Keychain (`Security.framework`) and are never written to plaintext configuration files or transmitted to the developer.
* **Logs:** Activity and server logs remain local to your Mac and are never uploaded to third-party AI services or developer servers.

## 3. Optional User-Initiated Third-Party Connections
BeaconMac only initiates outbound network requests to external services when you explicitly configure and trigger them (for example, checking a GitHub repository, verifying a cloud API token you entered, or starting a Cloudflare Tunnel). Those requests go directly from your Mac to the third-party provider you selected and are governed by that provider's privacy policy.

## 4. Tracking, Analytics & Crash Reporting
* **Tracking:** BeaconMac does not track you across apps or websites (`NSPrivacyTracking = false`).
* **Analytics / Telemetry:** BeaconMac includes no third-party analytics SDKs, advertising SDKs, or behavioral telemetry.

## 5. Data Deletion
You can remove stored credentials at any time using the **Clear** buttons in BeaconMac Settings (which deletes entries from your macOS Keychain) and clear local activity logs via **Clear Logs** or by deleting BeaconMac's Application Support folder.

## 6. Contact
If you have questions about this Privacy Policy, contact us at **[YOUR_SUPPORT_EMAIL]**.
