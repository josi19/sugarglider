import Testing
import SwiftUI
@testable import Sugarglider

// MARK: - TintedSlider geometry
//
// The view itself isn't unit-testable, but its two pure helpers are — and they
// hold the only real logic: mapping a value to a knob position and a click
// position back to a stepped value.

extension SugargliderTests {
    @Test func fractionMapsValueAcrossTheRange() {
        #expect(TintedSlider.fraction(of: 2, in: 2...48) == 0)
        #expect(TintedSlider.fraction(of: 48, in: 2...48) == 1)
        #expect(TintedSlider.fraction(of: 25, in: 2...48) == 0.5)
    }

    @Test func fractionClampsOutOfRangeValues() {
        #expect(TintedSlider.fraction(of: -10, in: 2...48) == 0)
        #expect(TintedSlider.fraction(of: 100, in: 2...48) == 1)
        #expect(TintedSlider.fraction(of: 5, in: 5...5) == 0)   // zero-width range
    }

    /// The knob's travel is inset by half a knob at each end, so x = knob/2
    /// is the minimum and x = width - knob/2 the maximum.
    @Test func valueAtXHitsBothEndsExactly() {
        let width: CGFloat = 216   // 200 usable + one knob
        let knob = TintedSlider.knobDiameter
        #expect(TintedSlider.value(atX: knob / 2, trackWidth: width, range: 2...48, step: 2) == 2)
        #expect(TintedSlider.value(atX: width - knob / 2, trackWidth: width, range: 2...48, step: 2) == 48)
    }

    @Test func valueAtXClampsOutsideTheTrack() {
        #expect(TintedSlider.value(atX: -50, trackWidth: 216, range: 2...48, step: 2) == 2)
        #expect(TintedSlider.value(atX: 999, trackWidth: 216, range: 2...48, step: 2) == 48)
    }

    @Test func valueAtXSnapsToStep() {
        let width: CGFloat = 216
        let knob = TintedSlider.knobDiameter
        // Halfway along is 25, which isn't on the 2h grid — it snaps to 26.
        let mid = TintedSlider.value(atX: knob / 2 + 100, trackWidth: width, range: 2...48, step: 2)
        #expect(mid == 26)
        #expect(mid.truncatingRemainder(dividingBy: 2) == 0)

        // step 0 means no snapping at all.
        let free = TintedSlider.value(atX: knob / 2 + 100, trackWidth: width, range: 2...48, step: 0)
        #expect(abs(free - 25) < 0.0001)
    }

    /// A degenerate width must not divide by zero or escape the range.
    @Test func valueAtXSurvivesAZeroWidthTrack() {
        let v = TintedSlider.value(atX: 0, trackWidth: 0, range: 2...48, step: 2)
        #expect((2...48).contains(v))
    }
}
