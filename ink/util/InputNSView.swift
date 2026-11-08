//
//  InputNSView.swift
//  ink
//
//  Created by Dylan Karunanayake on 2/11/2026.
//

import SwiftUI

final class InputNSView: NSView {
    var onPenDown: ((CGPoint, CGFloat) -> Void)?
    var onPenMove: ((CGPoint, CGFloat) -> Void)?
    var onPenUp: (() -> Void)?
    var onPan: ((CGSize) -> Void)?
    var onZoom: ((CGFloat, CGPoint) -> Void)?

    var penOnly = false

    private enum DragKind { case none, draw, pan }
    private var dragKind: DragKind = .none
    private var lastPanPoint: CGPoint = .zero

    override var isFlipped: Bool { true }

    private func point(_ e: NSEvent) -> CGPoint {
        convert(e.locationInWindow, from: nil)
    }

    override func mouseDown(with e: NSEvent) {
        let isPen = e.subtype == .tabletPoint
        if isPen || !penOnly {
            dragKind = .draw
            onPenDown?(point(e), CGFloat(e.pressure))
        } else {
            // Trackpad or mouse while pen-only is on so drag to pan
            dragKind = .pan
            lastPanPoint = point(e)
        }
    }

    override func mouseDragged(with e: NSEvent) {
        switch dragKind {
        case .draw:
            onPenMove?(point(e), CGFloat(e.pressure))
        case .pan:
            let p = point(e)
            onPan?(CGSize(width: p.x - lastPanPoint.x, height: p.y - lastPanPoint.y))
            lastPanPoint = p
        case .none:
            break
        }
    }

    override func mouseUp(with e: NSEvent) {
        if dragKind == .draw { onPenUp?() }
        dragKind = .none
    }
    
    // when users can draw with pointer too
    override func rightMouseDown(with e: NSEvent) {
        guard dragKind == .none else { return }
        dragKind = .pan
        lastPanPoint = point(e)
    }

    override func rightMouseDragged(with e: NSEvent) {
        guard dragKind == .pan else { return }
        let p = point(e)
        onPan?(CGSize(width: p.x - lastPanPoint.x, height: p.y - lastPanPoint.y))
        lastPanPoint = p
    }

    override func rightMouseUp(with e: NSEvent) {
        if dragKind == .pan { dragKind = .none }
    }

    override func scrollWheel(with e: NSEvent) {
        if e.modifierFlags.contains(.command) || !e.hasPreciseScrollingDeltas {
            onZoom?(1 + e.scrollingDeltaY * 0.01, point(e))
        } else {
            onPan?(CGSize(width: e.scrollingDeltaX, height: e.scrollingDeltaY)) 
        }
    }

    override func magnify(with e: NSEvent) {
        onZoom?(1 + e.magnification, point(e)) // pinch
    }
}

struct InputCatcher: NSViewRepresentable {
    var onPenDown: (CGPoint, CGFloat) -> Void
    var onPenMove: (CGPoint, CGFloat) -> Void
    var onPenUp: () -> Void
    var onPan: (CGSize) -> Void
    var onZoom: (CGFloat, CGPoint) -> Void
    var penOnly: Bool

    func makeNSView(context: Context) -> InputNSView { InputNSView() }

    func updateNSView(_ v: InputNSView, context: Context) {
        v.onPenDown = onPenDown
        v.onPenMove = onPenMove
        v.onPenUp = onPenUp
        v.onPan = onPan
        v.onZoom = onZoom
        v.penOnly = penOnly
    }
}
