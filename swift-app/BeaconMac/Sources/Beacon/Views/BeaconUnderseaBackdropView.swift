import AppKit
import SwiftUI

/// Native macOS SwiftUI Canvas rendering a very slow blackhole gravitational-infall space field
/// behind rare translucent undersea glass stingrays that react to the pointer:
/// - Idle pointer: the stingray grows curious, swims over, and orbits gently nearby.
/// - Pushed pointer (click/drag or brisk cursor sweep): emits an expanding water ripple and
///   propels the stingray outward with a faster wingbeat and wake bubbles.
struct BeaconUnderseaBackdropView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var engine = BeaconUnderseaEngine()

    var body: some View {
        let isLight = colorScheme == .light

        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                engine.render(
                    in: &context,
                    size: size,
                    now: timeline.date.timeIntervalSinceReferenceDate,
                    isLight: isLight,
                    reducedMotion: reduceMotion
                )
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            engine.startEventMonitor()
        }
        .onDisappear {
            engine.stopEventMonitor()
        }
    }
}

// MARK: - Simulation Engine

@MainActor
private final class BeaconUnderseaEngine: ObservableObject {
    private struct SpineNode {
        var x: Double
        var y: Double
        var angle: Double
    }

    private struct Stingray {
        var spine: [SpineNode]
        var segCount: Int
        var segLen: Double
        var scale: Double
        var baseSpeed: Double
        var turnRate: Double
        var wingSpan: Double
        var baseWingFreq: Double
        var wingPhase: Double
        var opacity: Double
        var depth: Double
        var angle: Double
        var targetX: Double
        var targetY: Double
        var waypointTimer: Double
        var orbitSeed: Double
        var spawnWake: Bool
        var wakeAccum: Double
        var fleeTimer: Double
        var fleeStrength: Double
        var pushVx: Double
        var pushVy: Double
    }

    private struct SpaceParticle {
        var r: Double
        var angle: Double
        var infallSpeed: Double
        var angularSpeed: Double
        var size: Double
        var alpha: Double
        var tintIdx: Int
        var phase: Double
    }

    private struct LensRing {
        var phase: Double
        var tilt: Double
        var rotOffset: Double
    }

    private struct Mote {
        var x: Double
        var y: Double
        var r: Double
        var vx: Double
        var vy: Double
        var phase: Double
        var alpha: Double
    }

    private struct WakeBubble {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var r: Double
        var life: Double
        var maxLife: Double
    }

    private struct WaterRipple {
        var x: Double
        var y: Double
        var r: Double
        var maxR: Double
        var life: Double
        var maxLife: Double
    }

    private var initialized = false
    private var canvasSize = CGSize(width: 1280, height: 840)
    private var lastFrameTime: TimeInterval?

    private var rays: [Stingray] = []
    private var spaceParticles: [SpaceParticle] = []
    private var lensRings: [LensRing] = []
    private var motes: [Mote] = []
    private var wakeBubbles: [WakeBubble] = []
    private var ripples: [WaterRipple] = []

    // Pointer state (top-left SwiftUI coordinate space)
    private var pointerX: Double = 640
    private var pointerY: Double = 420
    private var pointerSpeed: Double = 0
    private var pointerInside: Bool = false
    private var pointerIsDown: Bool = false
    private var lastPointerMoveTime: TimeInterval = 0
    private var lastPointerEventTime: TimeInterval = 0
    private var lastThrustTime: TimeInterval = 0

    private var eventMonitor: Any?

