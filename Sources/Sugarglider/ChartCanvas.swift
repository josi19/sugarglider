import SwiftUI
import AppKit

/// A small line chart of recent glucose readings, drawn with SwiftUI `Canvas`.
/// It paints on a transparent background so the menu's translucent material
/// shows through. Hover anywhere to read the exact value and time.
///
/// The `Canvas` content closure draws in a *flipped* sub-context (y growing
/// upward, the conventional chart coordinate space); text is drawn through
/// the unflipped top-level context so glyphs aren't mirrored, with
/// y-coordinates converted via `screenY(_:)`. `ChartMath` holds the pure,
/// framework-agnostic pieces (segment splitting, Catmull-Rom smoothing,
/// gridline stepping, zone coloring, hover hit-testing).
struct ChartCanvas: View {
    var readings: [Reading]
    var rangeHours: Int
    var settings: AppSettings

    /// Gaps longer than this break the line rather than drawing across a dropout.
    private let gapThreshold: TimeInterval = 15 * 60

    @State private var hoverIndex: Int?

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                updateHover(at: location, size: lastSize)
            case .ended:
                hoverIndex = nil
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size, initial: true) { _, new in lastSize = new }
        })
    }

    // `.onContinuousHover` doesn't hand us the view's size, so track it via a
    // zero-cost background GeometryReader.
    @State private var lastSize: CGSize = .zero

    // MARK: - Geometry (shared between draw and hover)

    private struct Layout {
        var visible: [Reading]
        var plot: CGRect       // in flipped chart space: minY = bottom, maxY = top
        var start: Date
        var end: Date
        var lo: Double
        var hi: Double
    }

    private func layout(size: CGSize) -> Layout? {
        let leftInset: CGFloat = 0.5, rightInset: CGFloat = 0.5
        let topInset: CGFloat = 10, bottomInset: CGFloat = 16
        let plot = CGRect(
            x: leftInset, y: bottomInset,
            width: size.width - leftInset - rightInset,
            height: size.height - topInset - bottomInset
        )

        let now = Date()
        let start = now.addingTimeInterval(-Double(rangeHours) * 3600)
        let visible = readings.filter { $0.date >= start }
        guard visible.count >= 2 else { return nil }

        let units = settings.units
        let mgdl = units == .mgdl
        let targetLow = units.display(settings.targetLow), targetHigh = units.display(settings.targetHigh)

        let pad = mgdl ? 10.0 : 0.5
        let clampLow = mgdl ? 40.0 : 2.0, clampHigh = mgdl ? 500.0 : 28.0
        let minSpan = mgdl ? 40.0 : 2.0
        let values = visible.map { units.value(fromMgdl: $0.sgv) }
        var lo = min(values.min() ?? targetLow, targetLow) - pad
        var hi = max(values.max() ?? targetHigh, targetHigh) + pad
        lo = max(clampLow, lo.rounded(.down))
        hi = min(clampHigh, hi.rounded(.up))
        if hi - lo < minSpan { hi = lo + minSpan }

        return Layout(visible: visible, plot: plot, start: start, end: now, lo: lo, hi: hi)
    }

    // MARK: - Draw

    private func draw(context ctx0: GraphicsContext, size: CGSize) {
        guard let l = layout(size: size) else {
            ctx0.draw(Text("No data for this range").font(.system(size: 11)).foregroundStyle(.secondary),
                      at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }
        let plot = l.plot

        // Flipped drawing context: y grows upward, so the geometry math below
        // reads like a conventional bottom-up chart.
        var chart = ctx0
        chart.translateBy(x: 0, y: size.height)
        chart.scaleBy(x: 1, y: -1)
        func screenY(_ chartY: CGFloat) -> CGFloat { size.height - chartY }

        let units = settings.units
        let targetLow = units.display(settings.targetLow), targetHigh = units.display(settings.targetHigh)
        func x(_ d: Date) -> CGFloat {
            plot.minX + CGFloat(d.timeIntervalSince(l.start) / l.end.timeIntervalSince(l.start)) * plot.width
        }
        func y(_ v: Double) -> CGFloat {
            plot.minY + CGFloat((v - l.lo) / (l.hi - l.lo)) * plot.height
        }
        func bandY(_ v: Double) -> CGFloat { min(max(y(v), plot.minY), plot.maxY) }

        let clipPath = Path(roundedRect: plot, cornerRadius: 10)

        // Optional solid background behind the plot; when off, the menu's
        // glass material shows through.
        if settings.chartBackgroundEnabled {
            chart.fill(clipPath, with: .color(settings.chartBackgroundColor))
        }

        // Faint rounded container so the plot reads as a distinct surface
        // (drawn before the clip, so the stroke itself isn't clipped).
        chart.stroke(clipPath, with: .color(Color(nsColor: .separatorColor).opacity(0.4)), lineWidth: 1)

        var inner = chart
        inner.clip(to: clipPath)

        // Horizontal gridlines with value labels.
        let step = ChartMath.niceStep(l.hi - l.lo)
        var level = (l.lo / step).rounded(.up) * step
        while level <= l.hi {
            let gy = y(level)
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: gy))
            grid.addLine(to: CGPoint(x: plot.maxX, y: gy))
            inner.stroke(grid, with: .color(Color(nsColor: .separatorColor).opacity(0.35)), lineWidth: 0.5)

            let text = Text(String(format: "%g", level)).font(.system(size: 9)).foregroundStyle(.tertiary)
            let ly = min(max(gy + 2, plot.minY + 1), plot.maxY - 11)
            ctx0.draw(text, at: CGPoint(x: plot.minX + 5, y: screenY(ly)), anchor: .bottomLeading)
            level += step
        }

        // Optimal-range band with dashed bounds.
        let yLow = y(targetLow), yHigh = y(targetHigh)
        let bandBottom = max(min(yLow, yHigh), plot.minY), bandTop = min(max(yLow, yHigh), plot.maxY)
        if bandTop > bandBottom {
            inner.fill(Path(CGRect(x: plot.minX, y: bandBottom, width: plot.width, height: bandTop - bandBottom)),
                       with: .color(settings.bandColor))
            let boundColor = settings.bandColor.opacity(0.35)
            for gy in [bandBottom, bandTop] {
                var d = Path()
                d.move(to: CGPoint(x: plot.minX, y: gy))
                d.addLine(to: CGPoint(x: plot.maxX, y: gy))
                inner.stroke(d, with: .color(boundColor), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }

        // The line, split across dropouts and smoothed, with a gradient area
        // fill. Zones top→bottom (chart space): extreme-high, above, in-range,
        // below, extreme-low.
        let zones = ChartMath.Zones(
            extremeLow: settings.extremeLow, targetLow: settings.targetLow,
            targetHigh: settings.targetHigh, extremeHigh: settings.extremeHigh,
            extremeLowColor: settings.extremeLowColor, belowColor: settings.belowColor,
            inRangeColor: settings.inRangeColor, aboveColor: settings.aboveColor,
            extremeHighColor: settings.extremeHighColor
        )
        let exLowY = bandY(units.display(settings.extremeLow))
        let lowY = bandY(targetLow)
        let highY = bandY(targetHigh)
        let exHighY = bandY(units.display(settings.extremeHigh))
        let bands: [(CGFloat, CGFloat, Color)] = [
            (plot.minY, exLowY, zones.extremeLowColor),
            (exLowY, lowY, zones.belowColor),
            (lowY, highY, zones.inRangeColor),
            (highY, exHighY, zones.aboveColor),
            (exHighY, plot.maxY, zones.extremeHighColor),
        ]

        for segment in ChartMath.segments(of: l.visible, gapThreshold: gapThreshold) {
            let pts = segment.map { CGPoint(x: x($0.date), y: y(units.value(fromMgdl: $0.sgv))) }
            guard pts.count >= 2 else {
                if let p = pts.first, let r = segment.first {
                    dot(&inner, at: p, radius: 2, color: ChartMath.color(for: r.sgv, zones: zones))
                }
                continue
            }
            let path = ChartMath.smooth(pts)

            var area = path
            area.addLine(to: CGPoint(x: pts.last!.x, y: plot.minY))
            area.addLine(to: CGPoint(x: pts.first!.x, y: plot.minY))
            area.closeSubpath()
            var areaCtx = inner
            areaCtx.clip(to: area)
            areaCtx.fill(Path(plot), with: .linearGradient(
                Gradient(colors: [zones.inRangeColor.opacity(0.14), zones.inRangeColor.opacity(0)]),
                startPoint: CGPoint(x: plot.midX, y: plot.maxY), endPoint: CGPoint(x: plot.midX, y: plot.minY)))

            if settings.blendLineColors {
                strokeBlended(&inner, path: path, bands: bands, plot: plot)
            } else {
                for (minY, maxY, color) in bands where maxY - minY > 0.5 {
                    var bandCtx = inner
                    bandCtx.clip(to: Path(CGRect(x: plot.minX, y: minY, width: plot.width, height: maxY - minY)))
                    bandCtx.stroke(path, with: .color(color.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }

        // Latest reading: halo + solid dot, colored by its range zone (drawn
        // unclipped, so the halo can bleed past the rounded corners slightly).
        if let last = l.visible.last {
            let p = CGPoint(x: x(last.date), y: y(units.value(fromMgdl: last.sgv)))
            let c = ChartMath.color(for: last.sgv, zones: zones)
            dot(&chart, at: p, radius: 7, color: c.opacity(0.18))
            dot(&chart, at: p, radius: 4, color: c)
        }

        // Time axis (start / latest).
        let startText = Text(Self.timeFmt.string(from: l.start)).font(.system(size: 9)).foregroundStyle(.tertiary)
        ctx0.draw(startText, at: CGPoint(x: plot.minX, y: screenY(plot.minY) - 2), anchor: .bottomLeading)
        let endStr = Self.timeFmt.string(from: l.visible.last!.date)
        let endText = Text(endStr).font(.system(size: 9)).foregroundStyle(.tertiary)
        ctx0.draw(endText, at: CGPoint(x: plot.maxX, y: screenY(plot.minY) - 2), anchor: .bottomTrailing)

        drawHover(ctx0: ctx0, chart: &chart, x: x, y: y, plot: plot, layout: l, zones: zones, screenY: screenY)
    }

    /// Stroke `path` with a vertical gradient that blends the zone colors into
    /// one another (bottom → top, matching the value axis), so the line's
    /// color shifts smoothly across thresholds instead of switching abruptly.
    private func strokeBlended(_ ctx: inout GraphicsContext, path: Path, bands: [(CGFloat, CGFloat, Color)], plot: CGRect) {
        var stops: [Gradient.Stop] = []
        for (minY, maxY, color) in bands where maxY - minY > 0.5 {
            let center = ((minY + maxY) / 2 - plot.minY) / plot.height
            stops.append(.init(color: color.opacity(0.9), location: min(max(center, 0), 1)))
        }
        guard !stops.isEmpty else { return }
        ctx.stroke(path, with: .linearGradient(
            Gradient(stops: stops.sorted { $0.location < $1.location }),
            startPoint: CGPoint(x: plot.midX, y: plot.minY), endPoint: CGPoint(x: plot.midX, y: plot.maxY)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    /// Crosshair + value/time pill at the hovered reading.
    private func drawHover(ctx0: GraphicsContext, chart: inout GraphicsContext,
                            x: (Date) -> CGFloat, y: (Double) -> CGFloat, plot: CGRect,
                            layout l: Layout, zones: ChartMath.Zones, screenY: (CGFloat) -> CGFloat) {
        guard let i = hoverIndex, l.visible.indices.contains(i) else { return }
        let r = l.visible[i]
        let units = settings.units
        let px = x(r.date), py = y(units.value(fromMgdl: r.sgv))

        var vline = Path()
        vline.move(to: CGPoint(x: px, y: plot.minY))
        vline.addLine(to: CGPoint(x: px, y: plot.maxY))
        chart.stroke(vline, with: .color(Color(nsColor: .labelColor).opacity(0.25)), lineWidth: 1)

        dot(&chart, at: CGPoint(x: px, y: py), radius: 4, color: ChartMath.color(for: r.sgv, zones: zones))

        let label = "\(r.text(in: units)) · \(Self.timeFmt.string(from: r.date))"
        // Resolve once so measurement and drawing share the same text layout.
        let resolved = ctx0.resolve(Text(label).font(.system(size: 10)).foregroundStyle(Color(nsColor: .labelColor)))
        let size = resolved.measure(in: plot.size)
        let pad: CGFloat = 5
        var bx = px - (size.width + pad * 2) / 2
        bx = max(plot.minX, min(bx, plot.maxX - size.width - pad * 2))
        let box = CGRect(x: bx, y: plot.maxY - size.height - pad * 2 - 2,
                         width: size.width + pad * 2, height: size.height + pad)
        let bg = Path(roundedRect: box, cornerRadius: 5)
        chart.fill(bg, with: .color(Color(nsColor: .controlBackgroundColor).opacity(0.95)))
        chart.stroke(bg, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)
        ctx0.draw(resolved, at: CGPoint(x: box.minX + pad, y: screenY(box.minY + pad / 2)), anchor: .bottomLeading)
    }

    private func dot(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    // MARK: - Hover tracking

    private func updateHover(at location: CGPoint, size: CGSize) {
        guard let l = layout(size: size) else { return }
        func x(_ d: Date) -> CGFloat {
            l.plot.minX + CGFloat(d.timeIntervalSince(l.start) / l.end.timeIntervalSince(l.start)) * l.plot.width
        }
        hoverIndex = ChartMath.nearestIndex(to: location.x, x: x, in: l.visible, maxDistance: 24)
    }
}
