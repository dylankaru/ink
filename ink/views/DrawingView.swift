//
//  DrawingView.swift
//  ink
//
//  Created by Dylan Karunanayake on 2/11/2026.
//

import SwiftUI

struct StrokePoint {
    var location: CGPoint
    var pressure: CGFloat
}

struct Stroke {
    var points: [StrokePoint] = []
    var colour: Color = .black
    var width: CGFloat = 8
}

struct DrawingView: View {
    @State private var strokes: [Stroke] = []
    @State private var currentStroke: Stroke? = nil
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero

    // screen = world * zoom + offset  →  world = (screen - offset) / zoom
    private func toWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.width) / zoom,
                y: (p.y - offset.height) / zoom)
    }

    // Keeps the world point under `anchor` fixed while zooming.
    private func applyZoom(_ factor: CGFloat, around anchor: CGPoint) {
        let newZoom = min(max(zoom * factor, 0.1), 10)
        let ratio = newZoom / zoom
        offset = CGSize(width: anchor.x - (anchor.x - offset.width) * ratio,
                        height: anchor.y - (anchor.y - offset.height) * ratio)
        zoom = newZoom
    }

    var body: some View {
        VStack(spacing: 0) {
            Button("Undo") { _ = strokes.popLast() }
                .disabled(strokes.isEmpty)
                .padding(8)

            Canvas { context, size in
                // Draw everything through the camera.
                context.translateBy(x: offset.width, y: offset.height)
                context.scaleBy(x: zoom, y: zoom)

                for stroke in strokes + [currentStroke].compactMap({ $0 }) {
                    // One small segment at a time, so each can have its own width.
                    for (a, b) in zip(stroke.points, stroke.points.dropFirst()) {
                        var segment = Path()
                        segment.move(to: a.location)
                        segment.addLine(to: b.location)

                        let pressure = (a.pressure + b.pressure) / 2
                        context.stroke(
                            segment,
                            with: .color(stroke.colour),
                            style: StrokeStyle(lineWidth: stroke.width * (0.2 + 0.8 * pressure),
                                               lineCap: .round)
                        )
                    }
                }
            }
            .background(Rectangle().fill(.white))
            .overlay {
                InputCatcher(
                    onPenDown: { p, pressure in
                        currentStroke = Stroke()
                        currentStroke?.points.append(
                            StrokePoint(location: toWorld(p), pressure: pressure))
                    },
                    onPenMove: { p, pressure in
                        currentStroke?.points.append(
                            StrokePoint(location: toWorld(p), pressure: pressure))
                    },
                    onPenUp: {
                        if let finished = currentStroke { strokes.append(finished) }
                        currentStroke = nil
                    },
                    onPan: { d in
                        offset.width += d.width
                        offset.height += d.height
                    },
                    onZoom: { factor, anchor in applyZoom(factor, around: anchor) }
                )
            }
        }
    }
}

#Preview { DrawingView() }
