# Liquid Glass + Undersea Stingray Styling Guide

A self-contained, zero-dependency design system and ambient canvas guide for reusing this **Light-default Liquid Glass UI**, **floating transparent glass navigation menu**, and **interactive translucent undersea glass stingray** on any website.

---

## 1. Visual Architecture & Layering

| Layer | Element | `z-index` | Purpose |
| :--- | :--- | :---: | :--- |
| **Backdrop Canvas** | `<canvas id="bg-canvas">` | `0` | Fixed full-viewport canvas rendering ambient aurora pools, marine motes, water ripples, and the interactive translucent glass stingrays (`pointer-events: none`). |
| **Subtle Grid Overlay** | `body::before` | `0` | Soft radial-masked hairline grid (`64px × 64px`) for spatial structure. |
| **Main Glass Stage** | `.glass-stage` / `.tab-panel` | `1` | Slightly transparent frosted glass surface (`rgba(255, 255, 255, 0.34)` in Light, `blur(12px)`) with specular edge refraction so the swimming stingray stays visible behind content while text remains crisp. |
| **Floating Glass Menu** | `.top-nav` / `.top-nav-inner` | `30` | Transparent outer sticky wrapper holding a floating frosted glass capsule (`rgba(255, 255, 255, 0.24)`, `blur(28px) saturate(210%)`). |

---

## 2. Typography & HTML Head Setup

Set `data-theme="light"` on `<html>` so Light Liquid Glass renders immediately on first paint with zero dark flash.

```html
<!doctype html>
<html lang="en" data-theme="light">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Your Site Title</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap"
      rel="stylesheet"
    />
  </head>
  <body>
    <canvas id="bg-canvas" aria-hidden="true"></canvas>
    <!-- Floating glass menu + transparent glass stage go here -->
  </body>
</html>
```

---

## 3. Color Tokens & Liquid Glass CSS

Copy this stylesheet directly into your site's `<style>` block or global CSS file. Light mode is the default; toggling `data-theme="dark"` on `<html>` switches all surfaces, specular rims, text contrast, and the stingray palette in real time.

