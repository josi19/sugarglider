import SwiftUI
import AppKit

/// A horizontal slider whose filled track honors an arbitrary color.
///
/// SwiftUI's stock `Slider` is AppKit-backed on macOS and its track is
/// **not tintable**: `.tint(_:)`/`.accentColor(_:)` are ignored, and so is
/// `NSSlider.trackFillColor` on the modern control — the fill is a fixed
/// neutral grey (verified by off-screen renders on macOS 26). Honoring
/// `AppSettings.sliderColor` therefore means drawing the control ourselves;
/// this is deliberately the only hand-drawn stock control in the app.
///
/// Behavior matches `NSSlider`: clicking anywhere on the track jumps the knob
/// there, dragging tracks continuously, and values snap to `step`. Keyboard
/// adjustment is the one thing the stock control has and this doesn't — the
/// VoiceOver increment/decrement actions below cover the accessibility case.
/// The geometry itself lives in the two static helpers, which are pure and
/// unit-tested without a live view.
struct TintedSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0
    var tint: Color
    /// Spoken by VoiceOver in place of the raw number, e.g. "6 hours".
    var accessibilityValueText: String?

    static let knobDiameter: CGFloat = 16
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // The knob's center travels between the two inset ends, so the
            // filled track has to stop at the knob's center, not the edge.
            let usable = max(width - Self.knobDiameter, 1)
            let f = Self.fraction(of: value, in: range)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(tint)
                    .frame(width: Self.knobDiameter / 2 + usable * f, height: trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                    .offset(x: usable * f)
            }
            .frame(height: Self.knobDiameter)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    value = Self.value(atX: g.location.x, trackWidth: width, range: range, step: step)
                }
            )
        }
        .frame(height: Self.knobDiameter)
        .accessibilityElement()
        .accessibilityValue(accessibilityValueText ?? String(format: "%g", value))
        .accessibilityAdjustableAction { direction in
            let delta = step > 0 ? step : (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(max(value + delta, range.lowerBound), range.upperBound)
            case .decrement: value = min(max(value - delta, range.lowerBound), range.upperBound)
            @unknown default: break
            }
        }
    }

    /// Where `value` sits in `range`, as 0…1 (clamped).
    static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// The value a click/drag at `x` (in view coordinates) selects: the knob's
    /// travel is inset by half a knob at each end, and the result is snapped to
    /// `step` (when > 0) and clamped to `range`.
    static func value(atX x: CGFloat, trackWidth: CGFloat,
                      range: ClosedRange<Double>, step: Double) -> Double {
        let usable = max(trackWidth - knobDiameter, 1)
        let f = min(max((x - knobDiameter / 2) / usable, 0), 1)
        let raw = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
        let snapped = step > 0 ? (raw / step).rounded() * step : raw
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}
