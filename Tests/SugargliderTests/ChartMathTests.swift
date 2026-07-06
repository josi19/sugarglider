import Testing
import SwiftUI
@testable import Sugarglider

/// Collect a `Path`'s elements — the SwiftUI equivalent of `NSBezierPath`'s
/// `elementCount`/`element(at:associatedPoints:)`, which `Path` doesn't expose.
private func elements(of path: Path) -> [Path.Element] {
    var result: [Path.Element] = []
    path.forEach { result.append($0) }
    return result
}

private func defaultZones() -> ChartMath.Zones {
    .init(extremeLow: 54, targetLow: 70, targetHigh: 180, extremeHigh: 250,
          extremeLowColor: .red, belowColor: .orange, inRangeColor: .green,
          aboveColor: .blue, extremeHighColor: .purple)
}

extension SugargliderTests {
    @Test func niceStepPicksRoundIntervals() {
        #expect(abs(ChartMath.niceStep(4) - 1) < 1e-9)
        #expect(abs(ChartMath.niceStep(8) - 2) < 1e-9)
        #expect(abs(ChartMath.niceStep(20) - 5) < 1e-9)
        #expect(abs(ChartMath.niceStep(40) - 10) < 1e-9)
        #expect(abs(ChartMath.niceStep(100) - 20) < 1e-9)
        #expect(abs(ChartMath.niceStep(2) - 0.5) < 1e-9)
    }

    @Test func segmentsSplitOnDropouts() {
        let base = Date()
        func asc(_ minutes: [Double]) -> [Reading] {   // oldest-first
            minutes.sorted(by: >).map { reading(100, minutesAgo: $0, from: base) }
        }
        #expect(ChartMath.segments(of: [], gapThreshold: 900).isEmpty)

        let single = ChartMath.segments(of: asc([0]), gapThreshold: 900)
        #expect(single.count == 1 && single[0].count == 1)

        let contiguous = ChartMath.segments(of: asc([10, 5, 0]), gapThreshold: 900)  // 5-min steps
        #expect(contiguous.count == 1 && contiguous[0].count == 3)

        // 45,40 then a 30-min gap then 10,5,0 → two runs of 2 and 3.
        let split = ChartMath.segments(of: asc([45, 40, 10, 5, 0]), gapThreshold: 900)
        #expect(split.map(\.count) == [2, 3])
    }

    @Test func colorForZone() {
        let zones = defaultZones()
        // Defaults: extremeLow 54, targetLow 70, targetHigh 180, extremeHigh 250.
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 50, zones: zones), zones.extremeLowColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 60, zones: zones), zones.belowColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 100, zones: zones), zones.inRangeColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 200, zones: zones), zones.aboveColor))
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 300, zones: zones), zones.extremeHighColor))
        // Boundaries (strict comparisons in color(for:)).
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 54, zones: zones), zones.belowColor))   // not < 54
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 70, zones: zones), zones.inRangeColor)) // not < 70
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 180, zones: zones), zones.inRangeColor)) // not > 180
        #expect(AppSettings.colorsMatch(ChartMath.color(for: 250, zones: zones), zones.aboveColor))  // not > 250
    }

    @Test func smoothElementCounts() {
        let p = { (x: CGFloat) in CGPoint(x: x, y: x) }
        #expect(elements(of: ChartMath.smooth([])).count == 0)
        #expect(elements(of: ChartMath.smooth([p(0)])).count == 1)             // moveTo
        #expect(elements(of: ChartMath.smooth([p(0), p(1)])).count == 2)       // moveTo + lineTo
        #expect(elements(of: ChartMath.smooth([p(0), p(1), p(2)])).count == 3) // moveTo + 2 curves
    }

    @Test func sampleReadingsSweepAllZones() {
        let end = Date()
        let readings = ChartMath.sampleReadings(
            extremeLow: 54, targetLow: 70, targetHigh: 180, extremeHigh: 250, endingAt: end)

        #expect(readings.count == 35)
        #expect(readings.last?.date == end)
        #expect(zip(readings, readings.dropFirst()).allSatisfy { $0.date < $1.date })
        // 5-min spacing → the whole span fits a 3-hour chart window.
        #expect(readings.first!.date >= end.addingTimeInterval(-3 * 3600))

        // The curve must visit every zone so each configurable color shows.
        let values = readings.map { Double($0.sgv) }
        #expect(values.contains { $0 < 54 })            // very low
        #expect(values.contains { (54..<70).contains($0) })   // below optimal
        #expect(values.contains { (70...180).contains($0) })  // in range
        #expect(values.contains { (180...250).contains($0) }) // above optimal
        #expect(values.contains { $0 > 250 })           // very high
        #expect(values.allSatisfy { (40...400).contains($0) })
    }

    @Test func nearestIndexFindsClosestByX() {
        let base = Date()
        // `reading(minutesAgo:)` is seconds-since-`base` × 60 in the past, so
        // negating it here places these at x = 0, 5, 10 (in the same units `x`
        // reports below, seconds — not minutes; keep the two in sync).
        let readings = [0.0, 300.0, 600.0].map { reading(100, minutesAgo: -$0 / 60, from: base) }
        func x(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(base)) }
        #expect(ChartMath.nearestIndex(to: 0, x: x, in: readings, maxDistance: 24) == 0)
        #expect(ChartMath.nearestIndex(to: 310, x: x, in: readings, maxDistance: 24) == 1)
        #expect(ChartMath.nearestIndex(to: 590, x: x, in: readings, maxDistance: 24) == 2)
        #expect(ChartMath.nearestIndex(to: 1000, x: x, in: readings, maxDistance: 24) == nil)  // too far
    }
}

