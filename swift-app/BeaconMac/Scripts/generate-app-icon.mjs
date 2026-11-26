#!/usr/bin/env node
/**
 * Generates the BeaconMac macOS AppIcon set (.appiconset PNGs) and SwiftPM
 * fallback PNG based on the BeaconMac website brand mark:
 *   - Apple macOS continuous squircle geometry (824x824 inside 1024x1024 grid)
 *   - Liquid Glass cobalt-to-royal-blue gradient, top specular sheen & rim
 *   - Exact BeaconMac website glyph: central emitter dot + symmetric inner & outer arcs
 *
 * Uses pure Node.js analytical SDF rendering at 2048x2048 and ImageMagick Lanczos
 * downsampling for razor-sharp Retina and 16x16 icons.
 */

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const SWIFT_DIR = path.resolve(__dirname, '..');
const RESOURCES_DIR = path.join(SWIFT_DIR, 'Sources', 'Beacon', 'Resources');
const ICONSET_DIR = path.join(RESOURCES_DIR, 'Assets.xcassets', 'AppIcon.appiconset');

// Minimal zero-dependency RGBA PNG encoder
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) {
      c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
    }
  }
  return (c ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBuf = Buffer.from(type, 'ascii');
  const lenBuf = Buffer.alloc(4);
  lenBuf.writeUInt32BE(data.length, 0);
  const crcInput = Buffer.concat([typeBuf, data]);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(crcInput), 0);
  return Buffer.concat([lenBuf, typeBuf, data, crcBuf]);
}

