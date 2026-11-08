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
    @AppStorage("penOnly") private var penOnly = true

    @State private var strokes: [Stroke] = []
    @State private var currentStroke: Stroke? = nil
    @State private var undoStack: [[Stroke]] = []
    @State private var redoStack: [[Stroke]] = []
    @State private var eraseSnapshot: [Stroke]? = nil
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var tools = ToolState()

    private var isDrawing: Bool { currentStroke != nil || eraseSnapshot != nil }

    private func toWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.width) / zoom,
                y: (p.y - offset.height) / zoom)
    }

    private func applyZoom(_ factor: CGFloat, around anchor: CGPoint) {
        let newZoom = min(max(zoom * factor, 0.1), 10)
        let ratio = newZoom / zoom
        offset = CGSize(width: anchor.x - (anchor.x - offset.width) * ratio,
                        height: anchor.y - (anchor.y - offset.height) * ratio)
        zoom = newZoom
    }

    private func commit(_ snapshot: [Stroke]) {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }

    private func clear() {
        guard !strokes.isEmpty else { return }
        commit(strokes)
        strokes = []
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func erase(at screenPoint: CGPoint) {
        let p = toWorld(screenPoint)
        let radius = tools.current.width / 2 / zoom
        var result: [Stroke] = []
        var changed = false

        for stroke in strokes {
            let reach = radius + stroke.width / 2
            let pts = stroke.points

            if pts.count < 2 {
                if let only = pts.first,
                   hypot(only.location.x - p.x, only.location.y - p.y) <= reach {
                    changed = true
                } else {
                    result.append(stroke)
                }
                continue
            }

            var pieces: [Stroke] = []
            var run: [StrokePoint] = []
            var touched = false

            func flush() {
                if run.count > 1 {
                    var piece = stroke
                    piece.points = run
                    pieces.append(piece)
                }
                run = []
            }

            for i in 0..<(pts.count - 1) {
                let a = pts[i], b = pts[i + 1]
                if distance(from: p, toSegment: a.location, b.location) <= reach {
                    touched = true
                    flush()
                } else {
                    if run.isEmpty { run.append(a) }
                    run.append(b)
                }
            }
            flush()

            if touched {
                changed = true
                result.append(contentsOf: pieces)
            } else {
                result.append(stroke)
            }
        }

        if changed { strokes = result }
    }

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: offset.width, y: offset.height)
            context.scaleBy(x: zoom, y: zoom)

            for stroke in strokes + [currentStroke].compactMap({ $0 }) {
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
                    if tools.isExpanded {
                        withAnimation(.smooth(duration: 0.35)) { tools.collapse() }
                    }
                    if tools.selected == .eraser {
                        eraseSnapshot = strokes
                        erase(at: p)
                    } else {
                        currentStroke = Stroke(colour: tools.current.colour, width: tools.current.width)
                        currentStroke?.points.append(StrokePoint(location: toWorld(p), pressure: pressure))
                    }
                },
                onPenMove: { p, pressure in
                    if tools.selected == .eraser {
                        erase(at: p)
                    } else {
                        currentStroke?.points.append(
                            StrokePoint(location: toWorld(p), pressure: pressure))
                    }
                },
                onPenUp: {
                    if let snapshot = eraseSnapshot {
                        if snapshot.count != strokes.count || !snapshot.elementsEqualCount(strokes) {
                            commit(snapshot)
                        }
                        eraseSnapshot = nil
                    } else if let finished = currentStroke {
                        commit(strokes)
                        strokes.append(finished)
                    }
                    currentStroke = nil
                },
                onPan: { d in
                    offset.width += d.width
                    offset.height += d.height
                },
                onZoom: { factor, anchor in applyZoom(factor, around: anchor) },
                penOnly: penOnly
            )
        }
        .overlay {
            ToolPalette(
                state: tools,
                penOnly: $penOnly,
                isDrawing: isDrawing,
                canUndo: !undoStack.isEmpty,
                canRedo: !redoStack.isEmpty,
                onUndo: undo,
                onRedo: redo,
                onClear: clear
            )
        }
        .background {
            Group {
                Button("Undo", action: undo)
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo", action: redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
}

private extension Array where Element == Stroke {
    func elementsEqualCount(_ other: [Stroke]) -> Bool {
        reduce(0) { $0 + $1.points.count } == other.reduce(0) { $0 + $1.points.count }
    }
}

#Preview { DrawingView() }
