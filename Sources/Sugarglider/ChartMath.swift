import SwiftUI

/// Framework-agnostic chart math, shared by `ChartCanvas`'s drawing and its
/// tests. Kept free of SwiftUI view state so it's trivially unit-testable.
enum ChartMath {
    /// The five range-zone thresholds and colors used to color the line and
    /// pick a reading's dot color.
    struct Zones {
        var extremeLow: Double
        var targetLow: Double
        var targetHigh: Double
        var extremeHigh: Double
        var extremeLowColor: Color
        var belowColor: Color
        var inRangeColor: Color
        var aboveColor: Color
        var extremeHighColor: Color
    }

    /// The color for a reading based on its range zone. Compared in mg/dL —
    /// the unit thresholds are stored in, independent of the display unit.
    static func color(for sgv: Int, zones: Zones) -> Color {
        let v = Double(sgv)
        if v < zones.extremeLow { return zones.extremeLowColor }
        if v < zones.targetLow { return zones.belowColor }
        if v > zones.extremeHigh { return zones.extremeHighColor }
        if v > zones.targetHigh { return zones.aboveColor }
        return zones.inRangeColor
    }

    /// Split readings into contiguous runs, breaking where a dropout exceeds `gap`.
    static func segments(of readings: [Reading], gapThreshold gap: TimeInterval) -> [[Reading]] {
        var result: [[Reading]] = []
        var current: [Reading] = []
        for r in readings {
            if let prev = current.last, r.date.timeIntervalSince(prev.date) > gap {
                result.append(current); current = []
            }
            current.append(r)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Catmull-Rom smoothing → a flowing bezier through the points.
    static func smooth(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count < 3 {
            pts.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// The index of the reading nearest `targetX` (by horizontal distance
    /// only), or nil if none is within `maxDistance`. Pure geometry — the
    /// hover hit-test, factored out so it's testable without a live view.
    static func nearestIndex(to targetX: CGFloat, x: (Date) -> CGFloat, in readings: [Reading], maxDistance: CGFloat) -> Int? {
        var best = 0, bestDist = CGFloat.greatestFiniteMagnitude
        for (i, r) in readings.enumerated() {
            let d = abs(x(r.date) - targetX)
            if d < bestDist { bestDist = d; best = i }
        }
        return bestDist < maxDistance ? best : nil
    }

    /// A "nice" gridline step (1/2/5 × 10ⁿ) giving roughly five lines across the
    /// span — works for both mmol/L and mg/dL ranges.
    static func niceStep(_ span: Double) -> Double {
        let rough = max(span / 4, 0.0001)
        let mag = pow(10, floor(log10(rough)))
        let norm = rough / mag
        let nice: Double = norm < 1.5 ? 1 : (norm < 3 ? 2 : (norm < 7 ? 5 : 10))
        return nice * mag
    }
}