function encodePNG(width, height, rgba) {
  const raw = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y++) {
    const rowStart = y * (width * 4 + 1);
    raw[rowStart] = 0; // filter type 0 (None)
    rgba.copy(raw, rowStart + 1, y * width * 4, (y + 1) * width * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const idat = zlib.deflateSync(raw, { level: 6 });
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  return Buffer.concat([
    sig,
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', idat),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

// Utility math helpers
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
const lerp = (a, b, t) => a + (b - a) * t;
const smoothstep = (e0, e1, x) => {
  const t = clamp((x - e0) / (e1 - e0), 0, 1);
  return t * t * (3 - 2 * t);
};

// Approximate Euclidean signed distance to a superellipse |x/a|^p + |y/a|^p = 1
// Using gradient normalization for accurate pixel-level antialiasing & bevel distance.
function sdSquircle(px, py, halfSize, p = 5.3) {
  const ax = Math.abs(px);
  const ay = Math.abs(py);
  const nx = ax / halfSize;
  const ny = ay / halfSize;
  const xp = Math.pow(nx, p);
  const yp = Math.pow(ny, p);
  const f = xp + yp;
  if (f < 1e-12) return -halfSize;
  const norm = Math.pow(f, 1 / p);
  // First-order Newton distance estimate: (norm - 1) * halfSize / |grad(norm)|
  const gx = Math.pow(nx, p - 1);
  const gy = Math.pow(ny, p - 1);
  const gradMag = Math.pow(f, (1 - p) / p) * Math.hypot(gx, gy);
  return ((norm - 1) * halfSize) / Math.max(gradMag, 1e-6);
}

// Exact signed distance to a circular arc centered at (0, 0) with radius R,
// centered on angle `centerAngle`, spanning `+-halfAperture` radians, stroke radius `halfThick`.
function sdArc(px, py, radius, centerAngle, halfAperture, halfThick) {
  // Rotate point so centerAngle aligns with +X axis
  const ca = Math.cos(-centerAngle);
  const sa = Math.sin(-centerAngle);
  const rx = px * ca - py * sa;
  const ry = Math.abs(px * sa + py * ca); // symmetric across X axis

  const sinA = Math.sin(halfAperture);
  const cosA = Math.cos(halfAperture);

  let d;
  // Check whether point lies within angular sector [-halfAperture, +halfAperture]
  if (rx * sinA > ry * cosA) {
    d = Math.abs(Math.hypot(rx, ry) - radius);
  } else {
    // Distance to arc cap center
    const ex = radius * cosA;
    const ey = radius * sinA;
    d = Math.hypot(rx - ex, ry - ey);
  }
  return d - halfThick;
}

// Signed distance to the full BeaconMac website glyph in centered 1024-grid coordinates
function sdBeaconGlyph(gx, gy, svgScale, strokeBoost = 1.0) {
  // Website SVG (viewBox 0 0 24 24, center 12,12):
  //   circle r=2.2 (slightly tuned to 2.38 for optical balance)
  //   inner arcs: r=6.0, span [-45deg, +45deg] and [135deg, 225deg]
  //   outer arcs: r=10.0, span [-45deg, +45deg] and [135deg, 225deg]
  //   stroke-width=2.25 -> halfThick = 1.125
  const dotR = 2.38 * svgScale * (0.94 + 0.06 * strokeBoost);
  const halfThick = 1.14 * svgScale * strokeBoost;
  const rInner = 6.0 * svgScale;
  const rOuter = 10.0 * svgScale;
  const halfAper = Math.PI / 4; // 45 deg (exact match to SVG 16.24,7.76 & 19.07,4.93)

  let d = Math.hypot(gx, gy) - dotR;
  d = Math.min(d, sdArc(gx, gy, rInner, 0, halfAper, halfThick));
  d = Math.min(d, sdArc(gx, gy, rInner, Math.PI, halfAper, halfThick));
  d = Math.min(d, sdArc(gx, gy, rOuter, 0, halfAper, halfThick));
  d = Math.min(d, sdArc(gx, gy, rOuter, Math.PI, halfAper, halfThick));
  return d;
}

// Premultiplied alpha compositing: src over dst (all linear/sRGB 0..1)
function blendOver(dr, dg, db, da, sr, sg, sb, sa) {
  const outA = sa + da * (1 - sa);
  if (outA <= 1e-6) return [0, 0, 0, 0];
  const outR = (sr * sa + dr * da * (1 - sa)) / outA;
  const outG = (sg * sa + dg * da * (1 - sa)) / outA;
  const outB = (sb * sa + db * da * (1 - sa)) / outA;
  return [outR, outG, outB, outA];
}

function renderMasterIcon(size = 2048, strokeBoost = 1.0) {
  const buf = Buffer.alloc(size * size * 4);
  const scale = size / 1024;
  const halfGrid = 512;
  const squircleHalf = 412; // 824x824 squircle inside 1024x1024 (Apple macOS HIG grid)
  const svgScale = 26.2; // 24 SVG units -> 628.8px across 824px squircle
  const aa = 0.85 / scale; // smooth analytical AA width in 1024-grid units

  for (let py = 0; py < size; py++) {
    const gy = (py + 0.5) / scale - halfGrid; // -512 .. +512
    for (let px = 0; px < size; px++) {
      const gx = (px + 0.5) / scale - halfGrid;

      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;

      // 1. Soft macOS elevation + contact drop shadow outside/underneath squircle
      const dShadowFar = sdSquircle(gx, gy - 18, squircleHalf - 4, 5.3);
      if (dShadowFar < 78) {
        const sFar = Math.exp(-Math.pow(Math.max(dShadowFar, 0) / 28, 1.85)) * 0.25;
        const dShadowNear = sdSquircle(gx, gy - 6, squircleHalf - 1, 5.3);
        const sNear = Math.exp(-Math.pow(Math.max(dShadowNear, 0) / 10, 1.8)) * 0.19;
        const shadowA = clamp(sFar + sNear, 0, 0.42);
        [r, g, b, a] = blendOver(r, g, b, a, 8 / 255, 20 / 255, 52 / 255, shadowA);
      }

      // 2. Squircle body
      const dSq = sdSquircle(gx, gy, squircleHalf, 5.3);
      const sqCov = 1 - smoothstep(-aa, aa, dSq);

      if (sqCov > 0.0005) {
        // Normalized coords inside squircle (-1 .. +1)
        const u = gx / squircleHalf;
        const v = gy / squircleHalf; // -1 top, +1 bottom
        const tY = clamp((v + 1) * 0.5, 0, 1);

        // Multi-stop vertical blue gradient matching website --accent-btn-bg (#3b82f6 -> #1d4ed8)
        let br, bg, bb;
        if (tY < 0.42) {
          const k = tY / 0.42;
          br = lerp(74, 53, k);
          bg = lerp(156, 126, k);
          bb = lerp(255, 246, k);
        } else {
          const k = (tY - 0.42) / 0.58;
          br = lerp(53, 21, k);
          bg = lerp(126, 56, k);
          bb = lerp(246, 174, k);
        }

        // Upper-left cyan-sky Liquid Glass luminescence
        const distTopLeft = Math.hypot((u + 0.42) * 0.85, (v + 0.62) * 0.95);
        const glowTL = Math.pow(clamp(1 - distTopLeft / 1.48, 0, 1), 2.1) * 0.34;
        br = lerp(br, 138, glowTL);
        bg = lerp(bg, 222, glowTL);
        bb = lerp(bb, 255, glowTL);

        // Lower-right deep oceanic sapphire depth
        const distBotRight = Math.hypot((u - 0.48) * 0.88, (v - 0.65) * 0.92);
        const shadeBR = Math.pow(clamp(1 - distBotRight / 1.35, 0, 1), 1.9) * 0.28;
        br = lerp(br, 11, shadeBR);
        bg = lerp(bg, 26, shadeBR);
        bb = lerp(bb, 88, shadeBR);

        // Subtle central radial aurora behind the beacon emitter
        const distCenter = Math.hypot(u, v);
        const centerAura = Math.pow(clamp(1 - distCenter / 0.92, 0, 1), 2.4) * 0.22;
        br = lerp(br, 125, centerAura);
        bg = lerp(bg, 211, centerAura);
        bb = lerp(bb, 252, centerAura);

        // Subtle curved Liquid Glass top dome reflection sheen
        const domeCurve = -0.14 + 0.26 * u * u;
        const domeMask = smoothstep(domeCurve + 0.08, domeCurve - 0.05, v);
        const topFade = smoothstep(0.05, -0.98, v);
        const domeAlpha = domeMask * (0.04 + 0.16 * topFade);
        br = lerp(br, 255, domeAlpha);
        bg = lerp(bg, 255, domeAlpha);
        bb = lerp(bb, 255, domeAlpha);

        // Ultra-subtle concentric sonar depth rings behind the glyph
        const distPx = Math.hypot(gx, gy);
        const ring1 = 1 - smoothstep(0, 2.8, Math.abs(distPx - 6.0 * svgScale));
        const ring2 = 1 - smoothstep(0, 2.8, Math.abs(distPx - 10.0 * svgScale));
        const ringAlpha = Math.max(ring1, ring2) * 0.075;
        br = lerp(br, 235, ringAlpha);
        bg = lerp(bg, 246, ringAlpha);
        bb = lerp(bb, 255, ringAlpha);

        // Liquid Glass inner specular bevel rim along squircle border
        const inward = -dSq; // positive inside squircle
        if (inward < 22) {
          // Bright sharp inner specular highlight (strongest at top, softer sides, faint bottom)
          const rimBand =
            smoothstep(0.0, 2.2, inward) * (1 - smoothstep(3.2, 11.0, inward));
          const topWeight = clamp((-v + 0.35) / 1.35, 0, 1);
          const botWeight = clamp((v - 0.45) / 0.55, 0, 1);
          const rimOpacity = 0.14 + 0.56 * Math.pow(topWeight, 1.5) + 0.10 * botWeight;
          br = lerp(br, 255, rimBand * rimOpacity);
          bg = lerp(bg, 255, rimBand * rimOpacity);
          bb = lerp(bb, 255, rimBand * rimOpacity);

          // Subtle crisp outer edge definition (1.6px) for high contrast on white backgrounds
          const outerEdge = 1 - smoothstep(0.0, 2.4, inward);
          br = lerp(br, 14, outerEdge * 0.22);
          bg = lerp(bg, 36, outerEdge * 0.22);
          bb = lerp(bb, 108, outerEdge * 0.22);
        }

        // 3. BeaconMac Glyph (shadow + soft bloom + crisp pearlescent white glyph)
        // Soft drop shadow beneath glyph
        const dGlyphSh = sdBeaconGlyph(gx, gy - 11, svgScale, strokeBoost);
        if (dGlyphSh < 44) {
          const gSh = Math.exp(-Math.pow(Math.max(dGlyphSh, 0) / 15, 1.75)) * 0.30;
          br = lerp(br, 8, gSh);
          bg = lerp(bg, 22, gSh);
          bb = lerp(bb, 68, gSh);
        }

        // Soft luminous cyan-white glow around emitter & arcs
        const dGlyph = sdBeaconGlyph(gx, gy, svgScale, strokeBoost);
        if (dGlyph < 64) {
          const gGlow = Math.exp(-Math.pow(Math.max(dGlyph, 0) / 24, 1.65)) * 0.24;
          br = lerp(br, 195, gGlow);
          bg = lerp(bg, 236, gGlow);
          bb = lerp(bb, 255, gGlow);
        }

        // Crisp pure white glyph fill with subtle top-to-bottom glass sheen
        const glyphCov = 1 - smoothstep(-aa, aa, dGlyph);
        if (glyphCov > 0.0005) {
          const glyphGrad = clamp((gy / 280 + 1) * 0.5, 0, 1);
          const gr = lerp(255, 236, glyphGrad);
          const gg = lerp(255, 245, glyphGrad);
          const gb = 255;
          br = lerp(br, gr, glyphCov);
          bg = lerp(bg, gg, glyphCov);
          bb = lerp(bb, gb, glyphCov);
        }

        [r, g, b, a] = blendOver(r, g, b, a, br / 255, bg / 255, bb / 255, sqCov);
      }

      const idx = (py * size + px) * 4;
      buf[idx] = clamp(Math.round(r * 255), 0, 255);
      buf[idx + 1] = clamp(Math.round(g * 255), 0, 255);
      buf[idx + 2] = clamp(Math.round(b * 255), 0, 255);
      buf[idx + 3] = clamp(Math.round(a * 255), 0, 255);
    }
  }
  return buf;
}

fs.mkdirSync(ICONSET_DIR, { recursive: true });

const tmpMaster = path.join('/tmp', 'beaconmac-icon-master-2048.png');
const tmpSmallMaster = path.join('/tmp', 'beaconmac-icon-small-512.png');

console.log('Rendering 2048x2048 master BeaconMac AppIcon...');
const masterRGBA = renderMasterIcon(2048, 1.0);
fs.writeFileSync(tmpMaster, encodePNG(2048, 2048, masterRGBA));

// Slightly bolder optical stroke for tiny 16x16 / 32x32 Finder/Spotlight icons
console.log('Rendering 512x512 optical-small master for 16px/32px sizes...');
const smallRGBA = renderMasterIcon(512, 1.16);
fs.writeFileSync(tmpSmallMaster, encodePNG(512, 512, smallRGBA));

const targets = [
  { name: 'icon_16x16.png', px: 16, src: tmpSmallMaster },
  { name: 'icon_16x16@2x.png', px: 32, src: tmpSmallMaster },
  { name: 'icon_32x32.png', px: 32, src: tmpSmallMaster },
  { name: 'icon_32x32@2x.png', px: 64, src: tmpMaster },
  { name: 'icon_128x128.png', px: 128, src: tmpMaster },
  { name: 'icon_128x128@2x.png', px: 256, src: tmpMaster },
  { name: 'icon_256x256.png', px: 256, src: tmpMaster },
  { name: 'icon_256x256@2x.png', px: 512, src: tmpMaster },
  { name: 'icon_512x512.png', px: 512, src: tmpMaster },
  { name: 'icon_512x512@2x.png', px: 1024, src: tmpMaster },
];

for (const t of targets) {
  const outPath = path.join(ICONSET_DIR, t.name);
  execFileSync('convert', [
    t.src,
    '-filter',
    'Lanczos',
    '-resize',
    `${t.px}x${t.px}`,
    'PNG32:' + outPath,
  ]);
  console.log(`  Generated ${t.name} (${t.px}x${t.px})`);
}

// Also copy 512x512 PNG for SwiftPM `swift run` Dock icon fallback
const spmIconPath = path.join(RESOURCES_DIR, 'BeaconAppIcon.png');
fs.copyFileSync(path.join(ICONSET_DIR, 'icon_512x512.png'), spmIconPath);
console.log(`  Generated BeaconAppIcon.png (512x512 SwiftPM fallback)`);

fs.rmSync(tmpMaster, { force: true });
fs.rmSync(tmpSmallMaster, { force: true });
console.log('Done!');
