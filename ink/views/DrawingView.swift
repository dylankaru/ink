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
    var tool: Tool = .pen
    var colour: Color = .black
    var width: CGFloat = 8
}

struct LaserStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint] // world coordinates
    var colour: Color
    var width: CGFloat
    var endedAt: Date? = nil
}

struct DrawingView: View {
    @AppStorage("penOnly") private var penOnly = true
    @AppStorage("scribbleErase") private var scribbleErase = true

    @State private var strokes: [Stroke] = []
    @State private var currentStroke: Stroke? = nil
    @State private var undoStack: [[Stroke]] = []
    @State private var redoStack: [[Stroke]] = []
    @State private var eraseSnapshot: [Stroke]? = nil
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var tools = ToolState()

    @State private var laserStrokes: [LaserStroke] = []
    @State private var activeLaserID: UUID? = nil

    private let laserHold: TimeInterval = 2.0   // seconds visible after you lift
    private let laserFade: TimeInterval = 0.8   // fade-out duration

    private var isDrawing: Bool {
        currentStroke != nil || eraseSnapshot != nil || activeLaserID != nil
    }

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

    private func drawMarker(_ stroke: Stroke, in context: GraphicsContext) {
        guard let first = stroke.points.first else { return }
        var path = Path()
        path.move(to: first.location)
        if stroke.points.count == 1 {
            path.addLine(to: first.location)
        } else {
            for point in stroke.points.dropFirst() { path.addLine(to: point.location) }
        }

        var layer = context
        layer.blendMode = .multiply
        layer.stroke(
            path,
            with: .color(stroke.colour.opacity(0.4)),
            style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawPencil(_ stroke: Stroke, in context: GraphicsContext) {
        var light = Path()
        var dark = Path()

        for (a, b) in zip(stroke.points, stroke.points.dropFirst()) {
            let pressure = (a.pressure + b.pressure) / 2
            let w = stroke.width * (0.2 + 0.8 * pressure)
            let dx = b.location.x - a.location.x
            let dy = b.location.y - a.location.y
            let len = hypot(dx, dy)
            let nx = len > 0 ? -dy / len : 0
            let ny = len > 0 ? dx / len : 0
            let count = min(Int(len * w * 0.9) + 1, 40)

            let seedX = UInt64(bitPattern: Int64((a.location.x * 64).rounded()))
            let seedY = UInt64(bitPattern: Int64((a.location.y * 64).rounded()))
            var rng = SeededGenerator(seed: seedX &* 31 &+ seedY)

            for _ in 0..<count {
                let t = rng.unit()
                let off = (rng.unit() - 0.5) * w
                let r = (0.35 + 0.45 * rng.unit()) * (1 + w * 0.08)
                let cx = a.location.x + dx * t + nx * off
                let cy = a.location.y + dy * t + ny * off
                let dot = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                if rng.unit() < 0.35 + 0.4 * pressure {
                    dark.addPath(dot)
                } else {
                    light.addPath(dot)
                }
            }
        }

        context.fill(light, with: .color(stroke.colour.opacity(0.35)))
        context.fill(dark, with: .color(stroke.colour.opacity(0.8)))
    }

    private func deleteStrokes(coveredBy scribble: Stroke) -> Bool {
        let box = Scribble.bounds(scribble.points.map(\.location))
            .insetBy(dx: -12 / zoom, dy: -12 / zoom)

        let remaining = strokes.filter { s in
            guard !s.points.isEmpty else { return true }
            let inside = s.points.filter { box.contains($0.location) }.count
            return Double(inside) / Double(s.points.count) < 0.6
        }
        guard remaining.count != strokes.count else { return false }

        commit(strokes)
        strokes = remaining
        return true
    }

    // MARK: - Laser

    private func laserAlpha(_ s: LaserStroke, at date: Date) -> Double {
        guard let ended = s.endedAt else { return 1 }
        let t = date.timeIntervalSince(ended) - laserHold
        return t <= 0 ? 1 : max(0, 1 - t / laserFade)
    }

    private func drawLaser(_ s: LaserStroke, alpha: Double, in context: GraphicsContext) {
        guard let first = s.points.first else { return }
        var ctx = context

        var path = Path()
        if s.points.count == 1 {
            path.move(to: first)
            path.addLine(to: first)          // round cap makes a dot
        } else {
            path.move(to: first)
            for i in 1..<s.points.count {
                let prev = s.points[i - 1], cur = s.points[i]
                path.addQuadCurve(to: CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2),
                                  control: prev)
            }
            if let last = s.points.last { path.addLine(to: last) }
        }

        func style(_ w: CGFloat) -> StrokeStyle {
            StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        }
        ctx.stroke(path, with: .color(s.colour.opacity(0.25 * alpha)), style: style(s.width * 2.6)) // glow
        ctx.stroke(path, with: .color(s.colour.opacity(alpha)),        style: style(s.width))       // body
        ctx.stroke(path, with: .color(.white.opacity(0.7 * alpha)),    style: style(max(s.width * 0.3, 1))) // core
    }

    private func startLaser(at screenPoint: CGPoint) {
        let s = LaserStroke(points: [toWorld(screenPoint)],
                            colour: tools.current.colour,
                            width: tools.current.width)
        activeLaserID = s.id
        laserStrokes.append(s)
    }

    private func extendLaser(to screenPoint: CGPoint) {
        guard let id = activeLaserID,
              let i = laserStrokes.firstIndex(where: { $0.id == id }) else { return }
        laserStrokes[i].points.append(toWorld(screenPoint))
    }

    private func endLaser() {
        guard let id = activeLaserID else { return }
        activeLaserID = nil
        if let i = laserStrokes.firstIndex(where: { $0.id == id }) {
            laserStrokes[i].endedAt = .now
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(laserHold + laserFade + 0.1))
            laserStrokes.removeAll { $0.id == id }
        }
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.animation(paused: laserStrokes.isEmpty)) { timeline in
            Canvas { context, size in
                context.translateBy(x: offset.width, y: offset.height)
                context.scaleBy(x: zoom, y: zoom)

                for stroke in strokes + [currentStroke].compactMap({ $0 }) {
                    switch stroke.tool {
                    case .highlighter:
                        drawMarker(stroke, in: context)
                    case .pencil:
                        drawPencil(stroke, in: context)
                    default:
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

                // Laser strokes sit on top of everything
                for laser in laserStrokes {
                    let alpha = laserAlpha(laser, at: timeline.date)
                    if alpha > 0 { drawLaser(laser, alpha: alpha, in: context) }
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
                    if tools.selected == .laser {
                        startLaser(at: p)
                    } else if tools.selected == .eraser {
                        eraseSnapshot = strokes
                        erase(at: p)
                    } else {
                        currentStroke = Stroke(tool: tools.selected, colour: tools.current.colour, width: tools.current.width)
                        currentStroke?.points.append(StrokePoint(location: toWorld(p), pressure: pressure))
                    }
                },
                onPenMove: { p, pressure in
                    if tools.selected == .laser {
                        extendLaser(to: p)
                    } else if tools.selected == .eraser {
                        erase(at: p)
                    } else {
                        currentStroke?.points.append(
                            StrokePoint(location: toWorld(p), pressure: pressure))
                    }
                },
                onPenUp: {
                    if activeLaserID != nil {
                        endLaser()
                        return
                    }
                    if let snapshot = eraseSnapshot {
                        if snapshot.count != strokes.count || !snapshot.elementsEqualCount(strokes) {
                            commit(snapshot)
                        }
                        eraseSnapshot = nil
                    } else if let finished = currentStroke {
                        let screenPoints = finished.points.map {
                            CGPoint(x: $0.location.x * zoom, y: $0.location.y * zoom)
                        }
                        let canScribble = tools.selected == .pen || tools.selected == .pencil
                        if scribbleErase, canScribble,
                           Scribble.isScribble(screenPoints),
                           deleteStrokes(coveredBy: finished) {
                        } else {
                            commit(strokes)
                            strokes.append(finished)
                        }
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
                scribbleErase: $scribbleErase,
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

private struct SeededGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> CGFloat {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}

private extension Array where Element == Stroke {
    func elementsEqualCount(_ other: [Stroke]) -> Bool {
        reduce(0) { $0 + $1.points.count } == other.reduce(0) { $0 + $1.points.count }
    }
}

#Preview { DrawingView() }
