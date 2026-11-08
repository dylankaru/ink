//
//  ScribbleGesture.swift
//  ink
//
//  Created by Dylan Karunanayake on 8/11/2026.
//

import CoreGraphics

enum Scribble {
    static func bounds(_ pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // Detection parametres
    private static let minSpacing: CGFloat = 6
    private static let minDiagonal: CGFloat = 24
    private static let reversalCosine: CGFloat = -0.3 // 107 deg
    private static let minReversals = 5
    private static let minLengthRatio: CGFloat = 3.5

    static func isScribble(_ raw: [CGPoint]) -> Bool {
        guard raw.count >= 12 else { return false }

        // resample to drop jitter and guarantee no zero-length segments
        var pts = [raw[0]]
        for p in raw.dropFirst() {
            let last = pts[pts.count - 1]
            if hypot(p.x - last.x, p.y - last.y) >= minSpacing { pts.append(p) }
        }
        guard pts.count >= 8 else { return false }

        var length: CGFloat = 0
        var reversals = 0
        var previous: CGVector?
        for (a, b) in zip(pts, pts.dropFirst()) {
            let v = CGVector(dx: b.x - a.x, dy: b.y - a.y)
            let len = hypot(v.dx, v.dy)
            length += len
            if let p = previous {
                // cosine near -1 means a U-turn and avoids calling acos() per segment
                let cosine = (p.dx * v.dx + p.dy * v.dy) / (hypot(p.dx, p.dy) * len)
                if cosine < reversalCosine { reversals += 1 }
            }
            previous = v
        }

        let box = bounds(pts)
        let diagonal = hypot(box.width, box.height)
        guard diagonal > minDiagonal else { return false }
        
        return reversals >= minReversals && length / diagonal >= minLengthRatio // need both
    }
}