// MARK: - Full render smoke tests (via ImageRenderer, no window needed)

extension SugargliderTests {
    private func renderedImage(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: 280, height: 160))
        renderer.scale = 1
        return renderer.cgImage
    }

    @Test func rendersEmptyStateWithoutCrash() {
        let s = Self.makeSettings()
        #expect(renderedImage(ChartCanvas(readings: [], rangeHours: 6, settings: s)) != nil)
    }

    @Test func rendersSinglePointAsNoData() {
        let s = Self.makeSettings()
        let chart = ChartCanvas(readings: [reading(100, minutesAgo: 0)], rangeHours: 6, settings: s)
        #expect(renderedImage(chart) != nil)
    }

    private func spanningReadings(from base: Date) -> [Reading] {
        // Values crossing every zone, within the default 6h window.
        let pts: [(Double, Int)] = [(300, 45), (240, 60), (180, 100),
                                    (120, 200), (60, 300), (30, 150), (10, 90), (0, 110)]
        return pts.map { reading($0.1, minutesAgo: $0.0, from: base) }.sorted { $0.date < $1.date }
    }

    @Test func rendersFullChartMmolDirectColors() {
        let s = Self.makeSettings()
        s.units = .mmol
        let chart = ChartCanvas(readings: spanningReadings(from: Date()), rangeHours: 6, settings: s)
        #expect(renderedImage(chart) != nil)
    }

    @Test func rendersFullChartMgdlBlendedWithBackground() {
        let s = Self.makeSettings()
        s.units = .mgdl
        s.blendLineColors = true
        s.chartBackgroundEnabled = true
        s.chartBackgroundColor = Color(red: 0.1, green: 0.1, blue: 0.12, opacity: 1)
        let chart = ChartCanvas(readings: spanningReadings(from: Date()), rangeHours: 6, settings: s)
        #expect(renderedImage(chart) != nil)   // exercises the blended-gradient stroke + background fill
    }

    @Test func rendersWithGapsAndIsolatedPoints() {
        let base = Date()
        let s = Self.makeSettings()
        // Isolated points at 300 and 0, a contiguous run at 100/95/90 → single-point
        // segments hit the dot branch.
        let readings = [300, 100, 95, 90, 0].sorted(by: >)
            .map { reading(120, minutesAgo: $0, from: base) }
            .sorted { $0.date < $1.date }
        let chart = ChartCanvas(readings: readings, rangeHours: 6, settings: s)
        #expect(renderedImage(chart) != nil)
    }
}
