//
//  Laser.swift
//  ink
//
//  Created by Dylan Karunanayake on 12/11/2026.
//

import SwiftUI

struct LaserLayer: View {
    var colour: Color
    var width: CGFloat
    var onActiveChange: (Bool) -> Void = { _ in }

    // Lifetime tuning
    var hold: TimeInterval = 3.5
    var fade: TimeInterval = 0.6
    var recovery: TimeInterval = 1.0

    @State private var strokes: [LaserStroke] = []
    @State private var activeID: UUID?

    @State private var fadeStartedAt: Date?
    @State private var hiddenAt: Date?
    @State private var cleanupTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // so that strokes redraw as their opacity changes
            TimelineView(.animation(paused: strokes.isEmpty)) { timeline in
                Canvas { ctx, _ in
                    let alpha = opacity(at: timeline.date)

                    guard alpha > 0 else { return }

                    for stroke in strokes {
                        draw(stroke, alpha: alpha, in: &ctx)
                    }
                }
            }
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            keepAlive()

                            if let id = activeID,
                               let i = strokes.firstIndex(where: { $0.id == id }) {
                                strokes[i].points.append(value.location)
                            } else {
                                let stroke = LaserStroke(
                                    points: [value.location],
                                    colour: colour,
                                    width: width
                                )

                                activeID = stroke.id
                                strokes.append(stroke)
                                onActiveChange(true)
                            }
                        }
                        .onEnded { _ in
                            activeID = nil
                            onActiveChange(false)

                            // start inactivity countdown
                            keepAlive()
                        }
                )
        }
        .onDisappear {
            cleanupTask?.cancel()
        }
    }

    private func keepAlive() {
        cleanupTask?.cancel()
        cleanupTask = nil

        // bring fading or hidden strokes back
        fadeStartedAt = nil
        hiddenAt = nil

        cleanupTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(hold))
                guard !Task.isCancelled else { return }

                fadeStartedAt = .now

                try await Task.sleep(for: .seconds(fade))
                guard !Task.isCancelled else { return }

                hiddenAt = .now

                try await Task.sleep(for: .seconds(recovery))
                guard !Task.isCancelled else { return }

                //  discard old drawings
                strokes.removeAll()
                fadeStartedAt = nil
                hiddenAt = nil
                cleanupTask = nil

            } catch {
                // beans
            }
        }
    }

    private func opacity(at date: Date) -> Double {
        guard let started = fadeStartedAt else { return 1 }
        guard hiddenAt == nil else { return 0 }

        let elapsed = date.timeIntervalSince(started)
        return max(0, 1 - elapsed / fade)
    }

    private func draw(
        _ stroke: LaserStroke,
        alpha: Double,
        in ctx: inout GraphicsContext
    ) {
        var path = Path()

        if stroke.points.count == 1, let p = stroke.points.first {
            // render a dot for a single-point stroke
            let r = stroke.width / 2
            path.addEllipse(in: CGRect(
                x: p.x - r,
                y: p.y - r,
                width: stroke.width,
                height: stroke.width
            ))

            ctx.fill(path, with: .color(stroke.colour.opacity(alpha)))
            return
        }

        path.move(to: stroke.points[0])

        for i in 1..<stroke.points.count {
            let prev = stroke.points[i - 1]
            let cur = stroke.points[i]

            path.addQuadCurve(
                to: CGPoint(
                    x: (prev.x + cur.x) / 2,
                    y: (prev.y + cur.y) / 2
                ),
                control: prev
            )
        }

        if let last = stroke.points.last {
            path.addLine(to: last)
        }

        let style = { (w: CGFloat) in
            StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        }

        ctx.stroke(path, with: .color(stroke.colour.opacity(0.25 * alpha)),
                   style: style(stroke.width * 2.6))

        ctx.stroke(path, with: .color(stroke.colour.opacity(alpha)),
                   style: style(stroke.width))

        ctx.stroke(path, with: .color(.white.opacity(0.7 * alpha)),
                   style: style(max(stroke.width * 0.3, 1)))
    }
}