    func startEventMonitor() {
        guard eventMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.processAppKitEvent(event)
            }
            return event
        }
    }

    func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func processAppKitEvent(_ event: NSEvent) {
        guard let window = event.window, let contentView = window.contentView else { return }
        if !window.acceptsMouseMovedEvents {
            window.acceptsMouseMovedEvents = true
        }
        let loc = event.locationInWindow
        let bounds = contentView.bounds
        let ptX = Double(loc.x)
        let ptY = Double(bounds.height - loc.y)
        let inside = ptX >= 0 && ptX <= Double(bounds.width) && ptY >= 0 && ptY <= Double(bounds.height)
        let now = Date.timeIntervalSinceReferenceDate

        switch event.type {
        case .mouseMoved, .leftMouseDragged:
            let dt = max(0.008, now - lastPointerEventTime)
            let dx = ptX - pointerX
            let dy = ptY - pointerY
            let dist = hypot(dx, dy)
            pointerX = ptX
            pointerY = ptY
            pointerInside = inside
            lastPointerEventTime = now

            if dist > 1.5 {
                lastPointerMoveTime = now
                let instSpeed = dist / dt
                pointerSpeed = lerp(pointerSpeed, instSpeed, 0.45)
            }

            if pointerIsDown && (now - lastThrustTime > 0.12) {
                lastThrustTime = now
                triggerPushAway(px: ptX, py: ptY, intensity: 1.05, maxRadius: 420)
            } else if pointerSpeed > 520 && (now - lastThrustTime > 0.18) {
                for ray in rays {
                    let c = ray.spine[min(3, ray.spine.count - 1)]
                    if hypot(c.x - ptX, c.y - ptY) < 210 * ray.scale + 70 {
                        lastThrustTime = now
                        let thrust = min(1.35, 0.65 + (pointerSpeed - 520) / 1400)
                        triggerPushAway(px: ptX, py: ptY, intensity: thrust, maxRadius: 340)
                        break
                    }
                }
            }

        case .leftMouseDown:
            pointerX = ptX
            pointerY = ptY
            pointerInside = inside
            pointerIsDown = true
            lastPointerMoveTime = now
            lastPointerEventTime = now
            lastThrustTime = now
            if inside {
                spawnRipple(x: ptX, y: ptY, strength: 0.95)
                let radius = max(460, min(Double(canvasSize.width), Double(canvasSize.height)) * 0.62)
                triggerPushAway(px: ptX, py: ptY, intensity: 1.35, maxRadius: radius)
            }

        case .leftMouseUp:
            pointerIsDown = false

        default:
            break
        }
    }

    // MARK: - Initialization

    private func ensureInitialized(size: CGSize) {
        let w = max(320, Double(size.width))
        let h = max(320, Double(size.height))
        canvasSize = CGSize(width: w, height: h)
        guard !initialized else { return }
        initialized = true

        rays = [
            makeStingray(
                segCount: 30, segLen: 10.2, scale: 1.0, speed: 56, turnRate: 1.45,
                wingSpan: 130, wingFreq: 2.2, wingPhase: 0.2, opacity: 1.0, depth: 1.0,
                startX: w * 0.20, startY: h * 0.72, startAngle: -0.45,
                targetX: w * 0.78, targetY: h * 0.28, orbitSeed: 1.3, spawnWake: true
            ),
            makeStingray(
                segCount: 24, segLen: 7.4, scale: 0.64, speed: 40, turnRate: 1.15,
                wingSpan: 84, wingFreq: 2.6, wingPhase: 2.8, opacity: 0.60, depth: 0.55,
                startX: w * 0.84, startY: h * 0.24, startAngle: 2.45,
                targetX: w * 0.24, targetY: h * 0.76, orbitSeed: 4.7, spawnWake: false
            )
        ]

        spaceParticles = (0..<84).map { _ in makeSpaceParticle(w: w, h: h, spawnAtEdge: false) }
        lensRings = (0..<8).map { i in
            LensRing(
                phase: Double(i) / 8.0,
                tilt: 0.76 + Double(i % 3) * 0.05,
                rotOffset: Double(i) * 0.78
            )
        }
        motes = (0..<24).map { _ in
            Mote(
                x: Double.random(in: 0...w),
                y: Double.random(in: 0...h),
                r: Double.random(in: 1.1...3.1),
                vx: Double.random(in: -4...4),
                vy: Double.random(in: -13 ... -4),
                phase: Double.random(in: 0...(Double.pi * 2)),
                alpha: Double.random(in: 0.20...0.50)
            )
        }
    }

    private func makeStingray(
        segCount: Int, segLen: Double, scale: Double, speed: Double, turnRate: Double,
        wingSpan: Double, wingFreq: Double, wingPhase: Double, opacity: Double, depth: Double,
        startX: Double, startY: Double, startAngle: Double, targetX: Double, targetY: Double,
        orbitSeed: Double, spawnWake: Bool
    ) -> Stingray {
        let spine = (0..<segCount).map { i in
            SpineNode(
                x: startX - cos(startAngle) * Double(i) * segLen,
                y: startY - sin(startAngle) * Double(i) * segLen,
                angle: startAngle
            )
        }
        return Stingray(
            spine: spine, segCount: segCount, segLen: segLen, scale: scale,
            baseSpeed: speed, turnRate: turnRate, wingSpan: wingSpan,
            baseWingFreq: wingFreq, wingPhase: wingPhase, opacity: opacity, depth: depth,
            angle: startAngle, targetX: targetX, targetY: targetY,
            waypointTimer: 4.0, orbitSeed: orbitSeed, spawnWake: spawnWake,
            wakeAccum: 0, fleeTimer: 0, fleeStrength: 0, pushVx: 0, pushVy: 0
        )
    }

    private func maxViewportRadius(w: Double, h: Double) -> Double {
        hypot(w * 0.5, h * 0.5) * 1.15
    }

    private func makeSpaceParticle(w: Double, h: Double, spawnAtEdge: Bool) -> SpaceParticle {
        let maxR = maxViewportRadius(w: w, h: h)
        let minR = min(w, h) * 0.055
        let normR = spawnAtEdge
            ? Double.random(in: 0.88...1.12)
            : pow(Double.random(in: 0...1), 0.62)
        return SpaceParticle(
            r: minR + normR * (maxR - minR),
            angle: Double.random(in: 0...(Double.pi * 2)),
            infallSpeed: Double.random(in: 7...18),
            angularSpeed: Double.random(in: 0.035...0.08),
            size: Double.random(in: 0.75...2.25),
            alpha: Double.random(in: 0.18...0.60),
            tintIdx: Int.random(in: 0...2),
            phase: Double.random(in: 0...(Double.pi * 2))
        )
    }

    private func spawnRipple(x: Double, y: Double, strength: Double) {
        if ripples.count > 10 { ripples.removeFirst() }
        ripples.append(WaterRipple(
            x: x, y: y, r: 8, maxR: 95 + strength * 75,
            life: 0, maxLife: 0.85 + strength * 0.35
        ))
    }

    private func spawnBurstWake(ray: Stingray, count: Int) {
        let ws = ray.spine[min(4, ray.spine.count - 1)]
        let perpX = -sin(ws.angle)
        let perpY = cos(ws.angle)
        for i in 0..<count where wakeBubbles.count < 56 {
            let side: Double = (i % 2 == 0) ? 1 : -1
            let radial = Double.random(in: 0.35...1.0) * ray.wingSpan
            wakeBubbles.append(WakeBubble(
                x: ws.x + perpX * side * radial,
                y: ws.y + perpY * side * radial,
                vx: -cos(ws.angle) * Double.random(in: 24...56) + Double.random(in: -13...13),
                vy: -sin(ws.angle) * Double.random(in: 24...56) + Double.random(in: -13...13),
                r: Double.random(in: 1.4...3.6),
                life: 0,
                maxLife: Double.random(in: 1.4...2.7)
            ))
        }
    }

    private func triggerPushAway(px: Double, py: Double, intensity: Double, maxRadius: Double) {
        let w = Double(canvasSize.width)
        let h = Double(canvasSize.height)
        var anyPushed = false

        for i in rays.indices {
            let center = rays[i].spine[min(3, rays[i].spine.count - 1)]
            let dx = center.x - px
            let dy = center.y - py
            let dist = hypot(dx, dy)
            let effectiveRadius = maxRadius * (0.75 + 0.35 * rays[i].depth)

            if dist < effectiveRadius {
                anyPushed = true
                let nx = dist > 0.001 ? dx / dist : cos(rays[i].angle)
                let ny = dist > 0.001 ? dy / dist : sin(rays[i].angle)
                let closeness = 1.0 - min(1.0, dist / effectiveRadius)
                let power = intensity * (0.55 + 0.85 * closeness) * (0.65 + 0.35 * rays[i].depth)

                rays[i].pushVx += nx * (260 * power)
                rays[i].pushVy += ny * (260 * power)
                rays[i].fleeTimer = max(rays[i].fleeTimer, 1.35 + 0.85 * closeness)
                rays[i].fleeStrength = min(1.8, max(rays[i].fleeStrength, power))

                let escapeDist = min(w, h) * (0.45 + 0.25 * closeness)
                let escapeAngle = atan2(ny, nx) + Double.random(in: -0.22...0.22)
                rays[i].targetX = max(80, min(w - 80, center.x + cos(escapeAngle) * escapeDist))
                rays[i].targetY = max(80, min(h - 80, center.y + sin(escapeAngle) * escapeDist))
                rays[i].waypointTimer = Double.random(in: 4.5...7.5)

                spawnBurstWake(ray: rays[i], count: max(2, Int(round(7 * power))))
            }
        }

        if anyPushed {
            spawnRipple(x: px, y: py, strength: min(1.2, intensity))
        }
    }

    // MARK: - Main Frame Render

    func render(in context: inout GraphicsContext, size: CGSize, now: TimeInterval, isLight: Bool, reducedMotion: Bool) {
        ensureInitialized(size: size)
        let w = max(320, Double(size.width))
        let h = max(320, Double(size.height))

        let dt: Double
        if reducedMotion {
            dt = 0
        } else if let prev = lastFrameTime {
            dt = min(0.05, max(0.001, now - prev))
        } else {
            dt = 0.016
        }
        lastFrameTime = now

        if dt > 0 && (now - lastPointerMoveTime > 0.09) {
            pointerSpeed *= exp(-dt * 8.0)
        }

        // Layer 0: Slow blackhole spacetime infall
        drawBlackholeSpace(in: &context, w: w, h: h, t: now, dt: dt, isLight: isLight)

        // Layer 1: Subtle drifting aurora pools
        drawAuroraOrbs(in: &context, w: w, h: h, t: now, isLight: isLight)

        // Layer 2: Marine motes, water ripples, and wingtip wake bubbles
        drawParticles(in: &context, w: w, h: h, t: now, dt: dt, isLight: isLight)

        // Layer 3: Distant ray then hero translucent glass stingray
        for idx in rays.indices.reversed() {
            if dt > 0 {
                updateRay(at: idx, w: w, h: h, dt: dt, t: now, now: now)
            }
            drawStingray(rays[idx], in: &context, isLight: isLight, t: now)
        }
    }

    private func drawBlackholeSpace(in context: inout GraphicsContext, w: Double, h: Double, t: Double, dt: Double, isLight: Bool) {
        let cx = w * 0.5 + sin(t * 0.11) * 14
        let cy = h * 0.5 + cos(t * 0.09) * 10
        let center = CGPoint(x: cx, y: cy)
        let maxR = maxViewportRadius(w: w, h: h)
        let horizonR = min(w, h) * 0.06
        let photonR = min(w, h) * 0.165

        // 1. Central gravitational well depth
        let wellRadius = maxR * 0.78
        let wellStops: [Gradient.Stop] = isLight
            ? [
                .init(color: Color(red: 0.051, green: 0.106, blue: 0.220).opacity(0.20), location: 0.0),
                .init(color: Color(red: 0.078, green: 0.165, blue: 0.322).opacity(0.11), location: 0.18),
                .init(color: Color(red: 0.118, green: 0.227, blue: 0.424).opacity(0.045), location: 0.46),
                .init(color: Color.clear, location: 1.0)
            ]
            : [
                .init(color: Color(red: 0.0, green: 0.008, blue: 0.027).opacity(0.76), location: 0.0),
                .init(color: Color(red: 0.008, green: 0.024, blue: 0.063).opacity(0.40), location: 0.18),
                .init(color: Color(red: 0.024, green: 0.055, blue: 0.118).opacity(0.14), location: 0.48),
                .init(color: Color.clear, location: 1.0)
            ]
        let wellRect = CGRect(x: cx - wellRadius, y: cy - wellRadius, width: wellRadius * 2, height: wellRadius * 2)
        context.fill(
            Path(ellipseIn: wellRect),
            with: .radialGradient(Gradient(stops: wellStops), center: center, startRadius: horizonR * 0.25, endRadius: wellRadius)
        )

        // 2. Soft rotating accretion-halo arcs
        for a in 0..<4 {
            let rot = t * (0.045 + Double(a) * 0.012) + Double(a) * (Double.pi * 0.5)
            let rx = photonR * (1.05 + Double(a) * 0.48)
            let ry = rx * (0.76 + Double(a % 2) * 0.08)
            let strokeColor = isLight
                ? Color(red: 0.118, green: 0.290, blue: 0.620).opacity(max(0.01, 0.075 - Double(a) * 0.013))
                : Color(red: 0.376, green: 0.647, blue: 0.980).opacity(max(0.01, 0.11 - Double(a) * 0.018))

            context.drawLayer { layer in
                layer.translateBy(x: cx, y: cy)
                layer.rotate(by: Angle(radians: rot))
                var arcPath = Path()
                let steps = 28
                for s in 0...steps {
                    let ang = (Double(s) / Double(steps)) * Double.pi * 1.18
                    let pt = CGPoint(x: cos(ang) * rx, y: sin(ang) * ry)
                    if s == 0 { arcPath.move(to: pt) } else { arcPath.addLine(to: pt) }
                }
                layer.stroke(arcPath, with: .color(strokeColor), style: StrokeStyle(lineWidth: 1.6 + Double(a) * 0.45, lineCap: .round))
            }
        }

        // 3. Slowly contracting concentric spacetime lensing rings
        for i in lensRings.indices {
            if dt > 0 {
                lensRings[i].phase -= dt * 0.031
                if lensRings[i].phase <= 0 { lensRings[i].phase += 1.0 }
            }
            let ring = lensRings[i]
            let eased = pow(ring.phase, 1.55)
            let radius = horizonR * 0.8 + eased * (maxR - horizonR * 0.8)
            let fade = sin(ring.phase * Double.pi)
            let alpha = (isLight ? 0.11 : 0.13) * fade * fade
            let ringColor = isLight
                ? Color(red: 0.114, green: 0.306, blue: 0.847).opacity(alpha)
                : Color(red: 0.490, green: 0.827, blue: 0.988).opacity(alpha)

            context.drawLayer { layer in
                layer.translateBy(x: cx, y: cy)
                layer.rotate(by: Angle(radians: ring.rotOffset + t * 0.025 + (1.0 - ring.phase) * 0.65))
                let rect = CGRect(x: -radius, y: -radius * ring.tilt, width: radius * 2, height: radius * ring.tilt * 2)
                layer.stroke(Path(ellipseIn: rect), with: .color(ringColor), lineWidth: 0.8 + (1.0 - ring.phase) * 0.65)
            }
        }

        // 4. Slow inward-spiraling cosmic dust streaks
        let lightTints: [(Double, Double, Double)] = [
            (0.118, 0.251, 0.580),
            (0.055, 0.455, 0.745),
            (0.310, 0.275, 0.898)
        ]
        let darkTints: [(Double, Double, Double)] = [
            (0.729, 0.902, 0.992),
            (0.506, 0.549, 0.973),
            (0.369, 0.918, 0.831)
        ]

        for i in spaceParticles.indices {
            let normDist = max(0.01, (spaceParticles[i].r - horizonR) / max(1.0, maxR - horizonR))
            if dt > 0 {
                let gravityPull = 1.0 + 1.9 * pow(1.0 - min(1.0, normDist), 2.1)
                spaceParticles[i].r -= spaceParticles[i].infallSpeed * gravityPull * dt
                spaceParticles[i].angle += spaceParticles[i].angularSpeed * (0.75 + 1.65 * (1.0 - min(1.0, normDist))) * dt
                if spaceParticles[i].r <= horizonR * 0.85 {
                    spaceParticles[i] = makeSpaceParticle(w: w, h: h, spawnAtEdge: true)
                }
            }

            let sp = spaceParticles[i]
            let px = cx + cos(sp.angle) * sp.r
            let py = cy + sin(sp.angle) * sp.r
            let trailR = sp.r + (7.0 + 16.0 * (1.0 - min(1.0, normDist)))
            let trailAngle = sp.angle - (0.025 + 0.055 * (1.0 - min(1.0, normDist)))
            let tx = cx + cos(trailAngle) * trailR
            let ty = cy + sin(trailAngle) * trailR

            let edgeFade = min(1.0, normDist * 5.2) * min(1.0, (1.12 - normDist) * 4.5)
            let twinkle = 0.72 + 0.28 * sin(t * 0.9 + sp.phase)
            let a = sp.alpha * max(0.0, edgeFade) * twinkle * (isLight ? 0.58 : 0.72)
            guard a > 0.004 else { continue }

            let rgb = isLight ? lightTints[sp.tintIdx] : darkTints[sp.tintIdx]
            let cHead = Color(red: rgb.0, green: rgb.1, blue: rgb.2).opacity(a)
            let cTail = Color(red: rgb.0, green: rgb.1, blue: rgb.2).opacity(0)

            var streak = Path()
            streak.move(to: CGPoint(x: px, y: py))
            streak.addLine(to: CGPoint(x: tx, y: ty))
            context.stroke(
                streak,
                with: .linearGradient(
                    Gradient(colors: [cHead, cTail]),
                    startPoint: CGPoint(x: px, y: py),
                    endPoint: CGPoint(x: tx, y: ty)
                ),
                style: StrokeStyle(lineWidth: sp.size * (0.75 + 0.35 * (1.0 - min(1.0, normDist))), lineCap: .round)
            )
        }

        // 5. Faint photon ring edge around central horizon
        let ringOuter = photonR * 1.15
        let ringStops: [Gradient.Stop] = isLight
            ? [
                .init(color: Color(red: 0.059, green: 0.114, blue: 0.227).opacity(0.13), location: 0.0),
                .init(color: Color(red: 0.220, green: 0.545, blue: 0.922).opacity(0.09), location: 0.58),
                .init(color: Color.white.opacity(0.16), location: 0.72),
                .init(color: Color.clear, location: 1.0)
            ]
            : [
                .init(color: Color(red: 0.0, green: 0.0, blue: 0.016).opacity(0.54), location: 0.0),
                .init(color: Color(red: 0.220, green: 0.741, blue: 0.973).opacity(0.14), location: 0.58),
                .init(color: Color(red: 0.729, green: 0.902, blue: 0.992).opacity(0.08), location: 0.72),
                .init(color: Color.clear, location: 1.0)
            ]
        let ringRect = CGRect(x: cx - ringOuter, y: cy - ringOuter, width: ringOuter * 2, height: ringOuter * 2)
        context.fill(
            Path(ellipseIn: ringRect),
            with: .radialGradient(Gradient(stops: ringStops), center: center, startRadius: horizonR * 0.6, endRadius: ringOuter)
        )
    }

    private func drawAuroraOrbs(in context: inout GraphicsContext, w: Double, h: Double, t: Double, isLight: Bool) {
        let specs: [(Double, Double, Double, Color, Double, Double, Double)] = [
            (0.20, 0.22, 360, isLight ? Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.11) : Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.12), 0.16, 0.13, 0.0),
            (0.80, 0.30, 400, isLight ? Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.09) : Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.11), -0.14, 0.15, 2.1),
            (0.50, 0.82, 320, isLight ? Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.08) : Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.08), 0.11, -0.12, 4.2)
        ]

        for spec in specs {
            let ox = w * spec.0 + sin(t * spec.4 + spec.6) * min(130, w * 0.11)
            let oy = h * spec.1 + cos(t * spec.5 + spec.6) * min(100, h * 0.10)
            let r = spec.2
            let rect = CGRect(x: ox - r, y: oy - r, width: r * 2, height: r * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [spec.3, Color.clear]),
                    center: CGPoint(x: ox, y: oy),
                    startRadius: 0,
                    endRadius: r
                )
            )
        }
    }

    private func drawParticles(in context: inout GraphicsContext, w: Double, h: Double, t: Double, dt: Double, isLight: Bool) {
        // Drifting marine motes
        for i in motes.indices {
            if dt > 0 {
                motes[i].x += (motes[i].vx + sin(t * 0.5 + motes[i].phase) * 5.0) * dt
                motes[i].y += motes[i].vy * dt
                if motes[i].y < -12 {
                    motes[i].y = h + 12
                    motes[i].x = Double.random(in: 0...w)
                }
                if motes[i].x < -12 { motes[i].x = w + 12 }
                if motes[i].x > w + 12 { motes[i].x = -12 }
            }
            let m = motes[i]
            let shimmer = 0.6 + 0.4 * sin(t * 1.3 + m.phase)
            let color = isLight
                ? Color(red: 0.220, green: 0.545, blue: 0.922).opacity(m.alpha * 0.40 * shimmer)
                : Color(red: 0.729, green: 0.902, blue: 0.992).opacity(m.alpha * 0.38 * shimmer)
            let rect = CGRect(x: m.x - m.r, y: m.y - m.r, width: m.r * 2, height: m.r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }

        // Expanding water ripples on pointer push
        for i in stride(from: ripples.count - 1, through: 0, by: -1) {
            if dt > 0 { ripples[i].life += dt }
            if ripples[i].life >= ripples[i].maxLife {
                ripples.remove(at: i)
                continue
            }
            let rp = ripples[i]
            let p = rp.life / rp.maxLife
            let eased = 1.0 - pow(1.0 - p, 2.5)
            let rad = lerp(rp.r, rp.maxR, eased)
            let fade = (1.0 - p) * (1.0 - p)

            let outerRect = CGRect(x: rp.x - rad, y: rp.y - rad, width: rad * 2, height: rad * 2)
            let outerColor = isLight
                ? Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.26 * fade)
                : Color(red: 0.490, green: 0.827, blue: 0.988).opacity(0.32 * fade)
            context.stroke(Path(ellipseIn: outerRect), with: .color(outerColor), lineWidth: 1.6 * (1.0 - p * 0.6))

            let innerRad = rad * 0.68
            let innerRect = CGRect(x: rp.x - innerRad, y: rp.y - innerRad, width: innerRad * 2, height: innerRad * 2)
            let innerColor = isLight
                ? Color.white.opacity(0.52 * fade)
                : Color(red: 0.878, green: 0.949, blue: 0.996).opacity(0.24 * fade)
            context.stroke(Path(ellipseIn: innerRect), with: .color(innerColor), lineWidth: 1.0)
        }

        // Wingtip wake bubbles
        for i in stride(from: wakeBubbles.count - 1, through: 0, by: -1) {
            if dt > 0 {
                wakeBubbles[i].life += dt
                wakeBubbles[i].x += wakeBubbles[i].vx * dt
                wakeBubbles[i].y += wakeBubbles[i].vy * dt
                wakeBubbles[i].vx *= 0.985
                wakeBubbles[i].vy *= 0.985
            }
            if wakeBubbles[i].life >= wakeBubbles[i].maxLife {
                wakeBubbles.remove(at: i)
                continue
            }
            let b = wakeBubbles[i]
            let fade = sin((b.life / b.maxLife) * Double.pi)
            let rad = b.r * (0.7 + 0.5 * (b.life / b.maxLife))
            let rect = CGRect(x: b.x - rad, y: b.y - rad, width: rad * 2, height: rad * 2)
            let color = isLight
                ? Color.white.opacity(0.62 * fade)
                : Color(red: 0.729, green: 0.902, blue: 0.992).opacity(0.42 * fade)
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 0.95)
        }
    }

    // MARK: - Stingray Physics & Rendering

    private func pickNextWaypoint(for idx: Int, w: Double, h: Double) {
        let marginX = min(120.0, w * 0.12)
        let marginY = min(110.0, h * 0.12)
        let head = rays[idx].spine[0]
        var tx = Double.random(in: marginX...max(marginX + 40, w - marginX))
        var ty = Double.random(in: marginY...max(marginY + 40, h - marginY))

        if hypot(tx - head.x, ty - head.y) < min(w, h) * 0.35 {
            tx = head.x < w * 0.5 ? w * Double.random(in: 0.66...0.90) : w * Double.random(in: 0.10...0.34)
            ty = head.y < h * 0.5 ? h * Double.random(in: 0.64...0.88) : h * Double.random(in: 0.12...0.36)
        }

        rays[idx].targetX = tx
        rays[idx].targetY = ty
        rays[idx].waypointTimer = Double.random(in: 5.5...10.5)
    }

    private func updateRay(at idx: Int, w: Double, h: Double, dt: Double, t: Double, now: TimeInterval) {
        rays[idx].waypointTimer -= dt

        if rays[idx].fleeTimer > 0 {
            rays[idx].fleeTimer = max(0, rays[idx].fleeTimer - dt)
            rays[idx].fleeStrength = lerp(rays[idx].fleeStrength, 0, min(1.0, dt * 1.4))
        } else {
            rays[idx].fleeStrength = lerp(rays[idx].fleeStrength, 0, min(1.0, dt * 2.5))
        }

        let pushDecay = exp(-dt * 3.1)
        rays[idx].pushVx *= pushDecay
        rays[idx].pushVy *= pushDecay

        let head = rays[idx].spine[0]
        let isPointerIdle = pointerInside && !pointerIsDown && (now - lastPointerMoveTime > 0.42)

        var goalX = rays[idx].targetX
        var goalY = rays[idx].targetY
        var approachingIdle = false
        var distToPointer = Double.infinity

        if rays[idx].fleeTimer > 0 {
            let outDx = head.x - pointerX
            let outDy = head.y - pointerY
            let outDist = max(1.0, hypot(outDx, outDy))
            let fleePull = min(1.0, rays[idx].fleeTimer / 0.8)
            goalX = lerp(rays[idx].targetX, head.x + (outDx / outDist) * 320, fleePull * 0.72)
            goalY = lerp(rays[idx].targetY, head.y + (outDy / outDist) * 320, fleePull * 0.72)
        } else if isPointerIdle {
            approachingIdle = true
            distToPointer = hypot(pointerX - head.x, pointerY - head.y)
            let hoverRadius = rays[idx].depth > 0.8 ? 58.0 : 145.0
            let orbitDir = rays[idx].depth > 0.8 ? 1.0 : -1.0
            let orbitSpeed = rays[idx].depth > 0.8 ? 0.62 : 0.42
            let orbitAngle = t * orbitSpeed * orbitDir + rays[idx].orbitSeed

            if distToPointer > hoverRadius + 45 {
                let approachAngle = atan2(pointerY - head.y, pointerX - head.x)
                let tangentOffset = min(34.0, distToPointer * 0.14) * orbitDir
                goalX = pointerX - sin(approachAngle) * tangentOffset
                goalY = pointerY + cos(approachAngle) * tangentOffset
            } else {
                goalX = pointerX + cos(orbitAngle) * hoverRadius
                goalY = pointerY + sin(orbitAngle) * hoverRadius
            }
        }

        let dx = goalX - head.x
        let dy = goalY - head.y
        if !approachingIdle && rays[idx].fleeTimer <= 0 && (hypot(dx, dy) < 105 || rays[idx].waypointTimer <= 0) {
            pickNextWaypoint(for: idx, w: w, h: h)
        }

        let swayAmt = approachingIdle ? 0.08 : (rays[idx].fleeTimer > 0 ? 0.04 : 0.22)
        let sway = sin(t * 0.65 + rays[idx].orbitSeed) * swayAmt
        let diff = wrapAngle(atan2(dy, dx) + sway - rays[idx].angle)

        let activeTurnRate = rays[idx].fleeTimer > 0
            ? rays[idx].turnRate * 2.55
            : (approachingIdle ? rays[idx].turnRate * 1.65 : rays[idx].turnRate)
        let maxTurn = activeTurnRate * dt
        let turnGain = rays[idx].fleeTimer > 0 ? 4.2 : (approachingIdle ? 3.1 : 2.2)
        rays[idx].angle = wrapAngle(rays[idx].angle + max(-maxTurn, min(maxTurn, diff * turnGain * dt)))

        let wingFreqMult = rays[idx].fleeTimer > 0
            ? 1.0 + 1.15 * min(1.4, rays[idx].fleeStrength)
            : (approachingIdle && distToPointer < 120 ? 0.85 : 1.08)
        rays[idx].wingPhase += dt * rays[idx].baseWingFreq * wingFreqMult

        let glideBoost = 0.84 + 0.30 * pow(0.5 + 0.5 * sin(rays[idx].wingPhase - 0.6), 1.6)
        let speedMult: Double
        if rays[idx].fleeTimer > 0 {
            speedMult = 1.0 + 1.85 * min(1.5, rays[idx].fleeStrength)
        } else if approachingIdle {
            speedMult = distToPointer > 130 ? 1.28 : 0.72
        } else {
            speedMult = 1.0
        }

        let step = rays[idx].baseSpeed * speedMult * glideBoost * dt
        rays[idx].spine[0].x += cos(rays[idx].angle) * step + rays[idx].pushVx * dt
        rays[idx].spine[0].y += sin(rays[idx].angle) * step + rays[idx].pushVy * dt
        rays[idx].spine[0].angle = rays[idx].angle

        let pad = 210.0
        if rays[idx].spine[0].x < -pad { rays[idx].spine[0].x = w + pad * 0.55 }
        if rays[idx].spine[0].x > w + pad { rays[idx].spine[0].x = -pad * 0.55 }
        if rays[idx].spine[0].y < -pad { rays[idx].spine[0].y = h + pad * 0.55 }
        if rays[idx].spine[0].y > h + pad { rays[idx].spine[0].y = -pad * 0.55 }

        for s in 1..<rays[idx].segCount {
            let prev = rays[idx].spine[s - 1]
            let curr = rays[idx].spine[s]
            var segAngle = atan2(prev.y - curr.y, prev.x - curr.x)
            if s > 12 {
                let tailProgress = Double(s - 12) / Double(rays[idx].segCount - 12)
                let tailAmp = rays[idx].fleeTimer > 0 ? 0.095 : 0.055
                segAngle += sin(rays[idx].wingPhase * 1.15 - Double(s) * 0.34) * tailAmp * tailProgress
            }
            rays[idx].spine[s].angle = segAngle
            rays[idx].spine[s].x = prev.x - cos(segAngle) * rays[idx].segLen
            rays[idx].spine[s].y = prev.y - sin(segAngle) * rays[idx].segLen
        }

        if rays[idx].spawnWake {
            rays[idx].wakeAccum += dt
            let interval = rays[idx].fleeTimer > 0 ? 0.09 : 0.22
            if rays[idx].wakeAccum > interval && wakeBubbles.count < 48 {
                rays[idx].wakeAccum = 0
                let ws = rays[idx].spine[4]
                let side: Double = Bool.random() ? 1 : -1
                let tipDist = rays[idx].wingSpan * (0.76 + 0.14 * sin(rays[idx].wingPhase - 1.1))
                let speedBase = rays[idx].fleeTimer > 0 ? 22.0 : 8.0
                wakeBubbles.append(WakeBubble(
                    x: ws.x - sin(ws.angle) * side * tipDist,
                    y: ws.y + cos(ws.angle) * side * tipDist,
                    vx: -cos(ws.angle) * speedBase + Double.random(in: -4...4),
                    vy: -sin(ws.angle) * speedBase + Double.random(in: -4...4),
                    r: Double.random(in: 1.2...3.1),
                    life: 0,
                    maxLife: Double.random(in: 2.0...3.6)
                ))
            }
        }
    }

    private func wingWidthProfile(_ u: Double) -> Double {
        if u <= 0 { return 0 }
        if u < 0.36 {
            return pow(sin((u / 0.36) * Double.pi * 0.5), 0.78)
        }
        let mainTaper = pow(cos(((u - 0.36) / 0.64) * Double.pi * 0.5), 1.35)
        let pelvicBump = exp(-pow((u - 0.86) / 0.085, 2.0)) * 0.14
        return max(0.03, mainTaper + pelvicBump)
    }

    private func drawStingray(_ ray: Stingray, in context: inout GraphicsContext, isLight: Bool, t: Double) {
        let spine = ray.spine
        let bodySegs = min(13, spine.count - 2)
        let a = ray.opacity

        let shadowColor = isLight
            ? Color(red: 0.098, green: 0.243, blue: 0.541).opacity(0.095 * a)
            : Color(red: 0.0, green: 0.024, blue: 0.071).opacity(0.28 * a)
        let bodyCore = isLight
            ? Color(red: 0.055, green: 0.431, blue: 0.824).opacity(0.30 * a)
            : Color(red: 0.220, green: 0.741, blue: 0.973).opacity(0.32 * a)
        let bodyMid = isLight
            ? Color(red: 0.149, green: 0.698, blue: 0.961).opacity(0.22 * a)
            : Color(red: 0.388, green: 0.400, blue: 0.945).opacity(0.22 * a)
        let bodyEdge = isLight
            ? Color(red: 0.388, green: 0.400, blue: 0.945).opacity(0.09 * a)
            : Color(red: 0.176, green: 0.831, blue: 0.749).opacity(0.08 * a)
        let rimOuter = isLight
            ? Color.white.opacity(0.78 * a)
            : Color(red: 0.729, green: 0.902, blue: 0.992).opacity(0.58 * a)
        let rimInner = isLight
            ? Color(red: 0.114, green: 0.306, blue: 0.847).opacity(0.38 * a)
            : Color(red: 0.220, green: 0.741, blue: 0.973).opacity(0.38 * a)
        let ribColor = isLight
            ? Color.white.opacity(0.42 * a)
            : Color(red: 0.729, green: 0.902, blue: 0.992).opacity(0.24 * a)
        let ribTint = isLight
            ? Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.20 * a)
            : Color(red: 0.220, green: 0.741, blue: 0.973).opacity(0.18 * a)
        let spineGlow = isLight
            ? Color.white.opacity(0.68 * a)
            : Color(red: 0.878, green: 0.949, blue: 0.996).opacity(0.54 * a)
        let spotColor = isLight
            ? Color.white.opacity(0.56 * a)
            : Color(red: 0.729, green: 0.902, blue: 0.992).opacity(0.46 * a)
        let spotRing = isLight
            ? Color(red: 0.055, green: 0.647, blue: 0.914).opacity(0.32 * a)
            : Color(red: 0.176, green: 0.831, blue: 0.749).opacity(0.34 * a)
        let tailColor = isLight
            ? Color(red: 0.114, green: 0.306, blue: 0.847).opacity(0.34 * a)
            : Color(red: 0.490, green: 0.827, blue: 0.988).opacity(0.40 * a)
        let tailHighlight = isLight
            ? Color.white.opacity(0.60 * a)
            : Color(red: 0.878, green: 0.949, blue: 0.996).opacity(0.50 * a)
        let eyeColor = isLight
            ? Color(red: 0.059, green: 0.137, blue: 0.306).opacity(0.52 * a)
            : Color(red: 0.878, green: 0.949, blue: 0.996).opacity(0.65 * a)

        let head = spine[0]
        let hfx = cos(head.angle)
        let hfy = sin(head.angle)
        let hpx = -hfy
        let hpy = hfx
        let snoutX = head.x + hfx * (13 * ray.scale)
        let snoutY = head.y + hfy * (13 * ray.scale)

        var leftPts: [CGPoint] = [
            CGPoint(x: head.x + hfx * (18 * ray.scale) + hpx * (14 * ray.scale),
                    y: head.y + hfy * (18 * ray.scale) + hpy * (14 * ray.scale))
        ]
        var rightPts: [CGPoint] = [
            CGPoint(x: head.x + hfx * (18 * ray.scale) - hpx * (14 * ray.scale),
                    y: head.y + hfy * (18 * ray.scale) - hpy * (14 * ray.scale))
        ]

        let flexAmp = ray.fleeTimer > 0 ? 0.22 : 0.16
        for i in 0...bodySegs {
            let seg = spine[i]
            let u = Double(i) / Double(bodySegs)
            let bp = wingWidthProfile(u)
            let wp = ray.wingPhase - u * 2.85
            let wf = sin(wp)
            let span = ray.wingSpan * bp * (0.86 + flexAmp * wf + cos(wp * 2.0 - 0.5) * 0.04)
            let sweep = (-8.0 + 18.0 * wf) * bp * ray.scale
            let fx = cos(seg.angle)
            let fy = sin(seg.angle)
            let px = -fy
            let py = fx
            leftPts.append(CGPoint(x: seg.x - fx * sweep + px * span, y: seg.y - fy * sweep + py * span))
            rightPts.append(CGPoint(x: seg.x - fx * sweep - px * span, y: seg.y - fy * sweep - py * span))
        }

        func buildBodyPath(offsetX: Double, offsetY: Double) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: snoutX + offsetX, y: snoutY + offsetY))
            for i in 0..<(leftPts.count - 1) {
                let c = leftPts[i]
                let n = leftPts[i + 1]
                p.addQuadCurve(
                    to: CGPoint(x: (Double(c.x) + Double(n.x)) * 0.5 + offsetX, y: (Double(c.y) + Double(n.y)) * 0.5 + offsetY),
                    control: CGPoint(x: Double(c.x) + offsetX, y: Double(c.y) + offsetY)
                )
            }
            let lastL = leftPts[leftPts.count - 1]
            let tailBase = spine[bodySegs]
            let lastR = rightPts[rightPts.count - 1]
            p.addLine(to: CGPoint(x: Double(lastL.x) + offsetX, y: Double(lastL.y) + offsetY))
            p.addLine(to: CGPoint(x: tailBase.x + offsetX, y: tailBase.y + offsetY))
            p.addLine(to: CGPoint(x: Double(lastR.x) + offsetX, y: Double(lastR.y) + offsetY))
            for i in stride(from: rightPts.count - 1, through: 1, by: -1) {
                let c = rightPts[i]
                let pr = rightPts[i - 1]
                p.addQuadCurve(
                    to: CGPoint(x: (Double(c.x) + Double(pr.x)) * 0.5 + offsetX, y: (Double(c.y) + Double(pr.y)) * 0.5 + offsetY),
                    control: CGPoint(x: Double(c.x) + offsetX, y: Double(c.y) + offsetY)
                )
            }
            p.addQuadCurve(
                to: CGPoint(x: snoutX + offsetX, y: snoutY + offsetY),
                control: CGPoint(x: Double(rightPts[0].x) + offsetX, y: Double(rightPts[0].y) + offsetY)
            )
            p.closeSubpath()
            return p
        }

        // 1. Soft underwater offset shadow
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.fill(buildBodyPath(offsetX: 14 * ray.scale, offsetY: 22 * ray.scale), with: .color(shadowColor))
        }

        // 2. Whip-like tapered stingray tail
        for i in (bodySegs - 1)..<(ray.segCount - 1) {
            let p0 = spine[i]
            let p1 = spine[i + 1]
            let frac = 1.0 - Double(i - (bodySegs - 1)) / Double(max(1, ray.segCount - bodySegs))
            let tailW = max(0.65, 5.2 * ray.scale * pow(max(0, frac), 1.8))
            var segPath = Path()
            segPath.move(to: CGPoint(x: p0.x, y: p0.y))
            segPath.addLine(to: CGPoint(x: p1.x, y: p1.y))
            context.stroke(segPath, with: .color(tailColor), style: StrokeStyle(lineWidth: tailW, lineCap: .round))
            if frac > 0.25 {
                context.stroke(segPath, with: .color(tailHighlight), style: StrokeStyle(lineWidth: max(0.4, tailW * 0.32), lineCap: .round))
            }
        }

        // 3. Translucent glass body disc + clipped internal anatomy
        let bodyPath = buildBodyPath(offsetX: 0, offsetY: 0)
        let cs = spine[min(4, spine.count - 1)]
        context.drawLayer { layer in
            layer.fill(
                bodyPath,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: bodyCore, location: 0.0),
                        .init(color: bodyMid, location: 0.52),
                        .init(color: bodyEdge, location: 1.0)
                    ]),
                    center: CGPoint(x: cs.x, y: cs.y),
                    startRadius: 4 * ray.scale,
                    endRadius: ray.wingSpan * 1.08
                )
            )

            layer.clip(to: bodyPath)

            // Cartilaginous radial fin rays
            for i in 2...(bodySegs - 2) {
                let s = spine[i]
                let startPt = CGPoint(x: s.x, y: s.y)
                for tip in [leftPts[i + 1], rightPts[i + 1]] {
                    var ribPath = Path()
                    ribPath.move(to: startPt)
                    let ctrl = CGPoint(
                        x: lerp(s.x, Double(tip.x), 0.5) - cos(s.angle) * 6 * ray.scale,
                        y: lerp(s.y, Double(tip.y), 0.5) - sin(s.angle) * 6 * ray.scale
                    )
                    ribPath.addQuadCurve(to: tip, control: ctrl)
                    layer.stroke(
                        ribPath,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: ribColor, location: 0.0),
                                .init(color: ribTint, location: 0.65),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            startPoint: startPt,
                            endPoint: tip
                        ),
                        lineWidth: 0.9 * ray.scale
                    )
                }
            }

            // Shimmering dorsal ocelli
            let spots: [(Int, Double, Double)] = [
                (3, 0.28, 4.2), (4, 0.42, 3.6), (5, 0.24, 4.6),
                (6, 0.52, 3.0), (7, 0.34, 3.4), (8, 0.22, 2.7)
            ]
            for (sIdx, sp) in spots.enumerated() where sp.0 + 1 < leftPts.count {
                let seg = spine[sp.0]
                let shimmer = 0.72 + 0.28 * sin(t * 1.4 + Double(sIdx) * 1.1 + ray.orbitSeed)
                let rad = sp.2 * ray.scale
                for tip in [leftPts[sp.0 + 1], rightPts[sp.0 + 1]] {
                    let sx = lerp(seg.x, Double(tip.x), sp.1)
                    let sy = lerp(seg.y, Double(tip.y), sp.1)
                    let rect = CGRect(x: sx - rad, y: sy - rad, width: rad * 2, height: rad * 2)
                    layer.fill(Path(ellipseIn: rect), with: .color(spotColor.opacity(shimmer)))
                    layer.stroke(Path(ellipseIn: rect), with: .color(spotRing.opacity(shimmer)), lineWidth: 0.9)
                }
            }

            // Luminous dorsal spine filament
            var spinePath = Path()
            spinePath.move(to: CGPoint(x: snoutX, y: snoutY))
            for i in 0...bodySegs {
                spinePath.addLine(to: CGPoint(x: spine[i].x, y: spine[i].y))
            }
            layer.stroke(spinePath, with: .color(spineGlow), style: StrokeStyle(lineWidth: 3.2 * ray.scale, lineCap: .round))

            // Subtle paired gill slits
            for g in 2...5 where g < spine.count {
                let gs = spine[g]
                let gpx = -sin(gs.angle)
                let gpy = cos(gs.angle)
                let gfx = cos(gs.angle)
                let gfy = sin(gs.angle)
                let offset = (9.0 + Double(g - 2) * 1.4) * ray.scale
                let len = 5.5 * ray.scale
                for side in [-1.0, 1.0] {
                    let gx = gs.x + gpx * side * offset
                    let gy = gs.y + gpy * side * offset
                    var gill = Path()
                    gill.move(to: CGPoint(x: gx + gfx * 1.2, y: gy + gfy * 1.2))
                    gill.addLine(to: CGPoint(x: gx + gpx * side * len - gfx * 1.5, y: gy + gpy * side * len - gfy * 1.5))
                    layer.stroke(gill, with: .color(rimInner), lineWidth: 0.9 * ray.scale)
                }
            }
        }

        // 4. Crisp Liquid-Glass outer specular rim + wide-set pelagic eyes
        context.stroke(bodyPath, with: .color(rimOuter), lineWidth: 1.75 * ray.scale)
        context.stroke(bodyPath, with: .color(rimInner), lineWidth: 0.9 * ray.scale)

        let es = spine[1]
        let efx = cos(es.angle)
        let efy = sin(es.angle)
        let epx = -efy
        let epy = efx
        for side in [-1.0, 1.0] {
            let ex = es.x + efx * (5 * ray.scale) + epx * side * (12.5 * ray.scale)
            let ey = es.y + efy * (5 * ray.scale) + epy * side * (12.5 * ray.scale)
            context.drawLayer { layer in
                layer.translateBy(x: ex, y: ey)
                layer.rotate(by: Angle(radians: es.angle))
                let ew = 2.3 * ray.scale
                let eh = 1.4 * ray.scale
                layer.fill(Path(ellipseIn: CGRect(x: -ew, y: -eh, width: ew * 2, height: eh * 2)), with: .color(eyeColor))
            }
        }
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func wrapAngle(_ a: Double) -> Double {
        var v = a
        while v > Double.pi { v -= Double.pi * 2 }
        while v < -Double.pi { v += Double.pi * 2 }
        return v
    }
}