```css
/* ==========================================================================
   1. Theme Tokens — Light (Default) & Dark Liquid Glass
   ========================================================================== */
:root,
[data-theme='light'] {
  --bg-base: #eef4fc;
  --bg-canvas:
    radial-gradient(64% 56% at 14% 8%, rgba(56, 189, 248, 0.24) 0%, rgba(56, 189, 248, 0) 68%),
    radial-gradient(58% 54% at 88% 14%, rgba(99, 102, 241, 0.20) 0%, rgba(99, 102, 241, 0) 66%),
    radial-gradient(60% 50% at 50% 96%, rgba(20, 184, 166, 0.16) 0%, rgba(20, 184, 166, 0) 65%),
    linear-gradient(180deg, #f7faff 0%, #eef4fc 55%, #e6eef9 100%);
  --grid-line: rgba(15, 23, 42, 0.032);

  /* Transparent Floating Glass Menu */
  --glass-menu-bg: rgba(255, 255, 255, 0.24);
  --glass-menu-border: rgba(255, 255, 255, 0.62);
  --glass-menu-shadow: 0 12px 36px rgba(15, 23, 42, 0.08), inset 0 1px 0 rgba(255, 255, 255, 0.85);
  --seg-track: rgba(255, 255, 255, 0.22);
  --seg-thumb: rgba(255, 255, 255, 0.68);
  --seg-thumb-border: rgba(255, 255, 255, 0.90);

  /* Translucent Main Content Stage & Cards (shows background creature clearly) */
  --glass-surface: rgba(255, 255, 255, 0.34);
  --glass-surface-strong: rgba(255, 255, 255, 0.62);
  --glass-card: rgba(255, 255, 255, 0.34);
  --glass-card-hover: rgba(255, 255, 255, 0.60);
  --glass-well: rgba(241, 246, 255, 0.44);
  --glass-border: rgba(148, 163, 184, 0.32);
  --glass-border-strong: rgba(59, 130, 246, 0.34);

  /* Optical Specular Rim & Pointer Glint */
  --specular-rim: linear-gradient(
    135deg,
    rgba(255, 255, 255, 0.98) 0%,
    rgba(147, 197, 253, 0.55) 42%,
    rgba(148, 163, 184, 0.35) 100%
  );
  --specular-sheen: radial-gradient(
    520px circle at var(--mx, 50%) var(--my, 0%),
    rgba(37, 99, 235, 0.08),
    transparent 62%
  );
  --shadow-stage: 0 28px 80px rgba(15, 23, 42, 0.09), 0 6px 20px rgba(15, 23, 42, 0.05);
  --shadow-card: 0 10px 26px rgba(15, 23, 42, 0.055);

  /* Typography & Accent */
  --text-primary: #0b1324;
  --text-body: #334155;
  --text-muted: #586982;
  --accent: #1d4ed8;
  --accent-strong: #2563eb;
  --accent-ink: #ffffff;
  --accent-btn-bg: linear-gradient(180deg, #3b82f6 0%, #1d4ed8 100%);
  --accent-btn-hover: linear-gradient(180deg, #2563eb 0%, #1e40af 100%);
  --accent-glow: rgba(37, 99, 235, 0.26);
  --code-bg: rgba(15, 23, 42, 0.055);
  --code-text: #1e3a8a;
}

[data-theme='dark'] {
  --bg-base: #06080f;
  --bg-canvas:
    radial-gradient(62% 54% at 14% 8%, rgba(56, 189, 248, 0.22) 0%, rgba(56, 189, 248, 0) 68%),
    radial-gradient(56% 52% at 88% 16%, rgba(99, 102, 241, 0.20) 0%, rgba(99, 102, 241, 0) 66%),
    radial-gradient(58% 48% at 52% 96%, rgba(16, 185, 129, 0.12) 0%, rgba(16, 185, 129, 0) 65%),
    linear-gradient(180deg, #0a0f1c 0%, #060911 55%, #05070d 100%);
  --grid-line: rgba(255, 255, 255, 0.025);

  --glass-menu-bg: rgba(14, 20, 34, 0.28);
  --glass-menu-border: rgba(255, 255, 255, 0.16);
  --glass-menu-shadow: 0 14px 40px rgba(0, 0, 0, 0.36), inset 0 1px 0 rgba(255, 255, 255, 0.24);
  --seg-track: rgba(255, 255, 255, 0.045);
  --seg-thumb: rgba(255, 255, 255, 0.14);
  --seg-thumb-border: rgba(255, 255, 255, 0.28);

  --glass-surface: rgba(14, 20, 34, 0.38);
  --glass-surface-strong: rgba(14, 19, 31, 0.62);
  --glass-card: rgba(255, 255, 255, 0.036);
  --glass-card-hover: rgba(255, 255, 255, 0.068);
  --glass-well: rgba(6, 9, 16, 0.44);
  --glass-border: rgba(255, 255, 255, 0.11);
  --glass-border-strong: rgba(255, 255, 255, 0.18);

  --specular-rim: linear-gradient(
    135deg,
    rgba(255, 255, 255, 0.34) 0%,
    rgba(125, 211, 252, 0.14) 38%,
    rgba(255, 255, 255, 0.05) 100%
  );
  --specular-sheen: radial-gradient(
    520px circle at var(--mx, 50%) var(--my, 0%),
    rgba(125, 211, 252, 0.11),
    transparent 62%
  );
  --shadow-stage: 0 32px 90px rgba(0, 0, 0, 0.58), 0 8px 26px rgba(0, 0, 0, 0.36);
  --shadow-card: 0 12px 32px rgba(0, 0, 0, 0.28);

  --text-primary: #f8fafc;
  --text-body: #b8c4d9;
  --text-muted: #7f8ea8;
  --accent: #38bdf8;
  --accent-strong: #7dd3fc;
  --accent-ink: #05111f;
  --accent-btn-bg: linear-gradient(180deg, #6ed4ff 0%, #2aa8f5 100%);
  --accent-btn-hover: linear-gradient(180deg, #8ee0ff 0%, #38bdf8 100%);
  --accent-glow: rgba(56, 189, 248, 0.34);
  --code-bg: rgba(255, 255, 255, 0.055);
  --code-text: #d7e8ff;
}

/* ==========================================================================
   2. Base Canvas & Subtle Radial Grid
   ========================================================================== */
*, *::before, *::after { box-sizing: border-box; }

html, body {
  margin: 0;
  padding: 0;
  min-height: 100%;
  background-color: var(--bg-base);
  color: var(--text-primary);
  font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, 'SF Pro Display', system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
  transition: background-color 240ms ease, color 240ms ease;
}

body {
  position: relative;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  overflow-x: hidden;
  background: var(--bg-canvas);
}

#bg-canvas {
  position: fixed;
  inset: 0;
  width: 100%;
  height: 100%;
  z-index: 0;
  pointer-events: none;
  display: block;
}

body::before {
  content: '';
  position: fixed;
  inset: 0;
  z-index: 0;
  pointer-events: none;
  background-image:
    linear-gradient(var(--grid-line) 1px, transparent 1px),
    linear-gradient(90deg, var(--grid-line) 1px, transparent 1px);
  background-size: 64px 64px;
  mask-image: radial-gradient(ellipse 78% 66% at 50% 40%, #000 12%, transparent 84%);
  -webkit-mask-image: radial-gradient(ellipse 78% 66% at 50% 40%, #000 12%, transparent 84%);
}

/* ==========================================================================
   3. Floating Transparent Liquid Glass Navigation Menu
   ========================================================================== */
.top-nav {
  position: sticky;
  top: 0;
  z-index: 30;
  width: 100%;
  padding: 14px 20px 0;
  background: transparent;
}

.top-nav-inner {
  max-width: 1060px;
  margin: 0 auto;
  padding: 10px 18px;
  border-radius: 18px;
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  gap: 16px;
  background: var(--glass-menu-bg);
  border: 1px solid var(--glass-menu-border);
  box-shadow: var(--glass-menu-shadow);
  backdrop-filter: blur(28px) saturate(210%);
  -webkit-backdrop-filter: blur(28px) saturate(210%);
}

.nav-segmented {
  position: relative;
  display: inline-flex;
  align-items: center;
  padding: 4px;
  border-radius: 999px;
  background: var(--seg-track);
  border: 1px solid var(--glass-menu-border);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.45);
  backdrop-filter: blur(22px) saturate(200%);
  -webkit-backdrop-filter: blur(22px) saturate(200%);
}

.nav-seg-thumb {
  position: absolute;
  top: 4px;
  bottom: 4px;
  left: 4px;
  border-radius: 999px;
  background: var(--seg-thumb);
  border: 1px solid var(--seg-thumb-border);
  box-shadow: 0 4px 14px rgba(15, 23, 42, 0.10), inset 0 1px 0 rgba(255, 255, 255, 0.85);
  transition: transform 340ms cubic-bezier(0.22, 1, 0.36, 1), width 340ms cubic-bezier(0.22, 1, 0.36, 1);
  pointer-events: none;
  z-index: 0;
}

.nav-link {
  position: relative;
  z-index: 1;
  padding: 7px 18px;
  border-radius: 999px;
  font-size: 13.5px;
  font-weight: 600;
  color: var(--text-muted);
  text-decoration: none;
  white-space: nowrap;
  transition: color 180ms ease;
}

.nav-link:hover,
.nav-link.active { color: var(--text-primary); }

/* ==========================================================================
   4. Slightly Transparent Liquid Glass Main Panel (with Specular Rim & Glint)
   ========================================================================== */
.stage {
  position: relative;
  z-index: 1;
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 32px 24px 28px;
}

.glass-panel {
  position: relative;
  width: 100%;
  max-width: 1060px;
  padding: 38px 40px 32px;
  border-radius: 24px;
  background: var(--glass-surface);
  backdrop-filter: blur(12px) saturate(165%);
  -webkit-backdrop-filter: blur(12px) saturate(165%);
  box-shadow: var(--shadow-stage), inset 0 1px 0 rgba(255, 255, 255, 0.34);
  overflow: hidden;
}

/* Specular Edge Refraction */
.glass-panel::before {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  padding: 1px;
  background: var(--specular-rim);
  -webkit-mask: linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0);
  -webkit-mask-composite: xor;
  mask-composite: exclude;
  pointer-events: none;
  z-index: 2;
}

/* Subtle Pointer-Tracked Specular Glint */
.glass-panel::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  background: var(--specular-sheen);
  pointer-events: none;
  z-index: 0;
}

.glass-panel > * {
  position: relative;
  z-index: 1;
}

/* ==========================================================================
   5. Inner Glass Cards & Tactile Buttons
   ========================================================================== */
.glass-card {
  padding: 18px;
  border-radius: 16px;
  background: var(--glass-card);
  border: 1px solid var(--glass-border);
  box-shadow: var(--shadow-card), inset 0 1px 0 rgba(255, 255, 255, 0.14);
  transition: transform 220ms cubic-bezier(0.22, 1, 0.36, 1), background-color 180ms ease, border-color 180ms ease;
}

.glass-card:hover {
  transform: translateY(-2px);
  background: var(--glass-card-hover);
  border-color: var(--glass-border-strong);
}

.btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 12px 20px;
  border-radius: 12px;
  font-size: 14px;
  font-weight: 600;
  text-decoration: none;
  white-space: nowrap;
  cursor: pointer;
  border: none;
  font-family: inherit;
  transition: transform 200ms cubic-bezier(0.22, 1, 0.36, 1), filter 160ms ease, background-color 160ms ease;
}

.btn-primary {
  background: var(--accent-btn-bg);
  color: var(--accent-ink);
  box-shadow: 0 10px 26px var(--accent-glow), inset 0 1px 0 rgba(255, 255, 255, 0.55);
}

.btn-primary:hover {
  background: var(--accent-btn-hover);
  transform: translateY(-1.5px);
}

.btn-secondary {
  background: var(--glass-card);
  color: var(--text-primary);
  border: 1px solid var(--glass-border);
  backdrop-filter: blur(14px);
  -webkit-backdrop-filter: blur(14px);
}

.btn-secondary:hover {
  background: var(--glass-card-hover);
  border-color: var(--glass-border-strong);
  transform: translateY(-1.5px);
}

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## 4. Theme Switcher & Specular Glint JS

Drop this script before `</body>` to persist Light/Dark toggles and power the subtle pointer glint across `.glass-panel` containers:

```js
/* Light (default) / Dark Theme Persistence */
(function () {
  const root = document.documentElement;
  const toggleBtn = document.getElementById('theme-toggle');
  const STORAGE_KEY = 'liquid-glass-theme';

  function applyTheme(theme) {
    root.setAttribute('data-theme', theme);
    try { localStorage.setItem(STORAGE_KEY, theme); } catch (_) {}
  }

  let initial = 'light';
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved === 'light' || saved === 'dark') initial = saved;
  } catch (_) {}
  applyTheme(initial);

  if (toggleBtn) {
    toggleBtn.addEventListener('click', () => {
      const next = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
      applyTheme(next);
    });
  }
})();

