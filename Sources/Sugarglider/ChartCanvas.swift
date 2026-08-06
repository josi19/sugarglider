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
    /// The instant the window ends at. The live chart leaves this nil and
    /// anchors to the wall clock, which is what makes a stopped feed show up as
    /// a growing gap at the right edge. Settings' synthetic preview pins it to
    /// its own sample data's end instead: that data is generated when the view
    /// body runs, while `Canvas` redraws whenever it likes, so a wall-clock
    /// window slid the samples out of range as the app kept running — after
    /// `rangeHours` the preview showed "No data for this range" until some edit
    /// re-ran the body and regenerated it.
    var windowEnd: Date?

    @State private var hoverIndex: Int?
    /// `.onContinuousHover` doesn't hand us the view's size, so track it via a
    /// zero-cost background GeometryReader.
    @State private var lastSize: CGSize = .zero

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Used instead of `timeFmt` on wide windows — see `ChartMath.labelsNeedDay`.
    /// The pattern stays fixed 24h like `timeFmt` (the weekday abbreviation still
    /// localizes through the formatter's locale) so both variants read alike.
    private static let dayTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E HH:mm"
        return f
    }()

    /// Time label for `date` in a window spanning `span`.
    private static func timeLabel(_ date: Date, span: TimeInterval) -> String {
        (ChartMath.labelsNeedDay(span: span) ? dayTimeFmt : timeFmt).string(from: date)
    }

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

    // MARK: - Geometry (shared between draw and hover)

    /// Everything the drawing and the hover hit-test need to map readings to
    /// points. Both go through `x(_:)`/`y(_:)`, so the two can't disagree about
    /// where a reading sits.
    private struct Layout {
        var visible: [Reading]
        var plot: CGRect       // in flipped chart space: minY = bottom, maxY = top
        var size: CGSize       // the whole canvas, for converting back to screen space
        var start: Date
        var end: Date
        var lo: Double
        var hi: Double
        var units: AppSettings.Units

        /// Horizontal position of an instant in the window.
        func x(_ date: Date) -> CGFloat {
            plot.minX + CGFloat(date.timeIntervalSince(start) / end.timeIntervalSince(start)) * plot.width
        }

        /// Vertical position of a value *in display units* (chart space, y up).
        func y(_ value: Double) -> CGFloat {
            plot.minY + CGFloat((value - lo) / (hi - lo)) * plot.height
        }

        /// `y(_:)` for an mg/dL value, clamped into the plot — for the threshold
        /// lines and zone bands, which exist even when they fall off the axis.
        func bandY(mgdl: Double) -> CGFloat {
            min(max(y(units.display(mgdl)), plot.minY), plot.maxY)
        }

        func y(of reading: Reading) -> CGFloat { y(units.value(fromMgdl: reading.sgv)) }

        /// Chart-space y back to the unflipped context's coordinates, for text.
        func screenY(_ chartY: CGFloat) -> CGFloat { size.height - chartY }

        var span: TimeInterval { end.timeIntervalSince(start) }
    }

    private func layout(size: CGSize) -> Layout? {
        let leftInset: CGFloat = 0.5
        // The newest reading sits exactly at the plot's right edge, so its dot
        // and halo need room there or the `Canvas` frame clips them in half.
        // Capped so a big halo can't squeeze a narrow chart out of existence.
        let rightInset = min(max(0.5, settings.dotRadius, settings.dotHaloRadius), size.width / 4)
        let topInset: CGFloat = 10, bottomInset: CGFloat = 16
        let plot = CGRect(
            x: leftInset, y: bottomInset,
            width: size.width - leftInset - rightInset,
            height: size.height - topInset - bottomInset
        )

        let now = windowEnd ?? Date()
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

        return Layout(visible: visible, plot: plot, size: size,
                      start: start, end: now, lo: lo, hi: hi, units: units)
    }

    // MARK: - Draw

    private func draw(context ctx0: GraphicsContext, size: CGSize) {
        guard let l = layout(size: size) else {
            ctx0.draw(Text("No data for this range").font(.system(size: 11)).foregroundStyle(.secondary),
                      at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }

        // Flipped drawing context: y grows upward, so the geometry math in
        // `Layout` reads like a conventional bottom-up chart. `ctx0` stays
        // unflipped and is what all text is drawn through.
        var chart = ctx0
        chart.translateBy(x: 0, y: size.height)
        chart.scaleBy(x: 1, y: -1)

        let clipPath = Path(roundedRect: l.plot, cornerRadius: 10)

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

        drawGridlines(inner, text: ctx0, layout: l)
        drawTargetBand(inner, layout: l)
        drawLine(inner, chart: &chart, layout: l)
        drawTimeAxis(ctx0, layout: l)
        drawHover(ctx0, chart: &chart, layout: l)
    }

    /// Horizontal gridlines with value labels, at "nice" intervals.
    private func drawGridlines(_ ctx: GraphicsContext, text ctx0: GraphicsContext, layout l: Layout) {
        let plot = l.plot
        let step = ChartMath.niceStep(l.hi - l.lo)
        var level = (l.lo / step).rounded(.up) * step
        while level <= l.hi {
            let gy = l.y(level)
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: gy))
            grid.addLine(to: CGPoint(x: plot.maxX, y: gy))
            ctx.stroke(grid, with: .color(Color(nsColor: .separatorColor).opacity(0.35)), lineWidth: 0.5)

            let label = Text(String(format: "%g", level)).font(.system(size: 9)).foregroundStyle(.tertiary)
            let ly = min(max(gy + 2, plot.minY + 1), plot.maxY - 11)
            ctx0.draw(label, at: CGPoint(x: plot.minX + 5, y: l.screenY(ly)), anchor: .bottomLeading)
            level += step
        }
    }

    /// The optimal-range band, with dashed bounds.
    private func drawTargetBand(_ ctx: GraphicsContext, layout l: Layout) {
        let plot = l.plot
        let yLow = l.y(l.units.display(settings.targetLow))
        let yHigh = l.y(l.units.display(settings.targetHigh))
        let bandBottom = max(min(yLow, yHigh), plot.minY), bandTop = min(max(yLow, yHigh), plot.maxY)
        guard bandTop > bandBottom else { return }

        ctx.fill(Path(CGRect(x: plot.minX, y: bandBottom, width: plot.width, height: bandTop - bandBottom)),
                 with: .color(settings.bandColor))
        let boundColor = settings.bandColor.opacity(0.35)
        for gy in [bandBottom, bandTop] {
            var bound = Path()
            bound.move(to: CGPoint(x: plot.minX, y: gy))
            bound.addLine(to: CGPoint(x: plot.maxX, y: gy))
            ctx.stroke(bound, with: .color(boundColor), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    /// The reading line — split across dropouts, smoothed, optionally shaded
    /// underneath — plus the dot marking the latest reading. `chart` (unclipped)
    /// is where the dot goes, so its halo may bleed past the rounded corners.
    private func drawLine(_ inner: GraphicsContext, chart: inout GraphicsContext, layout l: Layout) {
        let plot = l.plot
        let zones = zones()
        // Zone bands, bottom→top in chart space: extreme-low … extreme-high.
        let exLowY = l.bandY(mgdl: settings.extremeLow)
        let lowY = l.bandY(mgdl: settings.targetLow)
        let highY = l.bandY(mgdl: settings.targetHigh)
        let exHighY = l.bandY(mgdl: settings.extremeHigh)
        let bands: [(CGFloat, CGFloat, Color)] = [
            (plot.minY, exLowY, zones.extremeLowColor),
            (exLowY, lowY, zones.belowColor),
            (lowY, highY, zones.inRangeColor),
            (highY, exHighY, zones.aboveColor),
            (exHighY, plot.maxY, zones.extremeHighColor),
        ]

        for segment in ChartMath.segments(of: l.visible, gapThreshold: ChartMath.dropoutThreshold) {
            let pts = segment.map { CGPoint(x: l.x($0.date), y: l.y(of: $0)) }
            guard pts.count >= 2 else {
                if let p = pts.first, let r = segment.first {
                    dot(inner, at: p, radius: 2, color: ChartMath.color(for: r.sgv, zones: zones))
                }
                continue
            }
            let path = ChartMath.smooth(pts)
            if settings.lineShadingEnabled { fillUnder(inner, path: path, points: pts, plot: plot, zones: zones) }

            if settings.blendLineColors {
                strokeBlended(inner, path: path, bands: bands, plot: plot)
            } else {
                for (minY, maxY, color) in bands where maxY - minY > 0.5 {
                    var bandCtx = inner
                    bandCtx.clip(to: Path(CGRect(x: plot.minX, y: minY, width: plot.width, height: maxY - minY)))
                    bandCtx.stroke(path, with: .color(color.opacity(0.9)), style: Self.lineStroke)
                }
            }
        }

        // Latest reading: halo + solid dot, both sized by the user (either at 0
        // hides that part).
        if let last = l.visible.last {
            let p = CGPoint(x: l.x(last.date), y: l.y(of: last))
            let color = dotColor(for: last, zones: zones)
            if settings.dotHaloRadius > 0 {
                dot(chart, at: p, radius: settings.dotHaloRadius, color: color.opacity(0.18))
            }
            if settings.dotRadius > 0 {
                dot(chart, at: p, radius: settings.dotRadius, color: color)
            }
        }
    }

    /// The fading area between the line and the bottom of the plot.
    private func fillUnder(_ ctx: GraphicsContext, path: Path, points pts: [CGPoint],
                           plot: CGRect, zones: ChartMath.Zones) {
        let shade = settings.lineShadingUsesLineColor
            ? zones.inRangeColor.opacity(0.14)
            : settings.lineShadingColor
        var area = path
        area.addLine(to: CGPoint(x: pts.last!.x, y: plot.minY))
        area.addLine(to: CGPoint(x: pts.first!.x, y: plot.minY))
        area.closeSubpath()
        var areaCtx = ctx
        areaCtx.clip(to: area)
        areaCtx.fill(Path(plot), with: .linearGradient(
            Gradient(colors: [shade, shade.opacity(0)]),
            startPoint: CGPoint(x: plot.midX, y: plot.maxY), endPoint: CGPoint(x: plot.midX, y: plot.minY)))
    }

    /// Start and latest timestamps under the plot.
    private func drawTimeAxis(_ ctx0: GraphicsContext, layout l: Layout) {
        let baseline = l.screenY(l.plot.minY) - 2
        for (date, x, anchor) in [(l.start, l.plot.minX, UnitPoint.bottomLeading),
                                  (l.visible.last!.date, l.plot.maxX, .bottomTrailing)] {
            let text = Text(Self.timeLabel(date, span: l.span)).font(.system(size: 9)).foregroundStyle(.tertiary)
            ctx0.draw(text, at: CGPoint(x: x, y: baseline), anchor: anchor)
        }
    }

    /// The zone thresholds and colors the line, dots and bands are painted with.
    private func zones() -> ChartMath.Zones {
        ChartMath.Zones(
            extremeLow: settings.extremeLow, targetLow: settings.targetLow,
            targetHigh: settings.targetHigh, extremeHigh: settings.extremeHigh,
            extremeLowColor: settings.extremeLowColor, belowColor: settings.belowColor,
            inRangeColor: settings.inRangeColor, aboveColor: settings.aboveColor,
            extremeHighColor: settings.extremeHighColor
        )
    }

    private static let lineStroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

    /// Stroke `path` with a vertical gradient that blends the zone colors into
    /// one another (bottom → top, matching the value axis), so the line's
    /// color shifts smoothly across thresholds instead of switching abruptly.
    private func strokeBlended(_ ctx: GraphicsContext, path: Path, bands: [(CGFloat, CGFloat, Color)], plot: CGRect) {
        var stops: [Gradient.Stop] = []
        for (minY, maxY, color) in bands where maxY - minY > 0.5 {
            let center = ((minY + maxY) / 2 - plot.minY) / plot.height
            stops.append(.init(color: color.opacity(0.9), location: min(max(center, 0), 1)))
        }
        guard !stops.isEmpty else { return }
        ctx.stroke(path, with: .linearGradient(
            Gradient(stops: stops.sorted { $0.location < $1.location }),
            startPoint: CGPoint(x: plot.midX, y: plot.minY), endPoint: CGPoint(x: plot.midX, y: plot.maxY)),
            style: Self.lineStroke)
    }

    /// Crosshair + value/time pill at the hovered reading.
    private func drawHover(_ ctx0: GraphicsContext, chart: inout GraphicsContext, layout l: Layout) {
        guard let i = hoverIndex, l.visible.indices.contains(i) else { return }
        let plot = l.plot
        let r = l.visible[i]
        let px = l.x(r.date), py = l.y(of: r)

        var vline = Path()
        vline.move(to: CGPoint(x: px, y: plot.minY))
        vline.addLine(to: CGPoint(x: px, y: plot.maxY))
        chart.stroke(vline, with: .color(Color(nsColor: .labelColor).opacity(0.25)), lineWidth: 1)

        // The crosshair always needs a visible marker, so this one keeps a floor
        // even when the latest-reading dot is sized down to nothing.
        dot(chart, at: CGPoint(x: px, y: py),
            radius: max(3, settings.dotRadius), color: dotColor(for: r, zones: zones()))

        let label = "\(r.text(in: l.units)) · \(Self.timeLabel(r.date, span: l.span))"
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
        ctx0.draw(resolved, at: CGPoint(x: box.minX + pad, y: l.screenY(box.minY + pad / 2)), anchor: .bottomLeading)
    }

    /// The dot color for a reading: its range zone's color by default, or the
    /// user's fixed `dotColor` when they've opted out of zone coloring.
    private func dotColor(for r: Reading, zones: ChartMath.Zones) -> Color {
        settings.dotUsesZoneColor ? ChartMath.color(for: r.sgv, zones: zones) : settings.dotColor
    }

    private func dot(_ ctx: GraphicsContext, at p: CGPoint, radius r: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    // MARK: - Hover tracking

    private func updateHover(at location: CGPoint, size: CGSize) {
        guard let l = layout(size: size) else { return }
        hoverIndex = ChartMath.nearestIndex(to: location.x, x: l.x, in: l.visible, maxDistance: 24)
    }
}
