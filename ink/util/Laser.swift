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
    var hold: TimeInterval = 1.5
    var fade: TimeInterval = 0.6
    
    @State private var strokes: [LaserStroke] = []
    @State private var activeID: UUID?
    
    var body: some View {
        ZStack {
            // so that strokes redraw as their opacity changes
            TimelineView(.animation(paused: strokes.isEmpty)) { timeline in
                Canvas { ctx, _ in
                    for stroke in strokes {
                        let alpha = opacity(for: stroke, at: timeline.date)
                        guard alpha > 0 else { continue }
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
                            if let id = activeID,
                               let i = strokes.firstIndex(where: { $0.id == id }) {
                                strokes[i].points.append(value.location)
                            } else {
                                let s = LaserStroke(points: [value.location],
                                                    colour: colour, width: width)
                                activeID = s.id
                                strokes.append(s)
                                onActiveChange(true)
                            }
                        }
                        .onEnded { _ in
                            guard let id = activeID else { return }
                            activeID = nil
                            onActiveChange(false)
                            
                            if let i = strokes.firstIndex(where: { $0.id == id }) {
                                // Start the hold and fade timer
                                strokes[i].endedAt = .now
                            }
                            
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(hold + fade + 0.1))
                                strokes.removeAll { $0.id == id }
                            }
                        }
                )
        }
    }
    
    private func opacity(for stroke: LaserStroke, at date: Date) -> Double {
        guard let ended = stroke.endedAt else { return 1 }
        
        // Keep the stroke visible before fading it out
        let t = date.timeIntervalSince(ended) - hold
        return t <= 0 ? 1 : max(0, 1 - t / fade)
    }
    
    private func draw(_ stroke: LaserStroke, alpha: Double, in ctx: inout GraphicsContext) {
        var path = Path()
        
        if stroke.points.count == 1, let p = stroke.points.first {
            let r = stroke.width / 2
            path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: stroke.width, height: stroke.width))
            ctx.fill(path, with: .color(stroke.colour.opacity(alpha)))
            return
        }
        
        path.move(to: stroke.points[0])
        for i in 1..<stroke.points.count {
            let prev = stroke.points[i - 1]
            let cur = stroke.points[i]
            path.addQuadCurve(to: CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2),
                              control: prev)
        }
        if let last = stroke.points.last { path.addLine(to: last) }
        
        let style = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        
        // layered strokes create the glow effect
        ctx.stroke(path, with: .color(stroke.colour.opacity(0.25 * alpha)), style: style(stroke.width * 2.6))
        ctx.stroke(path, with: .color(stroke.colour.opacity(alpha)),        style: style(stroke.width))
        ctx.stroke(path, with: .color(.white.opacity(0.7 * alpha)),         style: style(max(stroke.width * 0.3, 1)))
    }
}