/* Pointer-Tracked Specular Glint on Glass Panels */
(function () {
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  document.querySelectorAll('.glass-panel').forEach((panel) => {
    panel.addEventListener('pointermove', (e) => {
      const r = panel.getBoundingClientRect();
      panel.style.setProperty('--mx', (((e.clientX - r.left) / r.width) * 100).toFixed(1) + '%');
      panel.style.setProperty('--my', (((e.clientY - r.top) / r.height) * 100).toFixed(1) + '%');
    }, { passive: true });
  });
})();
```

---

## 5. Interactive Undersea Glass Stingray JS (`undersea-ray.js`)

Save the script below as `undersea-ray.js` and load it with `<script src="/undersea-ray.js" defer></script>` on any page that has `<canvas id="bg-canvas"></canvas>`.

### Behavior Summary
- **Idle Pointer**: After ~420ms of pointer stillness inside the window, the stingray grows curious, swims smoothly toward the pointer, and orbits tenderly nearby (`~58px` radius).
- **Pushed Pointer**: Pressing/clicking (`pointerdown`), dragging while held, or briskly sweeping the cursor (`> 520px/s`) toward the ray emits an expanding translucent water ripple and triggers an immediate propulsion burst (faster wingbeat, radial push-away velocity, and wake bubbles).
- **Theme-Aware**: Reads `document.documentElement.getAttribute('data-theme')` every frame to switch between opal-cerulean glass (Light) and bioluminescent ice-cyan glass (Dark).
- **Accessible & Battery-Friendly**: Pauses when `document.hidden` is true, caps DPR at `2`, and renders a single poised static frame under `prefers-reduced-motion: reduce`.

### Quick Customization Knobs
- **Panel Transparency**: Adjust `--glass-surface` alpha (`0.25`–`0.42`) and `.glass-panel` `backdrop-filter: blur(10px–16px)` to control how clearly the stingray shines through content.
- **Creature Size & Speed**: Edit `scale`, `wingSpan`, and `speed` in the `rays` array inside `undersea-ray.js`.
- **Idle Hover Distance**: Change `hoverRadius` (`58` for primary ray, `145` for background ray).
- **Push-Away Power**: Adjust `triggerPushAway` intensity (`1.35` on click) or `260 * power` impulse velocity.

```js
/* Transparent Undersea Glass Stingray — Procedural Canvas 2D Ambient Effect
 * Requires: <canvas id="bg-canvas" aria-hidden="true"></canvas>
 */
