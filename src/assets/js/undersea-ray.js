/* Transparent Undersea Glass Stingray — Procedural Canvas 2D Ambient Effect
 * Interactive pelagic behavior:
 * - Idle pointer: stingray senses stillness, grows curious, and glides smoothly close to the pointer.
 * - Pushed pointer (pointer press/click or brisk cursor push toward the ray):
 *   stingray surges away with an energetic wingbeat propulsion burst, translucent water ripple,
 *   and wake bubbles before settling back into serene gliding.
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

  // Pointer tracking for idle-approach and push-away physics
  const pointer = {
    x: width * 0.5,
    y: height * 0.5,
    prevX: width * 0.5,
    prevY: height * 0.5,
    vx: 0,
    vy: 0,
    speed: 0,
    inside: false,
    isDown: false,
    lastMoveTime: 0,
    lastEventTime: 0
  };

  // Subtle translucent water ripples emitted when the pointer pushes the creature
  const ripples = [];

  function spawnRipple(x, y, strength) {
    if (ripples.length > 10) ripples.shift();
    ripples.push({
      x,
      y,
      r: 8,
      maxR: 95 + strength * 75,
      life: 0,
      maxLife: 0.85 + strength * 0.35
    });
  }

  // Ambient Liquid Glass aurora pools behind the stingrays
  const orbs = [
    { xRatio: 0.20, yRatio: 0.22, r: 380, dark: '56, 189, 248', light: '59, 130, 246', alphaDark: 0.13, alphaLight: 0.11, sx: 0.16, sy: 0.13, p: 0 },
    { xRatio: 0.80, yRatio: 0.30, r: 420, dark: '99, 102, 241', light: '99, 102, 241', alphaDark: 0.12, alphaLight: 0.09, sx: -0.14, sy: 0.15, p: 2.1 },
    { xRatio: 0.50, yRatio: 0.82, r: 340, dark: '16, 185, 129', light: '20, 184, 166', alphaDark: 0.08, alphaLight: 0.08, sx: 0.11, sy: -0.12, p: 4.2 }
  ];

  // Very slow blackhole gravitational-infall space field (polar spiral particles + spacetime rings)
  const SPACE_PARTICLE_COUNT = 96;
  const spaceParticles = [];
  function maxViewportRadius() {
    return Math.hypot(width * 0.5, height * 0.5) * 1.15;
  }
  function createSpaceParticle(spawnAtEdge) {
    const maxR = maxViewportRadius();
    const minR = Math.min(width, height) * 0.055;
    const normR = spawnAtEdge
      ? 0.88 + Math.random() * 0.24
      : Math.pow(Math.random(), 0.62); // fuller spread from outer rim to near horizon
    return {
      r: minR + normR * (maxR - minR),
      angle: Math.random() * Math.PI * 2,
      infallSpeed: 7 + Math.random() * 11,      // very slow inward drift (px/s base)
      angularSpeed: 0.035 + Math.random() * 0.045, // subtle slow orbital frame-dragging
      size: 0.75 + Math.random() * 1.55,
      alpha: 0.18 + Math.random() * 0.42,
      tintIdx: Math.floor(Math.random() * 3),
      phase: Math.random() * Math.PI * 2
    };
  }
  for (let i = 0; i < SPACE_PARTICLE_COUNT; i++) {
    spaceParticles.push(createSpaceParticle(false));
  }

  const LENS_RING_COUNT = 8;
  const lensRings = Array.from({ length: LENS_RING_COUNT }, (_, i) => ({
    phase: i / LENS_RING_COUNT,
    tilt: 0.76 + (i % 3) * 0.05,
    rotOffset: i * 0.78
  }));

  // Subtle drifting translucent marine plankton / bubble motes
  const motes = [];
  const MOTE_COUNT = 28;
  for (let i = 0; i < MOTE_COUNT; i++) {
    motes.push({
      x: Math.random() * width,
      y: Math.random() * height,
      r: 1.1 + Math.random() * 2.2,
      vx: (Math.random() - 0.5) * 8,
      vy: -4 - Math.random() * 10,
      phase: Math.random() * Math.PI * 2,
      alpha: 0.20 + Math.random() * 0.32
    });
  }

  // Wake particles spawned gently off the wingtips
  const wakeParticles = [];

  function lerp(a, b, t) {
    return a + (b - a) * t;
  }

  function wrapAngle(a) {
    while (a > Math.PI) a -= Math.PI * 2;
    while (a < -Math.PI) a += Math.PI * 2;
    return a;
  }

  function createStingray(opts) {
    const segCount = opts.segCount || 30;
    const segLen = opts.segLen || 11.5;
    const startX = width * opts.startXRatio;
    const startY = height * opts.startYRatio;
    const angle = opts.startAngle;

    const spine = [];
    for (let i = 0; i < segCount; i++) {
      spine.push({
        x: startX - Math.cos(angle) * i * segLen,
        y: startY - Math.sin(angle) * i * segLen,
        angle: angle
      });
    }

    return {
      spine,
      segCount,
      segLen,
      scale: opts.scale,
      baseSpeed: opts.speed,
      turnRate: opts.turnRate,
      wingSpan: opts.wingSpan,
      baseWingFreq: opts.wingFreq,
      wingPhase: opts.wingPhase || 0,
      opacity: opts.opacity,
      depth: opts.depth,
      angle,
      targetX: width * opts.targetXRatio,
      targetY: height * opts.targetYRatio,
      waypointTimer: 0,
      orbitSeed: opts.orbitSeed || 0,
      spawnWake: opts.spawnWake !== false,
      wakeAccum: 0,
      // Push-away propulsion state
      fleeTimer: 0,
      fleeStrength: 0,
      pushVx: 0,
      pushVy: 0
    };
  }

  const rays = [
    // Primary rare translucent Glass Stingray
    createStingray({
      segCount: 32,
      segLen: 10.5,
      scale: 1.04,
      speed: 58,
      turnRate: 1.45,
      wingSpan: 136,
      wingFreq: 2.2,
      wingPhase: 0.2,
      opacity: 1.0,
      depth: 1.0,
      startXRatio: 0.18,
      startYRatio: 0.72,
      startAngle: -0.45,
      targetXRatio: 0.78,
      targetYRatio: 0.28,
      orbitSeed: 1.3,
      spawnWake: true
    }),
    // Secondary deeper distant translucent juvenile ray for serene parallax depth
    createStingray({
      segCount: 26,
      segLen: 7.4,
      scale: 0.66,
      speed: 42,
      turnRate: 1.15,
      wingSpan: 88,
      wingFreq: 2.6,
      wingPhase: 2.8,
      opacity: 0.62,
      depth: 0.55,
      startXRatio: 0.84,
      startYRatio: 0.24,
      startAngle: 2.45,
      targetXRatio: 0.24,
      targetYRatio: 0.76,
      orbitSeed: 4.7,
      spawnWake: false
    })
  ];

  function spawnBurstWake(ray, count) {
    const wingSeg = ray.spine[4];
    const perpX = -Math.sin(wingSeg.angle);
    const perpY = Math.cos(wingSeg.angle);
    for (let i = 0; i < count; i++) {
      if (wakeParticles.length >= 60) break;
      const side = i % 2 === 0 ? 1 : -1;
      const radial = (0.35 + Math.random() * 0.65) * ray.wingSpan;
      wakeParticles.push({
        x: wingSeg.x + perpX * side * radial,
        y: wingSeg.y + perpY * side * radial,
        vx: -Math.cos(wingSeg.angle) * (24 + Math.random() * 34) + (Math.random() - 0.5) * 26,
        vy: -Math.sin(wingSeg.angle) * (24 + Math.random() * 34) + (Math.random() - 0.5) * 26,
        r: 1.4 + Math.random() * 2.4,
        life: 0,
        maxLife: 1.4 + Math.random() * 1.4
      });
    }
  }

  function triggerPushAway(px, py, intensity, maxRadius) {
    let anyPushed = false;
    for (const ray of rays) {
      const center = ray.spine[3];
      const dx = center.x - px;
      const dy = center.y - py;
      const dist = Math.hypot(dx, dy);
      const effectiveRadius = maxRadius * (0.75 + 0.35 * ray.depth);

      if (dist < effectiveRadius) {
        anyPushed = true;
        const nx = dist > 0.001 ? dx / dist : Math.cos(ray.angle);
        const ny = dist > 0.001 ? dy / dist : Math.sin(ray.angle);
        const closeness = 1 - Math.min(1, dist / effectiveRadius);
        const power = intensity * (0.55 + 0.85 * closeness) * (0.65 + 0.35 * ray.depth);

        // Immediately impart outward propulsion impulse & turn heading outward
        ray.pushVx += nx * (260 * power);
        ray.pushVy += ny * (260 * power);
        ray.fleeTimer = Math.max(ray.fleeTimer, 1.35 + 0.85 * closeness);
        ray.fleeStrength = Math.min(1.8, Math.max(ray.fleeStrength, power));

        // Pick a fresh distant destination in the pushed direction so it glides cleanly away
        const escapeDist = Math.min(width, height) * (0.45 + 0.25 * closeness);
        const spread = (Math.random() - 0.5) * 0.45;
        const escapeAngle = Math.atan2(ny, nx) + spread;
        ray.targetX = Math.max(80, Math.min(width - 80, center.x + Math.cos(escapeAngle) * escapeDist));
        ray.targetY = Math.max(80, Math.min(height - 80, center.y + Math.sin(escapeAngle) * escapeDist));
        ray.waypointTimer = 4.5 + Math.random() * 3.0;

        spawnBurstWake(ray, Math.round(7 * power));
      }
    }

    if (anyPushed) {
      spawnRipple(px, py, Math.min(1.2, intensity));
    }
  }

  let lastThrustTime = 0;

  window.addEventListener(
    'pointermove',
    (e) => {
      const now = performance.now();
      const dtMs = Math.max(8, now - pointer.lastEventTime);
      const dx = e.clientX - pointer.x;
      const dy = e.clientY - pointer.y;
      const dist = Math.hypot(dx, dy);

      pointer.prevX = pointer.x;
      pointer.prevY = pointer.y;
      pointer.x = e.clientX;
      pointer.y = e.clientY;
      pointer.inside = true;
      pointer.lastEventTime = now;

      if (dist > 1.5) {
        pointer.lastMoveTime = now;
        const instSpeed = (dist / dtMs) * 1000; // px / sec
        pointer.vx = (dx / dtMs) * 1000;
        pointer.vy = (dy / dtMs) * 1000;
        pointer.speed = lerp(pointer.speed, instSpeed, 0.45);
      }

      // If pointer is pushed/held down while dragging OR swept quickly near the creature, push it away
      if (pointer.isDown) {
        if (now - lastThrustTime > 120) {
          lastThrustTime = now;
          triggerPushAway(pointer.x, pointer.y, 1.05, 420);
        }
      } else if (pointer.speed > 520 && now - lastThrustTime > 180) {
        // Check if cursor is pushing close to a ray
        for (const ray of rays) {
          const c = ray.spine[3];
          const d = Math.hypot(c.x - pointer.x, c.y - pointer.y);
          if (d < 210 * ray.scale + 70) {
            lastThrustTime = now;
            const thrustPower = Math.min(1.35, 0.65 + (pointer.speed - 520) / 1400);
            triggerPushAway(pointer.x, pointer.y, thrustPower, 340);
            break;
          }
        }
      }
    },
    { passive: true }
  );

  window.addEventListener(
    'pointerdown',
    (e) => {
      pointer.x = e.clientX;
      pointer.y = e.clientY;
      pointer.inside = true;
      pointer.isDown = true;
      pointer.lastMoveTime = performance.now();
      pointer.lastEventTime = pointer.lastMoveTime;
      lastThrustTime = pointer.lastMoveTime;

      // Pushing/pressing the pointer pushes the creature away strongly with a visible water ripple
      spawnRipple(pointer.x, pointer.y, 0.95);
      triggerPushAway(pointer.x, pointer.y, 1.35, Math.max(460, Math.min(width, height) * 0.62));
    },
    { passive: true }
  );

  window.addEventListener(
    'pointerup',
    () => {
      pointer.isDown = false;
    },
    { passive: true }
  );

  window.addEventListener(
    'pointercancel',
    () => {
      pointer.isDown = false;
    },
    { passive: true }
  );

  window.addEventListener(
    'pointerleave',
    () => {
      pointer.inside = false;
      pointer.isDown = false;
    },
    { passive: true }
  );

  function pickNextWaypoint(ray) {
    const marginX = Math.min(120, width * 0.12);
    const marginY = Math.min(110, height * 0.12);
    const head = ray.spine[0];

    let tx = marginX + Math.random() * Math.max(80, width - marginX * 2);
    let ty = marginY + Math.random() * Math.max(80, height - marginY * 2);

    const dx = tx - head.x;
    const dy = ty - head.y;
    if (Math.hypot(dx, dy) < Math.min(width, height) * 0.35) {
      tx = head.x < width * 0.5 ? width * (0.66 + Math.random() * 0.24) : width * (0.10 + Math.random() * 0.24);
      ty = head.y < height * 0.5 ? height * (0.64 + Math.random() * 0.24) : height * (0.12 + Math.random() * 0.24);
    }

    ray.targetX = tx;
    ray.targetY = ty;
    ray.waypointTimer = 5.5 + Math.random() * 5.0;
  }

  function updateRay(ray, dt, t, nowMs) {
    const head = ray.spine[0];
    ray.waypointTimer -= dt;

    // Decay push-away impulse and flee timer smoothly
    if (ray.fleeTimer > 0) {
      ray.fleeTimer = Math.max(0, ray.fleeTimer - dt);
      ray.fleeStrength = lerp(ray.fleeStrength, 0, Math.min(1, dt * 1.4));
    } else {
      ray.fleeStrength = lerp(ray.fleeStrength, 0, Math.min(1, dt * 2.5));
    }
    const pushDecay = Math.exp(-dt * 3.1);
    ray.pushVx *= pushDecay;
    ray.pushVy *= pushDecay;

    const idleDuration = nowMs - pointer.lastMoveTime;
    const isPointerIdle = pointer.inside && !pointer.isDown && idleDuration > 420;

    let goalX = ray.targetX;
    let goalY = ray.targetY;
    let approachingIdlePointer = false;
    let distToPointer = Infinity;

    if (ray.fleeTimer > 0) {
      // Actively fleeing outward from the pushed pointer
      const outDx = head.x - pointer.x;
      const outDy = head.y - pointer.y;
      const outDist = Math.hypot(outDx, outDy) || 1;
      const fleePull = Math.min(1, ray.fleeTimer / 0.8);
      goalX = lerp(ray.targetX, head.x + (outDx / outDist) * 320, fleePull * 0.72);
      goalY = lerp(ray.targetY, head.y + (outDy / outDist) * 320, fleePull * 0.72);
    } else if (isPointerIdle) {
      // Curious approach: when pointer is idle, glide gently close to it and circle softly around it
      approachingIdlePointer = true;
      distToPointer = Math.hypot(pointer.x - head.x, pointer.y - head.y);

      // Primary ray comes very close (~58px orbit); secondary ray lingers slightly further (~145px)
      const hoverRadius = ray.depth > 0.8 ? 58 : 145;
      const orbitDir = ray.depth > 0.8 ? 1 : -1;
      const orbitSpeed = ray.depth > 0.8 ? 0.62 : 0.42;
      const orbitAngle = t * orbitSpeed * orbitDir + ray.orbitSeed;

      if (distToPointer > hoverRadius + 45) {
        // Swim directly toward the idle pointer with subtle graceful curve
        const approachAngle = Math.atan2(pointer.y - head.y, pointer.x - head.x);
        const tangentOffset = Math.min(34, distToPointer * 0.14) * orbitDir;
        goalX = pointer.x - Math.sin(approachAngle) * tangentOffset;
        goalY = pointer.y + Math.cos(approachAngle) * tangentOffset;
      } else {
        // Circle tenderly right near the idle pointer
        goalX = pointer.x + Math.cos(orbitAngle) * hoverRadius;
        goalY = pointer.y + Math.sin(orbitAngle) * hoverRadius;
      }
    }

    const dx = goalX - head.x;
    const dy = goalY - head.y;
    const dist = Math.hypot(dx, dy);

    if (!approachingIdlePointer && ray.fleeTimer <= 0 && (dist < 105 || ray.waypointTimer <= 0)) {
      pickNextWaypoint(ray);
    }

    const desiredAngle = Math.atan2(dy, dx);
    const swayAmt = approachingIdlePointer ? 0.08 : (ray.fleeTimer > 0 ? 0.04 : 0.22);
    const sway = Math.sin(t * 0.65 + ray.orbitSeed) * swayAmt;
    const diff = wrapAngle(desiredAngle + sway - ray.angle);

    // Faster turning during push-away escape or close curious orbiting
    const activeTurnRate = ray.fleeTimer > 0
      ? ray.turnRate * 2.55
      : (approachingIdlePointer ? ray.turnRate * 1.65 : ray.turnRate);

    const maxTurn = activeTurnRate * dt;
    const turnGain = ray.fleeTimer > 0 ? 4.2 : (approachingIdlePointer ? 3.1 : 2.2);
    ray.angle = wrapAngle(ray.angle + Math.max(-maxTurn, Math.min(maxTurn, diff * turnGain * dt)));

    // Wingbeat speeds up noticeably when pushing itself away, slows gracefully when hovering near idle pointer
    const wingFreqMult = ray.fleeTimer > 0
      ? 1 + 1.15 * Math.min(1.4, ray.fleeStrength)
      : (approachingIdlePointer && distToPointer < 120 ? 0.85 : 1.08);
    ray.wingPhase += dt * ray.baseWingFreq * wingFreqMult;

    const glideBoost = 0.84 + 0.30 * Math.pow(0.5 + 0.5 * Math.sin(ray.wingPhase - 0.6), 1.6);

    let speedMult = 1.0;
    if (ray.fleeTimer > 0) {
      speedMult = 1.0 + 1.85 * Math.min(1.5, ray.fleeStrength);
    } else if (approachingIdlePointer) {
      if (distToPointer > 130) {
        speedMult = 1.28; // eager graceful approach
      } else {
        speedMult = 0.72; // calm close hover/circle around idle pointer
      }
    }

    const step = ray.baseSpeed * speedMult * glideBoost * dt;

    head.x += Math.cos(ray.angle) * step + ray.pushVx * dt;
    head.y += Math.sin(ray.angle) * step + ray.pushVy * dt;
    head.angle = ray.angle;

    // Keep smoothly inside extended viewport bounds
    const pad = 210;
    if (head.x < -pad) head.x = width + pad * 0.55;
    if (head.x > width + pad) head.x = -pad * 0.55;
    if (head.y < -pad) head.y = height + pad * 0.55;
    if (head.y > height + pad) head.y = -pad * 0.55;

    // Articulated spine follow-the-leader constraints
    for (let i = 1; i < ray.segCount; i++) {
      const prev = ray.spine[i - 1];
      const curr = ray.spine[i];
      const sdx = prev.x - curr.x;
      const sdy = prev.y - curr.y;
      let segAngle = Math.atan2(sdy, sdx);

      if (i > 12) {
        const tailProgress = (i - 12) / (ray.segCount - 12);
        const tailAmp = ray.fleeTimer > 0 ? 0.095 : 0.055;
        segAngle += Math.sin(ray.wingPhase * 1.15 - i * 0.34) * tailAmp * tailProgress;
      }

      curr.angle = segAngle;
      curr.x = prev.x - Math.cos(segAngle) * ray.segLen;
      curr.y = prev.y - Math.sin(segAngle) * ray.segLen;
    }

    // Spawn faint iridescent wake motes off wingtips
    if (ray.spawnWake) {
      ray.wakeAccum += dt;
      const interval = ray.fleeTimer > 0 ? 0.09 : 0.22;
      if (ray.wakeAccum > interval && wakeParticles.length < 48) {
        ray.wakeAccum = 0;
        const wingSeg = ray.spine[4];
        const perpX = -Math.sin(wingSeg.angle);
        const perpY = Math.cos(wingSeg.angle);
        const side = Math.random() < 0.5 ? 1 : -1;
        const wave = Math.sin(ray.wingPhase - 1.1);
        const tipDist = ray.wingSpan * (0.76 + 0.14 * wave);
        wakeParticles.push({
          x: wingSeg.x + perpX * side * tipDist,
          y: wingSeg.y + perpY * side * tipDist,
          vx: -Math.cos(wingSeg.angle) * (ray.fleeTimer > 0 ? 22 : 8) + (Math.random() - 0.5) * 8,
          vy: -Math.sin(wingSeg.angle) * (ray.fleeTimer > 0 ? 22 : 8) + (Math.random() - 0.5) * 8,
          r: 1.2 + Math.random() * 2.0,
          life: 0,
          maxLife: 2.0 + Math.random() * 1.6
        });
      }
    }
  }

  // Anatomical diamond pectoral fin width profile along body disc (u in [0, 1])
  function wingWidthProfile(u) {
    if (u <= 0) return 0;
    if (u < 0.36) {
      const k = u / 0.36;
      return Math.pow(Math.sin(k * Math.PI * 0.5), 0.78);
    }
    const k = (u - 0.36) / 0.64;
    const mainTaper = Math.pow(Math.cos(k * Math.PI * 0.5), 1.35);
    const pelvicBump = Math.exp(-Math.pow((u - 0.86) / 0.085, 2)) * 0.14;
    return Math.max(0.03, mainTaper + pelvicBump);
  }

  function drawStingray(ray, isLight, t) {
    const spine = ray.spine;
    const bodySegs = 13;
    const alphaScale = ray.opacity;

    // Slightly enriched translucent optical tones so the glass stingray reads clearly
    // both in open water and through the slightly transparent main content panel
    const palette = isLight
      ? {
          shadow: `rgba(25, 62, 138, ${0.095 * alphaScale})`,
          bodyCore: `rgba(14, 110, 210, ${0.30 * alphaScale})`,
          bodyMid: `rgba(38, 178, 245, ${0.22 * alphaScale})`,
          bodyEdge: `rgba(99, 102, 241, ${0.09 * alphaScale})`,
          rimOuter: `rgba(255, 255, 255, ${0.78 * alphaScale})`,
          rimInner: `rgba(29, 78, 216, ${0.38 * alphaScale})`,
          rib: `rgba(255, 255, 255, ${0.42 * alphaScale})`,
          ribTint: `rgba(37, 99, 235, ${0.20 * alphaScale})`,
          spineGlow: `rgba(255, 255, 255, ${0.68 * alphaScale})`,
          spot: `rgba(255, 255, 255, ${0.56 * alphaScale})`,
          spotRing: `rgba(14, 165, 233, ${0.32 * alphaScale})`,
          tail: `rgba(29, 78, 216, ${0.34 * alphaScale})`,
          tailHighlight: `rgba(255, 255, 255, ${0.60 * alphaScale})`,
          eye: `rgba(15, 35, 78, ${0.52 * alphaScale})`
        }
      : {
          shadow: `rgba(0, 6, 18, ${0.28 * alphaScale})`,
          bodyCore: `rgba(56, 189, 248, ${0.32 * alphaScale})`,
          bodyMid: `rgba(99, 102, 241, ${0.22 * alphaScale})`,
          bodyEdge: `rgba(45, 212, 191, ${0.08 * alphaScale})`,
          rimOuter: `rgba(186, 230, 253, ${0.58 * alphaScale})`,
          rimInner: `rgba(56, 189, 248, ${0.38 * alphaScale})`,
          rib: `rgba(186, 230, 253, ${0.24 * alphaScale})`,
          ribTint: `rgba(56, 189, 248, ${0.18 * alphaScale})`,
          spineGlow: `rgba(224, 242, 254, ${0.54 * alphaScale})`,
          spot: `rgba(186, 230, 253, ${0.46 * alphaScale})`,
          spotRing: `rgba(45, 212, 191, ${0.34 * alphaScale})`,
          tail: `rgba(125, 211, 252, ${0.40 * alphaScale})`,
          tailHighlight: `rgba(224, 242, 254, ${0.50 * alphaScale})`,
          eye: `rgba(224, 242, 254, ${0.65 * alphaScale})`
        };

    const leftPts = [];
    const rightPts = [];
    const head = spine[0];
    const headFwdX = Math.cos(head.angle);
    const headFwdY = Math.sin(head.angle);
    const headPerpX = -headFwdY;
    const headPerpY = headFwdX;

    const snoutX = head.x + headFwdX * (13 * ray.scale);
    const snoutY = head.y + headFwdY * (13 * ray.scale);
    const lobeSpread = 14 * ray.scale;
    const lobeReach = 18 * ray.scale;

    leftPts.push({
      x: head.x + headFwdX * lobeReach + headPerpX * lobeSpread,
      y: head.y + headFwdY * lobeReach + headPerpY * lobeSpread
    });
    rightPts.push({
      x: head.x + headFwdX * lobeReach - headPerpX * lobeSpread,
      y: head.y + headFwdY * lobeReach - headPerpY * lobeSpread
    });

    const flexAmp = ray.fleeTimer > 0 ? 0.22 : 0.16;

    for (let i = 0; i <= bodySegs; i++) {
      const seg = spine[i];
      const u = i / bodySegs;
      const baseProfile = wingWidthProfile(u);

      const wavePhase = ray.wingPhase - u * 2.85;
      const wingFlex = Math.sin(wavePhase);
      const secondaryRipple = Math.cos(wavePhase * 2 - 0.5) * 0.04;

      const dynamicSpan = ray.wingSpan * baseProfile * (0.86 + flexAmp * wingFlex + secondaryRipple);
      const sweepBack = (-8 + 18 * wingFlex) * baseProfile * ray.scale;

      const fwdX = Math.cos(seg.angle);
      const fwdY = Math.sin(seg.angle);
      const perpX = -fwdY;
      const perpY = fwdX;

      leftPts.push({
        x: seg.x - fwdX * sweepBack + perpX * dynamicSpan,
        y: seg.y - fwdY * sweepBack + perpY * dynamicSpan
      });
      rightPts.push({
        x: seg.x - fwdX * sweepBack - perpX * dynamicSpan,
        y: seg.y - fwdY * sweepBack - perpY * dynamicSpan
      });
    }

    function traceBodyPath(offsetX, offsetY) {
      ctx.beginPath();
      ctx.moveTo(snoutX + offsetX, snoutY + offsetY);

      for (let i = 0; i < leftPts.length - 1; i++) {
        const curr = leftPts[i];
        const next = leftPts[i + 1];
        const mx = (curr.x + next.x) * 0.5 + offsetX;
        const my = (curr.y + next.y) * 0.5 + offsetY;
        ctx.quadraticCurveTo(curr.x + offsetX, curr.y + offsetY, mx, my);
      }
      const lastL = leftPts[leftPts.length - 1];
      ctx.lineTo(lastL.x + offsetX, lastL.y + offsetY);

      const tailBase = spine[bodySegs];
      ctx.lineTo(tailBase.x + offsetX, tailBase.y + offsetY);

      const lastR = rightPts[rightPts.length - 1];
      ctx.lineTo(lastR.x + offsetX, lastR.y + offsetY);
      for (let i = rightPts.length - 1; i > 0; i--) {
        const curr = rightPts[i];
        const prev = rightPts[i - 1];
        const mx = (curr.x + prev.x) * 0.5 + offsetX;
        const my = (curr.y + prev.y) * 0.5 + offsetY;
        ctx.quadraticCurveTo(curr.x + offsetX, curr.y + offsetY, mx, my);
      }
      ctx.quadraticCurveTo(rightPts[0].x + offsetX, rightPts[0].y + offsetY, snoutX + offsetX, snoutY + offsetY);
      ctx.closePath();
    }

    // 1. Soft underwater caustic depth shadow offset below the ray
    ctx.save();
    ctx.filter = 'blur(12px)';
    traceBodyPath(14 * ray.scale, 22 * ray.scale);
    ctx.fillStyle = palette.shadow;
    ctx.fill();
    ctx.restore();

    // 2. Whip-like tapered stingray tail
    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    for (let i = bodySegs - 1; i < ray.segCount - 1; i++) {
      const p0 = spine[i];
      const p1 = spine[i + 1];
      const frac = 1 - (i - (bodySegs - 1)) / (ray.segCount - bodySegs);
      const tailW = Math.max(0.65, 5.2 * ray.scale * Math.pow(frac, 1.8));

      ctx.beginPath();
      ctx.moveTo(p0.x, p0.y);
      ctx.lineTo(p1.x, p1.y);
      ctx.lineWidth = tailW;
      ctx.strokeStyle = palette.tail;
      ctx.stroke();

      if (frac > 0.25) {
        ctx.beginPath();
        ctx.moveTo(p0.x, p0.y);
        ctx.lineTo(p1.x, p1.y);
        ctx.lineWidth = Math.max(0.4, tailW * 0.32);
        ctx.strokeStyle = palette.tailHighlight;
        ctx.stroke();
      }
    }
    ctx.restore();

    // 3. Translucent Glass Stingray Body Disc
    const centerSeg = spine[4];
    const bodyGrad = ctx.createRadialGradient(
      centerSeg.x,
      centerSeg.y,
      4 * ray.scale,
      centerSeg.x,
      centerSeg.y,
      ray.wingSpan * 1.08
    );
    bodyGrad.addColorStop(0, palette.bodyCore);
    bodyGrad.addColorStop(0.52, palette.bodyMid);
    bodyGrad.addColorStop(1, palette.bodyEdge);

    ctx.save();
    traceBodyPath(0, 0);
    ctx.fillStyle = bodyGrad;
    ctx.fill();

    ctx.clip();

    // 4. Delicate cartilaginous fin rays fanning outward from the spine
    ctx.lineWidth = 0.9 * ray.scale;
    for (let i = 2; i <= bodySegs - 2; i++) {
      const s = spine[i];
      const lTip = leftPts[i + 1];
      const rTip = rightPts[i + 1];

      const ribGradL = ctx.createLinearGradient(s.x, s.y, lTip.x, lTip.y);
      ribGradL.addColorStop(0, palette.rib);
      ribGradL.addColorStop(0.65, palette.ribTint);
      ribGradL.addColorStop(1, 'rgba(255,255,255,0)');

      ctx.beginPath();
      ctx.moveTo(s.x, s.y);
      ctx.quadraticCurveTo(
        lerp(s.x, lTip.x, 0.5) - Math.cos(s.angle) * 6 * ray.scale,
        lerp(s.y, lTip.y, 0.5) - Math.sin(s.angle) * 6 * ray.scale,
        lTip.x,
        lTip.y
      );
      ctx.strokeStyle = ribGradL;
      ctx.stroke();

      const ribGradR = ctx.createLinearGradient(s.x, s.y, rTip.x, rTip.y);
      ribGradR.addColorStop(0, palette.rib);
      ribGradR.addColorStop(0.65, palette.ribTint);
      ribGradR.addColorStop(1, 'rgba(255,255,255,0)');

      ctx.beginPath();
      ctx.moveTo(s.x, s.y);
      ctx.quadraticCurveTo(
        lerp(s.x, rTip.x, 0.5) - Math.cos(s.angle) * 6 * ray.scale,
        lerp(s.y, rTip.y, 0.5) - Math.sin(s.angle) * 6 * ray.scale,
        rTip.x,
        rTip.y
      );
      ctx.strokeStyle = ribGradR;
      ctx.stroke();
    }

    // 5. Shimmering iridescent dorsal ocelli
    const spotRows = [
      { seg: 3, frac: 0.28, r: 4.2 },
      { seg: 4, frac: 0.42, r: 3.6 },
      { seg: 5, frac: 0.24, r: 4.6 },
      { seg: 6, frac: 0.52, r: 3.0 },
      { seg: 7, frac: 0.34, r: 3.4 },
      { seg: 8, frac: 0.22, r: 2.7 }
    ];
    for (let sIdx = 0; sIdx < spotRows.length; sIdx++) {
      const sp = spotRows[sIdx];
      const seg = spine[sp.seg];
      const lP = leftPts[sp.seg + 1];
      const rP = rightPts[sp.seg + 1];
      const shimmer = 0.72 + 0.28 * Math.sin(t * 1.4 + sIdx * 1.1 + ray.orbitSeed);
      const rad = sp.r * ray.scale;

      for (const tip of [lP, rP]) {
        const sx = lerp(seg.x, tip.x, sp.frac);
        const sy = lerp(seg.y, tip.y, sp.frac);
        ctx.save();
        ctx.globalAlpha = shimmer;
        ctx.beginPath();
        ctx.arc(sx, sy, rad, 0, Math.PI * 2);
        ctx.fillStyle = palette.spot;
        ctx.fill();
        ctx.lineWidth = 0.9;
        ctx.strokeStyle = palette.spotRing;
        ctx.stroke();
        ctx.restore();
      }
    }

    // 6. Luminous translucent dorsal spine filament
    ctx.beginPath();
    ctx.moveTo(snoutX, snoutY);
    for (let i = 0; i <= bodySegs; i++) {
      ctx.lineTo(spine[i].x, spine[i].y);
    }
    ctx.lineWidth = 3.2 * ray.scale;
    ctx.lineCap = 'round';
    ctx.strokeStyle = palette.spineGlow;
    ctx.stroke();

    // Subtle paired translucent gill slits
    ctx.lineWidth = 0.9 * ray.scale;
    ctx.strokeStyle = palette.rimInner;
    for (let g = 2; g <= 5; g++) {
      const gs = spine[g];
      const gPerpX = -Math.sin(gs.angle);
      const gPerpY = Math.cos(gs.angle);
      const gFwdX = Math.cos(gs.angle);
      const gFwdY = Math.sin(gs.angle);
      const offset = (9 + (g - 2) * 1.4) * ray.scale;
      const len = 5.5 * ray.scale;
      for (const side of [-1, 1]) {
        const gx = gs.x + gPerpX * side * offset;
        const gy = gs.y + gPerpY * side * offset;
        ctx.beginPath();
        ctx.moveTo(gx + gFwdX * 1.2, gy + gFwdY * 1.2);
        ctx.lineTo(gx + gPerpX * side * len - gFwdX * 1.5, gy + gPerpY * side * len - gFwdY * 1.5);
        ctx.stroke();
      }
    }

    ctx.restore();

    // 7. Crisp Liquid-Glass Specular Outer Edge Rim
    ctx.save();
    traceBodyPath(0, 0);
    ctx.lineWidth = 1.75 * ray.scale;
    ctx.strokeStyle = palette.rimOuter;
    ctx.stroke();

    ctx.lineWidth = 0.9 * ray.scale;
    ctx.strokeStyle = palette.rimInner;
    ctx.stroke();

    // Wide-set glassy pelagic eyes
    const eyeSeg = spine[1];
    const ePerpX = -Math.sin(eyeSeg.angle);
    const ePerpY = Math.cos(eyeSeg.angle);
    const eFwdX = Math.cos(eyeSeg.angle);
    const eFwdY = Math.sin(eyeSeg.angle);
    for (const side of [-1, 1]) {
      const ex = eyeSeg.x + eFwdX * (5 * ray.scale) + ePerpX * side * (12.5 * ray.scale);
      const ey = eyeSeg.y + eFwdY * (5 * ray.scale) + ePerpY * side * (12.5 * ray.scale);
      ctx.beginPath();
      ctx.ellipse(ex, ey, 2.3 * ray.scale, 1.4 * ray.scale, eyeSeg.angle, 0, Math.PI * 2);
      ctx.fillStyle = palette.eye;
      ctx.fill();
    }
    ctx.restore();
  }

  function drawBlackholeSpace(t, dt, isLight) {
    const cx = width * 0.5 + Math.sin(t * 0.11) * 14;
    const cy = height * 0.5 + Math.cos(t * 0.09) * 10;
    const maxR = maxViewportRadius();
    const horizonR = Math.min(width, height) * 0.06;
    const photonR = Math.min(width, height) * 0.165;

    // 1. Subtle darkened gravitational well pulling softly toward the center
    const wellGrad = ctx.createRadialGradient(cx, cy, horizonR * 0.25, cx, cy, maxR * 0.78);
    if (isLight) {
      wellGrad.addColorStop(0, 'rgba(13, 27, 56, 0.22)');
      wellGrad.addColorStop(0.18, 'rgba(20, 42, 82, 0.12)');
      wellGrad.addColorStop(0.45, 'rgba(30, 58, 108, 0.05)');
      wellGrad.addColorStop(1, 'rgba(30, 58, 108, 0)');
    } else {
      wellGrad.addColorStop(0, 'rgba(0, 2, 7, 0.78)');
      wellGrad.addColorStop(0.18, 'rgba(2, 6, 16, 0.42)');
      wellGrad.addColorStop(0.48, 'rgba(6, 14, 30, 0.14)');
      wellGrad.addColorStop(1, 'rgba(6, 14, 30, 0)');
    }
    ctx.fillStyle = wellGrad;
    ctx.beginPath();
    ctx.arc(cx, cy, maxR * 0.78, 0, Math.PI * 2);
    ctx.fill();

    // 2. Soft rotating accretion-halo glow rings around the distant event horizon
    ctx.save();
    ctx.translate(cx, cy);
    for (let a = 0; a < 4; a++) {
      const rot = t * (0.045 + a * 0.012) + a * (Math.PI * 0.5);
      const rx = photonR * (1.05 + a * 0.48);
      const ry = rx * (0.76 + (a % 2) * 0.08);
      ctx.save();
      ctx.rotate(rot);
      ctx.beginPath();
      ctx.ellipse(0, 0, rx, ry, 0, 0, Math.PI * 1.18);
      ctx.lineWidth = 1.6 + a * 0.5;
      ctx.strokeStyle = isLight
        ? `rgba(30, 74, 158, ${0.075 - a * 0.013})`
        : `rgba(96, 165, 250, ${0.11 - a * 0.018})`;
      ctx.stroke();
      ctx.restore();
    }
    ctx.restore();

    // 3. Very slowly contracting concentric spacetime lensing rings (moving inward into the blackhole)
    ctx.save();
    ctx.translate(cx, cy);
    for (const ring of lensRings) {
      if (dt > 0) {
        // Complete one calm inward contraction every ~32 seconds
        ring.phase -= dt * 0.031;
        if (ring.phase <= 0) ring.phase += 1;
      }
      // Exponential curve creates authentic depth acceleration as rings approach the horizon
      const eased = Math.pow(ring.phase, 1.55);
      const radius = horizonR * 0.8 + eased * (maxR - horizonR * 0.8);
      // Fade in gently at outer edge and dissolve smoothly at the horizon
      const fade = Math.sin(ring.phase * Math.PI);
      const alpha = (isLight ? 0.11 : 0.13) * fade * fade;

      ctx.save();
      ctx.rotate(ring.rotOffset + t * 0.025 + (1 - ring.phase) * 0.65);
      ctx.beginPath();
      ctx.ellipse(0, 0, radius, radius * ring.tilt, 0, 0, Math.PI * 2);
      ctx.lineWidth = 0.8 + (1 - ring.phase) * 0.7;
      ctx.strokeStyle = isLight
        ? `rgba(29, 78, 216, ${alpha})`
        : `rgba(125, 211, 252, ${alpha})`;
      ctx.stroke();
      ctx.restore();
    }
    ctx.restore();

    // 4. Slow inward-spiraling cosmic dust / stretched starlight streaks
    const lightTints = ['30, 64, 148', '14, 116, 190', '79, 70, 229'];
    const darkTints = ['186, 230, 253', '129, 140, 248', '94, 234, 212'];

    for (let i = 0; i < spaceParticles.length; i++) {
      const sp = spaceParticles[i];
      const normDist = Math.max(0.01, (sp.r - horizonR) / Math.max(1, maxR - horizonR));

      if (dt > 0) {
        // Gentle gravitational pull: very slow far out, subtly quicker near the photon sphere
        const gravityPull = 1 + 1.9 * Math.pow(1 - Math.min(1, normDist), 2.1);
        sp.r -= sp.infallSpeed * gravityPull * dt;
        sp.angle += sp.angularSpeed * (0.75 + 1.65 * (1 - Math.min(1, normDist))) * dt;

        if (sp.r <= horizonR * 0.85) {
          const fresh = createSpaceParticle(true);
          sp.r = fresh.r;
          sp.angle = fresh.angle;
          sp.infallSpeed = fresh.infallSpeed;
          sp.angularSpeed = fresh.angularSpeed;
          sp.size = fresh.size;
          sp.alpha = fresh.alpha;
        }
      }

      const px = cx + Math.cos(sp.angle) * sp.r;
      const py = cy + Math.sin(sp.angle) * sp.r;

      // Short curved spiral trail pointing back along where the particle drifted from
      const trailR = sp.r + (7 + 16 * (1 - Math.min(1, normDist)));
      const trailAngle = sp.angle - (0.025 + 0.055 * (1 - Math.min(1, normDist)));
      const tx = cx + Math.cos(trailAngle) * trailR;
      const ty = cy + Math.sin(trailAngle) * trailR;

      const edgeFade = Math.min(1, normDist * 5.2) * Math.min(1, (1.12 - normDist) * 4.5);
      const twinkle = 0.72 + 0.28 * Math.sin(t * 0.9 + sp.phase);
      const a = sp.alpha * Math.max(0, edgeFade) * twinkle * (isLight ? 0.58 : 0.72);
      if (a <= 0.004) continue;

      const rgb = isLight ? lightTints[sp.tintIdx] : darkTints[sp.tintIdx];
      const grad = ctx.createLinearGradient(px, py, tx, ty);
      grad.addColorStop(0, `rgba(${rgb}, ${a})`);
      grad.addColorStop(1, `rgba(${rgb}, 0)`);

      ctx.beginPath();
      ctx.moveTo(px, py);
      ctx.lineTo(tx, ty);
      ctx.lineWidth = sp.size * (0.75 + 0.35 * (1 - Math.min(1, normDist)));
      ctx.lineCap = 'round';
      ctx.strokeStyle = grad;
      ctx.stroke();
    }

    // 5. Faint luminous photon ring edge around the central singularity
    const ringGrad = ctx.createRadialGradient(cx, cy, horizonR * 0.6, cx, cy, photonR * 1.15);
    if (isLight) {
      ringGrad.addColorStop(0, 'rgba(15, 29, 58, 0.14)');
      ringGrad.addColorStop(0.58, 'rgba(56, 139, 235, 0.09)');
      ringGrad.addColorStop(0.72, 'rgba(255, 255, 255, 0.16)');
      ringGrad.addColorStop(1, 'rgba(255, 255, 255, 0)');
    } else {
      ringGrad.addColorStop(0, 'rgba(0, 0, 4, 0.55)');
      ringGrad.addColorStop(0.58, 'rgba(56, 189, 248, 0.14)');
      ringGrad.addColorStop(0.72, 'rgba(186, 230, 253, 0.08)');
      ringGrad.addColorStop(1, 'rgba(56, 189, 248, 0)');
    }
    ctx.fillStyle = ringGrad;
    ctx.beginPath();
    ctx.arc(cx, cy, photonR * 1.15, 0, Math.PI * 2);
    ctx.fill();
  }

  function drawScene(nowMs, dt) {
    const t = nowMs * 0.001;
    const isLight = document.documentElement.getAttribute('data-theme') === 'light';
    ctx.clearRect(0, 0, width, height);

    // Decay pointer velocity smoothly when mouse stops
    if (nowMs - pointer.lastMoveTime > 90) {
      pointer.speed *= Math.exp(-dt * 8);
    }

    // 0. Very slow blackhole spacetime infall background motion
    drawBlackholeSpace(t, dt, isLight);

    // 1. Ambient Liquid Glass aurora pools
    for (const orb of orbs) {
      const ox = width * orb.xRatio + Math.sin(t * orb.sx + orb.p) * Math.min(140, width * 0.11);
      const oy = height * orb.yRatio + Math.cos(t * orb.sy + orb.p) * Math.min(110, height * 0.10);
      const color = isLight ? orb.light : orb.dark;
      const alpha = isLight ? orb.alphaLight : orb.alphaDark;
      const grad = ctx.createRadialGradient(ox, oy, 0, ox, oy, orb.r);
      grad.addColorStop(0, 'rgba(' + color + ', ' + alpha + ')');
      grad.addColorStop(1, 'rgba(' + color + ', 0)');
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(ox, oy, orb.r, 0, Math.PI * 2);
      ctx.fill();
    }

    // 2. Subtle drifting undersea current motes
    for (const m of motes) {
      if (dt > 0) {
        m.x += (m.vx + Math.sin(t * 0.5 + m.phase) * 5) * dt;
        m.y += m.vy * dt;
        if (m.y < -12) {
          m.y = height + 12;
          m.x = Math.random() * width;
        }
        if (m.x < -12) m.x = width + 12;
        if (m.x > width + 12) m.x = -12;
      }
      const shimmer = 0.6 + 0.4 * Math.sin(t * 1.3 + m.phase);
      ctx.beginPath();
      ctx.arc(m.x, m.y, m.r, 0, Math.PI * 2);
      ctx.fillStyle = isLight
        ? `rgba(56, 139, 235, ${m.alpha * 0.40 * shimmer})`
        : `rgba(186, 230, 253, ${m.alpha * 0.38 * shimmer})`;
      ctx.fill();
    }

    // 3. Soft expanding water ripples when pointer pushes
    for (let i = ripples.length - 1; i >= 0; i--) {
      const rp = ripples[i];
      if (dt > 0) rp.life += dt;
      if (rp.life >= rp.maxLife) {
        ripples.splice(i, 1);
        continue;
      }
      const p = rp.life / rp.maxLife;
      const eased = 1 - Math.pow(1 - p, 2.5);
      const rad = lerp(rp.r, rp.maxR, eased);
      const fade = (1 - p) * (1 - p);

      ctx.beginPath();
      ctx.arc(rp.x, rp.y, rad, 0, Math.PI * 2);
      ctx.lineWidth = 1.6 * (1 - p * 0.6);
      ctx.strokeStyle = isLight
        ? `rgba(37, 99, 235, ${0.26 * fade})`
        : `rgba(125, 211, 252, ${0.32 * fade})`;
      ctx.stroke();

      ctx.beginPath();
      ctx.arc(rp.x, rp.y, rad * 0.68, 0, Math.PI * 2);
      ctx.lineWidth = 1.0;
      ctx.strokeStyle = isLight
        ? `rgba(255, 255, 255, ${0.52 * fade})`
        : `rgba(224, 242, 254, ${0.24 * fade})`;
      ctx.stroke();
    }

    // 4. Soft wingtip wake bubbles
    for (let i = wakeParticles.length - 1; i >= 0; i--) {
      const p = wakeParticles[i];
      if (dt > 0) {
        p.life += dt;
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vx *= 0.985;
        p.vy *= 0.985;
      }
      if (p.life >= p.maxLife) {
        wakeParticles.splice(i, 1);
        continue;
      }
      const fade = Math.sin((p.life / p.maxLife) * Math.PI);
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r * (0.7 + 0.5 * (p.life / p.maxLife)), 0, Math.PI * 2);
      ctx.strokeStyle = isLight
        ? `rgba(255, 255, 255, ${0.62 * fade})`
        : `rgba(186, 230, 253, ${0.42 * fade})`;
      ctx.lineWidth = 0.95;
      ctx.stroke();
    }

    // 5. Draw deeper ray first, then hero translucent glass stingray on top
    for (let i = rays.length - 1; i >= 0; i--) {
      const ray = rays[i];
      if (dt > 0) updateRay(ray, dt, t, nowMs);
      drawStingray(ray, isLight, t);
    }
  }

  if (prefersReducedMotion) {
    drawScene(0, 0);
    window.addEventListener('resize', () => drawScene(0, 0), { passive: true });
    const observer = new MutationObserver(() => drawScene(0, 0));
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    return;
  }

  let lastTime = performance.now();
  function loop(now) {
    const dt = Math.min(0.05, Math.max(0.001, (now - lastTime) * 0.001));
    lastTime = now;
    if (!document.hidden) {
      drawScene(now, dt);
    }
    window.requestAnimationFrame(loop);
  }

  window.requestAnimationFrame(loop);
})();
