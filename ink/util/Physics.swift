//
//  OrbPhysics.swift
//  ink
//
//  Created by Dylan Karunanayake on 6/11/2026.
//

import SwiftUI

@MainActor
@Observable
final class OrbPhysics {
    var position: CGPoint = .zero // top left
    var dockCount = 0

    // Tuning
    @ObservationIgnored private let stiffness: CGFloat = 140 // magnet strength
    @ObservationIgnored private let dampingRatio: CGFloat = 0.7 // overshoot reduction ratio
    @ObservationIgnored private let lookAhead: CGFloat = 0.25 // time to wait before locking on
    @ObservationIgnored private let maxSpeed: CGFloat = 3000 // max velocity can travel
    @ObservationIgnored private let restitution: CGFloat = 0.2 // wall bounciness

    private enum Phase { case idle, flying }

    @ObservationIgnored private var phase: Phase = .idle
    @ObservationIgnored private var velocity = CGVector.zero
    @ObservationIgnored private var target: CGPoint = .zero
    @ObservationIgnored private var dragStart: CGPoint?
    @ObservationIgnored private var bounds: CGRect = .zero
    @ObservationIgnored private var anchors: [CGPoint] = []
    @ObservationIgnored private var placed = false
    @ObservationIgnored private let driver = FrameDriver()

    private var damping: CGFloat { 2 * dampingRatio * stiffness.squareRoot() }

    init() {
        driver.onFrame = { [weak self] dt in self?.step(dt) }
    }

    func configure(size: CGSize, orbSize: CGFloat, margin: CGFloat) {
        let minX = margin, minY = margin
        let maxX = max(size.width - orbSize - margin, minX)
        let maxY = max(size.height - orbSize - margin, minY)
        bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        let xs = [minX, (minX + maxX) / 2, maxX]
        let ys = [minY, (minY + maxY) / 2, maxY]
        anchors = xs.flatMap { x in ys.map { y in CGPoint(x: x, y: y) } }
            .filter { !($0.x == xs[1] && $0.y == ys[1]) }

        if !placed {
            position = CGPoint(x: minX, y: maxY)
            placed = true
        } else if phase == .idle && dragStart == nil {
            position = nearestAnchor(to: position)
        } else {
            position = clamp(position)
        }
    }

    func place(_ p: CGPoint) {
        halt()
        position = clamp(p)
    }


    func drag(translation: CGSize) {
        if dragStart == nil {
            halt()
            dragStart = position
        }
        guard let start = dragStart else { return }
        position = clamp(CGPoint(x: start.x + translation.width, y: start.y + translation.height))
    }

    func release(velocity: CGVector) {
        dragStart = nil

        // Limit the throw speed
        let s = hypot(velocity.dx, velocity.dy)
        let scale = s > maxSpeed ? maxSpeed / s : 1
        self.velocity = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)

        // Pick the magnet the throw is heading toward, right now
        let aimed = CGPoint(x: position.x + self.velocity.dx * lookAhead,
                            y: position.y + self.velocity.dy * lookAhead)
        target = nearestAnchor(to: aimed)

        phase = .flying
        driver.start()
    }

    private func halt() {
        phase = .idle
        velocity = .zero
        driver.stop()
    }

    private func step(_ dt: CGFloat) {
        guard phase == .flying else { driver.stop(); return }

        // magnet pull and damping over original movement vector
        let ax = stiffness * (target.x - position.x) - damping * velocity.dx
        let ay = stiffness * (target.y - position.y) - damping * velocity.dy
        velocity = CGVector(dx: velocity.dx + ax * dt, dy: velocity.dy + ay * dt)
        move(dt)

        let gap = hypot(target.x - position.x, target.y - position.y)
        if gap < 0.5 && speed < 8 {
            position = target
            velocity = .zero
            phase = .idle
            dockCount += 1
            driver.stop()
        }
    }

    private var speed: CGFloat { hypot(velocity.dx, velocity.dy) }

    private func move(_ dt: CGFloat) {
        var p = CGPoint(x: position.x + velocity.dx * dt, y: position.y + velocity.dy * dt)
        if p.x < bounds.minX { p.x = bounds.minX; velocity.dx = abs(velocity.dx) * restitution }
        if p.x > bounds.maxX { p.x = bounds.maxX; velocity.dx = -abs(velocity.dx) * restitution }
        if p.y < bounds.minY { p.y = bounds.minY; velocity.dy = abs(velocity.dy) * restitution }
        if p.y > bounds.maxY { p.y = bounds.maxY; velocity.dy = -abs(velocity.dy) * restitution }
        position = p
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX),
                y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    private func nearestAnchor(to p: CGPoint) -> CGPoint {
        anchors.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) } ?? p
    }
}

@MainActor
private final class FrameDriver {
    var onFrame: ((CGFloat) -> Void)?
    private var timer: Timer?
    private var last: TimeInterval = 0

    func start() {
        guard timer == nil else { return }
        last = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // keeps running while the mouse is tracking
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - last, 1.0 / 30)
        last = now
        onFrame?(CGFloat(dt))
    }
}