(function () {
  const canvas = document.getElementById('bg-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const prefersReducedMotion =
    window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let width = window.innerWidth;
  let height = window.innerHeight;
  let dpr = Math.min(window.devicePixelRatio || 1, 2);

  function resize() {
    width = window.innerWidth;
    height = window.innerHeight;
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  window.addEventListener('resize', resize, { passive: true });
  resize();

  const pointer = {
    x: width * 0.5, y: height * 0.5, prevX: width * 0.5, prevY: height * 0.5,
    vx: 0, vy: 0, speed: 0, inside: false, isDown: false,
    lastMoveTime: 0, lastEventTime: 0
  };
  const ripples = [];
  const wakeParticles = [];

  const orbs = [
    { xRatio: 0.20, yRatio: 0.22, r: 380, dark: '56, 189, 248', light: '59, 130, 246', alphaDark: 0.13, alphaLight: 0.11, sx: 0.16, sy: 0.13, p: 0 },
    { xRatio: 0.80, yRatio: 0.30, r: 420, dark: '99, 102, 241', light: '99, 102, 241', alphaDark: 0.12, alphaLight: 0.09, sx: -0.14, sy: 0.15, p: 2.1 },
    { xRatio: 0.50, yRatio: 0.82, r: 340, dark: '16, 185, 129', light: '20, 184, 166', alphaDark: 0.08, alphaLight: 0.08, sx: 0.11, sy: -0.12, p: 4.2 }
  ];

  const motes = Array.from({ length: 28 }, () => ({
    x: Math.random() * width,
    y: Math.random() * height,
    r: 1.1 + Math.random() * 2.2,
    vx: (Math.random() - 0.5) * 8,
    vy: -4 - Math.random() * 10,
    phase: Math.random() * Math.PI * 2,
    alpha: 0.20 + Math.random() * 0.32
  }));

  function lerp(a, b, t) { return a + (b - a) * t; }
  function wrapAngle(a) {
    while (a > Math.PI) a -= Math.PI * 2;
    while (a < -Math.PI) a += Math.PI * 2;
    return a;
  }

  function spawnRipple(x, y, strength) {
    if (ripples.length > 10) ripples.shift();
    ripples.push({ x, y, r: 8, maxR: 95 + strength * 75, life: 0, maxLife: 0.85 + strength * 0.35 });
  }

  function createStingray(opts) {
    const segCount = opts.segCount || 30;
    const segLen = opts.segLen || 10.5;
    const startX = width * opts.startXRatio;
    const startY = height * opts.startYRatio;
    const spine = Array.from({ length: segCount }, (_, i) => ({
      x: startX - Math.cos(opts.startAngle) * i * segLen,
      y: startY - Math.sin(opts.startAngle) * i * segLen,
      angle: opts.startAngle
    }));
    return {
      spine, segCount, segLen, scale: opts.scale, baseSpeed: opts.speed, turnRate: opts.turnRate,
      wingSpan: opts.wingSpan, baseWingFreq: opts.wingFreq, wingPhase: opts.wingPhase || 0,
      opacity: opts.opacity, depth: opts.depth, angle: opts.startAngle,
      targetX: width * opts.targetXRatio, targetY: height * opts.targetYRatio,
      waypointTimer: 0, orbitSeed: opts.orbitSeed || 0, spawnWake: opts.spawnWake !== false,
      wakeAccum: 0, fleeTimer: 0, fleeStrength: 0, pushVx: 0, pushVy: 0
    };
  }

  const rays = [
    createStingray({
      segCount: 32, segLen: 10.5, scale: 1.04, speed: 58, turnRate: 1.45,
      wingSpan: 136, wingFreq: 2.2, wingPhase: 0.2, opacity: 1.0, depth: 1.0,
      startXRatio: 0.18, startYRatio: 0.72, startAngle: -0.45,
      targetXRatio: 0.78, targetYRatio: 0.28, orbitSeed: 1.3, spawnWake: true
    }),
    createStingray({
      segCount: 26, segLen: 7.4, scale: 0.66, speed: 42, turnRate: 1.15,
      wingSpan: 88, wingFreq: 2.6, wingPhase: 2.8, opacity: 0.62, depth: 0.55,
      startXRatio: 0.84, startYRatio: 0.24, startAngle: 2.45,
      targetXRatio: 0.24, targetYRatio: 0.76, orbitSeed: 4.7, spawnWake: false
    })
  ];

  function spawnBurstWake(ray, count) {
    const wingSeg = ray.spine[4];
    const perpX = -Math.sin(wingSeg.angle), perpY = Math.cos(wingSeg.angle);
    for (let i = 0; i < count && wakeParticles.length < 60; i++) {
      const side = i % 2 === 0 ? 1 : -1;
      const radial = (0.35 + Math.random() * 0.65) * ray.wingSpan;
      wakeParticles.push({
        x: wingSeg.x + perpX * side * radial,
        y: wingSeg.y + perpY * side * radial,
        vx: -Math.cos(wingSeg.angle) * (24 + Math.random() * 34) + (Math.random() - 0.5) * 26,
        vy: -Math.sin(wingSeg.angle) * (24 + Math.random() * 34) + (Math.random() - 0.5) * 26,
        r: 1.4 + Math.random() * 2.4, life: 0, maxLife: 1.4 + Math.random() * 1.4
      });
    }
  }

  function triggerPushAway(px, py, intensity, maxRadius) {
    let anyPushed = false;
    for (const ray of rays) {
      const center = ray.spine[3];
      const dx = center.x - px, dy = center.y - py;
      const dist = Math.hypot(dx, dy);
      const effectiveRadius = maxRadius * (0.75 + 0.35 * ray.depth);
      if (dist < effectiveRadius) {
        anyPushed = true;
        const nx = dist > 0.001 ? dx / dist : Math.cos(ray.angle);
        const ny = dist > 0.001 ? dy / dist : Math.sin(ray.angle);
        const closeness = 1 - Math.min(1, dist / effectiveRadius);
        const power = intensity * (0.55 + 0.85 * closeness) * (0.65 + 0.35 * ray.depth);
        ray.pushVx += nx * (260 * power);
        ray.pushVy += ny * (260 * power);
        ray.fleeTimer = Math.max(ray.fleeTimer, 1.35 + 0.85 * closeness);
        ray.fleeStrength = Math.min(1.8, Math.max(ray.fleeStrength, power));
        const escapeDist = Math.min(width, height) * (0.45 + 0.25 * closeness);
        const escapeAngle = Math.atan2(ny, nx) + (Math.random() - 0.5) * 0.45;
        ray.targetX = Math.max(80, Math.min(width - 80, center.x + Math.cos(escapeAngle) * escapeDist));
        ray.targetY = Math.max(80, Math.min(height - 80, center.y + Math.sin(escapeAngle) * escapeDist));
        ray.waypointTimer = 4.5 + Math.random() * 3.0;
        spawnBurstWake(ray, Math.round(7 * power));
      }
    }
    if (anyPushed) spawnRipple(px, py, Math.min(1.2, intensity));
  }

  let lastThrustTime = 0;
  window.addEventListener('pointermove', (e) => {
    const now = performance.now();
    const dtMs = Math.max(8, now - pointer.lastEventTime);
    const dx = e.clientX - pointer.x, dy = e.clientY - pointer.y;
    const dist = Math.hypot(dx, dy);
    pointer.prevX = pointer.x; pointer.prevY = pointer.y;
    pointer.x = e.clientX; pointer.y = e.clientY;
    pointer.inside = true; pointer.lastEventTime = now;
    if (dist > 1.5) {
      pointer.lastMoveTime = now;
      pointer.speed = lerp(pointer.speed, (dist / dtMs) * 1000, 0.45);
    }
    if (pointer.isDown && now - lastThrustTime > 120) {
      lastThrustTime = now;
      triggerPushAway(pointer.x, pointer.y, 1.05, 420);
    } else if (pointer.speed > 520 && now - lastThrustTime > 180) {
      for (const ray of rays) {
        const c = ray.spine[3];
        if (Math.hypot(c.x - pointer.x, c.y - pointer.y) < 210 * ray.scale + 70) {
          lastThrustTime = now;
          triggerPushAway(pointer.x, pointer.y, Math.min(1.35, 0.65 + (pointer.speed - 520) / 1400), 340);
          break;
        }
      }
    }
  }, { passive: true });

  window.addEventListener('pointerdown', (e) => {
    pointer.x = e.clientX; pointer.y = e.clientY;
    pointer.inside = true; pointer.isDown = true;
    pointer.lastMoveTime = pointer.lastEventTime = lastThrustTime = performance.now();
    spawnRipple(pointer.x, pointer.y, 0.95);
    triggerPushAway(pointer.x, pointer.y, 1.35, Math.max(460, Math.min(width, height) * 0.62));
  }, { passive: true });

  window.addEventListener('pointerup', () => { pointer.isDown = false; }, { passive: true });
  window.addEventListener('pointercancel', () => { pointer.isDown = false; }, { passive: true });
  window.addEventListener('pointerleave', () => { pointer.inside = false; pointer.isDown = false; }, { passive: true });

  function pickNextWaypoint(ray) {
    const mx = Math.min(120, width * 0.12), my = Math.min(110, height * 0.12);
    const head = ray.spine[0];
    let tx = mx + Math.random() * Math.max(80, width - mx * 2);
    let ty = my + Math.random() * Math.max(80, height - my * 2);
    if (Math.hypot(tx - head.x, ty - head.y) < Math.min(width, height) * 0.35) {
      tx = head.x < width * 0.5 ? width * (0.66 + Math.random() * 0.24) : width * (0.10 + Math.random() * 0.24);
      ty = head.y < height * 0.5 ? height * (0.64 + Math.random() * 0.24) : height * (0.12 + Math.random() * 0.24);
    }
    ray.targetX = tx; ray.targetY = ty; ray.waypointTimer = 5.5 + Math.random() * 5.0;
  }

  function wingWidthProfile(u) {
    if (u <= 0) return 0;
    if (u < 0.36) return Math.pow(Math.sin((u / 0.36) * Math.PI * 0.5), 0.78);
    const mainTaper = Math.pow(Math.cos(((u - 0.36) / 0.64) * Math.PI * 0.5), 1.35);
    const pelvicBump = Math.exp(-Math.pow((u - 0.86) / 0.085, 2)) * 0.14;
    return Math.max(0.03, mainTaper + pelvicBump);
  }

  function updateRay(ray, dt, t, nowMs) {
    const head = ray.spine[0];
    ray.waypointTimer -= dt;
    if (ray.fleeTimer > 0) {
      ray.fleeTimer = Math.max(0, ray.fleeTimer - dt);
      ray.fleeStrength = lerp(ray.fleeStrength, 0, Math.min(1, dt * 1.4));
    } else {
      ray.fleeStrength = lerp(ray.fleeStrength, 0, Math.min(1, dt * 2.5));
    }
    const pushDecay = Math.exp(-dt * 3.1);
    ray.pushVx *= pushDecay; ray.pushVy *= pushDecay;

    const isPointerIdle = pointer.inside && !pointer.isDown && (nowMs - pointer.lastMoveTime) > 420;
    let goalX = ray.targetX, goalY = ray.targetY;
    let approachingIdlePointer = false, distToPointer = Infinity;

    if (ray.fleeTimer > 0) {
      const outDx = head.x - pointer.x, outDy = head.y - pointer.y;
      const outDist = Math.hypot(outDx, outDy) || 1;
      const fleePull = Math.min(1, ray.fleeTimer / 0.8);
      goalX = lerp(ray.targetX, head.x + (outDx / outDist) * 320, fleePull * 0.72);
      goalY = lerp(ray.targetY, head.y + (outDy / outDist) * 320, fleePull * 0.72);
    } else if (isPointerIdle) {
      approachingIdlePointer = true;
      distToPointer = Math.hypot(pointer.x - head.x, pointer.y - head.y);
      const hoverRadius = ray.depth > 0.8 ? 58 : 145;
      const orbitDir = ray.depth > 0.8 ? 1 : -1;
      const orbitAngle = t * (ray.depth > 0.8 ? 0.62 : 0.42) * orbitDir + ray.orbitSeed;
      if (distToPointer > hoverRadius + 45) {
        const approachAngle = Math.atan2(pointer.y - head.y, pointer.x - head.x);
        const tangentOffset = Math.min(34, distToPointer * 0.14) * orbitDir;
        goalX = pointer.x - Math.sin(approachAngle) * tangentOffset;
        goalY = pointer.y + Math.cos(approachAngle) * tangentOffset;
      } else {
        goalX = pointer.x + Math.cos(orbitAngle) * hoverRadius;
        goalY = pointer.y + Math.sin(orbitAngle) * hoverRadius;
      }
    }

    const dx = goalX - head.x, dy = goalY - head.y;
    if (!approachingIdlePointer && ray.fleeTimer <= 0 && (Math.hypot(dx, dy) < 105 || ray.waypointTimer <= 0)) {
      pickNextWaypoint(ray);
    }

    const sway = Math.sin(t * 0.65 + ray.orbitSeed) * (approachingIdlePointer ? 0.08 : (ray.fleeTimer > 0 ? 0.04 : 0.22));
    const diff = wrapAngle(Math.atan2(dy, dx) + sway - ray.angle);
    const activeTurnRate = ray.fleeTimer > 0 ? ray.turnRate * 2.55 : (approachingIdlePointer ? ray.turnRate * 1.65 : ray.turnRate);
    const maxTurn = activeTurnRate * dt;
    const turnGain = ray.fleeTimer > 0 ? 4.2 : (approachingIdlePointer ? 3.1 : 2.2);
    ray.angle = wrapAngle(ray.angle + Math.max(-maxTurn, Math.min(maxTurn, diff * turnGain * dt)));

    const wingFreqMult = ray.fleeTimer > 0 ? 1 + 1.15 * Math.min(1.4, ray.fleeStrength) : (approachingIdlePointer && distToPointer < 120 ? 0.85 : 1.08);
    ray.wingPhase += dt * ray.baseWingFreq * wingFreqMult;
    const glideBoost = 0.84 + 0.30 * Math.pow(0.5 + 0.5 * Math.sin(ray.wingPhase - 0.6), 1.6);
    const speedMult = ray.fleeTimer > 0 ? 1 + 1.85 * Math.min(1.5, ray.fleeStrength) : (approachingIdlePointer ? (distToPointer > 130 ? 1.28 : 0.72) : 1.0);
    const step = ray.baseSpeed * speedMult * glideBoost * dt;

    head.x += Math.cos(ray.angle) * step + ray.pushVx * dt;
    head.y += Math.sin(ray.angle) * step + ray.pushVy * dt;
    head.angle = ray.angle;

    const pad = 210;
    if (head.x < -pad) head.x = width + pad * 0.55;
    if (head.x > width + pad) head.x = -pad * 0.55;
    if (head.y < -pad) head.y = height + pad * 0.55;
    if (head.y > height + pad) head.y = -pad * 0.55;

    for (let i = 1; i < ray.segCount; i++) {
      const prev = ray.spine[i - 1], curr = ray.spine[i];
      let segAngle = Math.atan2(prev.y - curr.y, prev.x - curr.x);
      if (i > 12) {
        const tailProgress = (i - 12) / (ray.segCount - 12);
        segAngle += Math.sin(ray.wingPhase * 1.15 - i * 0.34) * (ray.fleeTimer > 0 ? 0.095 : 0.055) * tailProgress;
      }
      curr.angle = segAngle;
      curr.x = prev.x - Math.cos(segAngle) * ray.segLen;
      curr.y = prev.y - Math.sin(segAngle) * ray.segLen;
    }

    if (ray.spawnWake) {
      ray.wakeAccum += dt;
      if (ray.wakeAccum > (ray.fleeTimer > 0 ? 0.09 : 0.22) && wakeParticles.length < 48) {
        ray.wakeAccum = 0;
        const ws = ray.spine[4], side = Math.random() < 0.5 ? 1 : -1;
        const tipDist = ray.wingSpan * (0.76 + 0.14 * Math.sin(ray.wingPhase - 1.1));
        wakeParticles.push({
          x: ws.x - Math.sin(ws.angle) * side * tipDist,
          y: ws.y + Math.cos(ws.angle) * side * tipDist,
          vx: -Math.cos(ws.angle) * (ray.fleeTimer > 0 ? 22 : 8) + (Math.random() - 0.5) * 8,
          vy: -Math.sin(ws.angle) * (ray.fleeTimer > 0 ? 22 : 8) + (Math.random() - 0.5) * 8,
          r: 1.2 + Math.random() * 2.0, life: 0, maxLife: 2.0 + Math.random() * 1.6
        });
      }
    }
  }

  function drawStingray(ray, isLight, t) {
    const spine = ray.spine, bodySegs = 13, a = ray.opacity;
    const p = isLight ? {
      shadow: `rgba(25, 62, 138, ${0.095 * a})`, bodyCore: `rgba(14, 110, 210, ${0.30 * a})`,
      bodyMid: `rgba(38, 178, 245, ${0.22 * a})`, bodyEdge: `rgba(99, 102, 241, ${0.09 * a})`,
      rimOuter: `rgba(255, 255, 255, ${0.78 * a})`, rimInner: `rgba(29, 78, 216, ${0.38 * a})`,
      rib: `rgba(255, 255, 255, ${0.42 * a})`, ribTint: `rgba(37, 99, 235, ${0.20 * a})`,
      spineGlow: `rgba(255, 255, 255, ${0.68 * a})`, spot: `rgba(255, 255, 255, ${0.56 * a})`,
      spotRing: `rgba(14, 165, 233, ${0.32 * a})`, tail: `rgba(29, 78, 216, ${0.34 * a})`,
      tailHighlight: `rgba(255, 255, 255, ${0.60 * a})`, eye: `rgba(15, 35, 78, ${0.52 * a})`
    } : {
      shadow: `rgba(0, 6, 18, ${0.28 * a})`, bodyCore: `rgba(56, 189, 248, ${0.32 * a})`,
      bodyMid: `rgba(99, 102, 241, ${0.22 * a})`, bodyEdge: `rgba(45, 212, 191, ${0.08 * a})`,
      rimOuter: `rgba(186, 230, 253, ${0.58 * a})`, rimInner: `rgba(56, 189, 248, ${0.38 * a})`,
      rib: `rgba(186, 230, 253, ${0.24 * a})`, ribTint: `rgba(56, 189, 248, ${0.18 * a})`,
      spineGlow: `rgba(224, 242, 254, ${0.54 * a})`, spot: `rgba(186, 230, 253, ${0.46 * a})`,
      spotRing: `rgba(45, 212, 191, ${0.34 * a})`, tail: `rgba(125, 211, 252, ${0.40 * a})`,
      tailHighlight: `rgba(224, 242, 254, ${0.50 * a})`, eye: `rgba(224, 242, 254, ${0.65 * a})`
    };

    const head = spine[0];
    const hfx = Math.cos(head.angle), hfy = Math.sin(head.angle), hpx = -hfy, hpy = hfx;
    const snoutX = head.x + hfx * (13 * ray.scale), snoutY = head.y + hfy * (13 * ray.scale);
    const leftPts = [{ x: head.x + hfx * (18 * ray.scale) + hpx * (14 * ray.scale), y: head.y + hfy * (18 * ray.scale) + hpy * (14 * ray.scale) }];
    const rightPts = [{ x: head.x + hfx * (18 * ray.scale) - hpx * (14 * ray.scale), y: head.y + hfy * (18 * ray.scale) - hpy * (14 * ray.scale) }];
    const flexAmp = ray.fleeTimer > 0 ? 0.22 : 0.16;

    for (let i = 0; i <= bodySegs; i++) {
      const seg = spine[i], u = i / bodySegs, bp = wingWidthProfile(u);
      const wp = ray.wingPhase - u * 2.85, wf = Math.sin(wp);
      const span = ray.wingSpan * bp * (0.86 + flexAmp * wf + Math.cos(wp * 2 - 0.5) * 0.04);
      const sweep = (-8 + 18 * wf) * bp * ray.scale;
      const fx = Math.cos(seg.angle), fy = Math.sin(seg.angle), px = -fy, py = fx;
      leftPts.push({ x: seg.x - fx * sweep + px * span, y: seg.y - fy * sweep + py * span });
      rightPts.push({ x: seg.x - fx * sweep - px * span, y: seg.y - fy * sweep - py * span });
    }

    function trace(ox, oy) {
      ctx.beginPath();
      ctx.moveTo(snoutX + ox, snoutY + oy);
      for (let i = 0; i < leftPts.length - 1; i++) {
        const c = leftPts[i], n = leftPts[i + 1];
        ctx.quadraticCurveTo(c.x + ox, c.y + oy, (c.x + n.x) * 0.5 + ox, (c.y + n.y) * 0.5 + oy);
      }
      const ll = leftPts[leftPts.length - 1], lr = rightPts[rightPts.length - 1], tb = spine[bodySegs];
      ctx.lineTo(ll.x + ox, ll.y + oy);
      ctx.lineTo(tb.x + ox, tb.y + oy);
      ctx.lineTo(lr.x + ox, lr.y + oy);
      for (let i = rightPts.length - 1; i > 0; i--) {
        const c = rightPts[i], pr = rightPts[i - 1];
        ctx.quadraticCurveTo(c.x + ox, c.y + oy, (c.x + pr.x) * 0.5 + ox, (c.y + pr.y) * 0.5 + oy);
      }
      ctx.quadraticCurveTo(rightPts[0].x + ox, rightPts[0].y + oy, snoutX + ox, snoutY + oy);
      ctx.closePath();
    }

    // Shadow
    ctx.save(); ctx.filter = 'blur(12px)'; trace(14 * ray.scale, 22 * ray.scale); ctx.fillStyle = p.shadow; ctx.fill(); ctx.restore();

    // Whip tail
    ctx.save(); ctx.lineCap = 'round';
    for (let i = bodySegs - 1; i < ray.segCount - 1; i++) {
      const p0 = spine[i], p1 = spine[i + 1];
      const frac = 1 - (i - (bodySegs - 1)) / (ray.segCount - bodySegs);
      const tw = Math.max(0.65, 5.2 * ray.scale * Math.pow(frac, 1.8));
      ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(p1.x, p1.y); ctx.lineWidth = tw; ctx.strokeStyle = p.tail; ctx.stroke();
      if (frac > 0.25) { ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(p1.x, p1.y); ctx.lineWidth = Math.max(0.4, tw * 0.32); ctx.strokeStyle = p.tailHighlight; ctx.stroke(); }
    }
    ctx.restore();

    // Translucent body + inner anatomy
    const cs = spine[4];
    const bg = ctx.createRadialGradient(cs.x, cs.y, 4 * ray.scale, cs.x, cs.y, ray.wingSpan * 1.08);
    bg.addColorStop(0, p.bodyCore); bg.addColorStop(0.52, p.bodyMid); bg.addColorStop(1, p.bodyEdge);
    ctx.save(); trace(0, 0); ctx.fillStyle = bg; ctx.fill(); ctx.clip();

    ctx.lineWidth = 0.9 * ray.scale;
    for (let i = 2; i <= bodySegs - 2; i++) {
      const s = spine[i];
      for (const tip of [leftPts[i + 1], rightPts[i + 1]]) {
        const rg = ctx.createLinearGradient(s.x, s.y, tip.x, tip.y);
        rg.addColorStop(0, p.rib); rg.addColorStop(0.65, p.ribTint); rg.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.beginPath(); ctx.moveTo(s.x, s.y);
        ctx.quadraticCurveTo(lerp(s.x, tip.x, 0.5) - Math.cos(s.angle) * 6 * ray.scale, lerp(s.y, tip.y, 0.5) - Math.sin(s.angle) * 6 * ray.scale, tip.x, tip.y);
        ctx.strokeStyle = rg; ctx.stroke();
      }
    }

    const spots = [{ seg: 3, frac: 0.28, r: 4.2 }, { seg: 4, frac: 0.42, r: 3.6 }, { seg: 5, frac: 0.24, r: 4.6 }, { seg: 6, frac: 0.52, r: 3.0 }, { seg: 7, frac: 0.34, r: 3.4 }, { seg: 8, frac: 0.22, r: 2.7 }];
    spots.forEach((sp, idx) => {
      const seg = spine[sp.seg], sh = 0.72 + 0.28 * Math.sin(t * 1.4 + idx * 1.1 + ray.orbitSeed);
      for (const tip of [leftPts[sp.seg + 1], rightPts[sp.seg + 1]]) {
        ctx.save(); ctx.globalAlpha = sh; ctx.beginPath();
        ctx.arc(lerp(seg.x, tip.x, sp.frac), lerp(seg.y, tip.y, sp.frac), sp.r * ray.scale, 0, Math.PI * 2);
        ctx.fillStyle = p.spot; ctx.fill(); ctx.lineWidth = 0.9; ctx.strokeStyle = p.spotRing; ctx.stroke(); ctx.restore();
      }
    });

    ctx.beginPath(); ctx.moveTo(snoutX, snoutY);
    for (let i = 0; i <= bodySegs; i++) ctx.lineTo(spine[i].x, spine[i].y);
    ctx.lineWidth = 3.2 * ray.scale; ctx.lineCap = 'round'; ctx.strokeStyle = p.spineGlow; ctx.stroke();
    ctx.restore();

    // Specular glass edge rim + eyes
    ctx.save(); trace(0, 0);
    ctx.lineWidth = 1.75 * ray.scale; ctx.strokeStyle = p.rimOuter; ctx.stroke();
    ctx.lineWidth = 0.9 * ray.scale; ctx.strokeStyle = p.rimInner; ctx.stroke();
    const es = spine[1], efx = Math.cos(es.angle), efy = Math.sin(es.angle), epx = -efy, epy = efx;
    for (const side of [-1, 1]) {
      ctx.beginPath();
      ctx.ellipse(es.x + efx * (5 * ray.scale) + epx * side * (12.5 * ray.scale), es.y + efy * (5 * ray.scale) + epy * side * (12.5 * ray.scale), 2.3 * ray.scale, 1.4 * ray.scale, es.angle, 0, Math.PI * 2);
      ctx.fillStyle = p.eye; ctx.fill();
    }
    ctx.restore();
  }

  function drawScene(nowMs, dt) {
    const t = nowMs * 0.001;
    const isLight = document.documentElement.getAttribute('data-theme') === 'light';
    ctx.clearRect(0, 0, width, height);
    if (nowMs - pointer.lastMoveTime > 90) pointer.speed *= Math.exp(-dt * 8);

    for (const o of orbs) {
      const ox = width * o.xRatio + Math.sin(t * o.sx + o.p) * Math.min(140, width * 0.11);
      const oy = height * o.yRatio + Math.cos(t * o.sy + o.p) * Math.min(110, height * 0.10);
      const g = ctx.createRadialGradient(ox, oy, 0, ox, oy, o.r);
      g.addColorStop(0, `rgba(${isLight ? o.light : o.dark}, ${isLight ? o.alphaLight : o.alphaDark})`);
      g.addColorStop(1, `rgba(${isLight ? o.light : o.dark}, 0)`);
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(ox, oy, o.r, 0, Math.PI * 2); ctx.fill();
    }

    for (const m of motes) {
      if (dt > 0) {
        m.x += (m.vx + Math.sin(t * 0.5 + m.phase) * 5) * dt; m.y += m.vy * dt;
        if (m.y < -12) { m.y = height + 12; m.x = Math.random() * width; }
        if (m.x < -12) m.x = width + 12; if (m.x > width + 12) m.x = -12;
      }
      const sh = 0.6 + 0.4 * Math.sin(t * 1.3 + m.phase);
      ctx.beginPath(); ctx.arc(m.x, m.y, m.r, 0, Math.PI * 2);
      ctx.fillStyle = isLight ? `rgba(56, 139, 235, ${m.alpha * 0.40 * sh})` : `rgba(186, 230, 253, ${m.alpha * 0.38 * sh})`;
      ctx.fill();
    }

    for (let i = ripples.length - 1; i >= 0; i--) {
      const rp = ripples[i]; if (dt > 0) rp.life += dt;
      if (rp.life >= rp.maxLife) { ripples.splice(i, 1); continue; }
      const p = rp.life / rp.maxLife, rad = lerp(rp.r, rp.maxR, 1 - Math.pow(1 - p, 2.5)), fade = (1 - p) * (1 - p);
      ctx.beginPath(); ctx.arc(rp.x, rp.y, rad, 0, Math.PI * 2); ctx.lineWidth = 1.6 * (1 - p * 0.6);
      ctx.strokeStyle = isLight ? `rgba(37, 99, 235, ${0.26 * fade})` : `rgba(125, 211, 252, ${0.32 * fade})`; ctx.stroke();
      ctx.beginPath(); ctx.arc(rp.x, rp.y, rad * 0.68, 0, Math.PI * 2); ctx.lineWidth = 1.0;
      ctx.strokeStyle = isLight ? `rgba(255, 255, 255, ${0.52 * fade})` : `rgba(224, 242, 254, ${0.24 * fade})`; ctx.stroke();
    }

    for (let i = wakeParticles.length - 1; i >= 0; i--) {
      const wp = wakeParticles[i]; if (dt > 0) { wp.life += dt; wp.x += wp.vx * dt; wp.y += wp.vy * dt; wp.vx *= 0.985; wp.vy *= 0.985; }
      if (wp.life >= wp.maxLife) { wakeParticles.splice(i, 1); continue; }
      const fade = Math.sin((wp.life / wp.maxLife) * Math.PI);
      ctx.beginPath(); ctx.arc(wp.x, wp.y, wp.r * (0.7 + 0.5 * (wp.life / wp.maxLife)), 0, Math.PI * 2);
      ctx.strokeStyle = isLight ? `rgba(255, 255, 255, ${0.62 * fade})` : `rgba(186, 230, 253, ${0.42 * fade})`;
      ctx.lineWidth = 0.95; ctx.stroke();
    }

    for (let i = rays.length - 1; i >= 0; i--) {
      if (dt > 0) updateRay(rays[i], dt, t, nowMs);
      drawStingray(rays[i], isLight, t);
    }
  }

  if (prefersReducedMotion) {
    drawScene(0, 0);
    window.addEventListener('resize', () => drawScene(0, 0), { passive: true });
    new MutationObserver(() => drawScene(0, 0)).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    return;
  }

  let lastTime = performance.now();
  function loop(now) {
    const dt = Math.min(0.05, Math.max(0.001, (now - lastTime) * 0.001));
    lastTime = now;
    if (!document.hidden) drawScene(now, dt);
    window.requestAnimationFrame(loop);
  }
  window.requestAnimationFrame(loop);
})();
```
