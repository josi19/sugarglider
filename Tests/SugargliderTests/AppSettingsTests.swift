import Testing
import SwiftUI
@testable import Sugarglider

// MARK: - Scalar settings

extension SugargliderTests {
    @Test func stringSettingsDefaultsAndRoundTrip() {
        let s = Self.makeSettings()
        #expect(s.baseURL == "")
        #expect(s.token == "")
        s.baseURL = "https://site.example"
        s.token = "monitor-abc"
        #expect(s.baseURL == "https://site.example")
        #expect(s.token == "monitor-abc")
    }

    @Test func unitsDefaultAndRoundTrip() {
        let s = Self.makeSettings()
        #expect(s.units == .mmol)          // default
        s.units = .mgdl
        #expect(s.units == .mgdl)
    }

    @Test func thresholdDefaults() {
        let s = Self.makeSettings()
        #expect(s.targetLow == 70)
        #expect(s.targetHigh == 180)
        #expect(s.extremeLow == 54)
        #expect(s.extremeHigh == 250)
    }

    @Test func thresholdRoundTrip() {
        let s = Self.makeSettings()
        s.targetLow = 80; s.targetHigh = 190
        s.extremeLow = 50; s.extremeHigh = 260
        #expect(s.targetLow == 80)
        #expect(s.targetHigh == 190)
        #expect(s.extremeLow == 50)
        #expect(s.extremeHigh == 260)
    }

    @Test func rangeHoursDefaultAndClamping() {
        let s = Self.makeSettings()
        #expect(s.rangeHours == 6)        // default when unset
        s.rangeHours = 24
        #expect(s.rangeHours == 24)
        s.rangeHours = 100                // clamped to 48
        #expect(s.rangeHours == 48)
        s.rangeHours = 1                  // clamped to 2
        #expect(s.rangeHours == 2)
        s.rangeHours = -5                 // clamped to 2
        #expect(s.rangeHours == 2)
    }

    @Test func themeDefaultAndRoundTrip() {
        let s = Self.makeSettings()
        #expect(s.theme == .system)
        s.theme = .dark
        #expect(s.theme == .dark)
        s.theme = .light
        #expect(s.theme == .light)
    }

    @Test func appearanceForTheme() {
        let s = Self.makeSettings()
        s.theme = .system; #expect(s.theme.nsAppearance == nil)
        s.theme = .light; #expect(s.theme.nsAppearance?.name == .aqua)
        s.theme = .dark; #expect(s.theme.nsAppearance?.name == .darkAqua)
    }

    @Test func deltaDisplayDefaultAndRoundTrip() {
        let s = Self.makeSettings()
        #expect(s.deltaDisplay == .menu)  // default when unset
        s.deltaDisplay = .off
        #expect(s.deltaDisplay == .off)
        s.deltaDisplay = .menuAndStatusBar
        #expect(s.deltaDisplay == .menuAndStatusBar)
        #expect(s.deltaDisplay.rawValue == 2)
    }

    @Test func boolFlagsDefaultAndRoundTrip() {
        let s = Self.makeSettings()
        #expect(s.chartBackgroundEnabled == false)
        #expect(s.blendLineColors == false)
        s.chartBackgroundEnabled = true
        s.blendLineColors = true
        #expect(s.chartBackgroundEnabled == true)
        #expect(s.blendLineColors == true)
    }

    @Test func isConfigured() {
        let s = Self.makeSettings()
        #expect(s.isConfigured == false)         // empty
        s.baseURL = "   "
        #expect(s.isConfigured == false)         // whitespace only
        s.baseURL = "https://site.example"
        #expect(s.isConfigured == true)
    }

    @Test func maskedToken() {
        #expect(AppSettings.maskedToken("reader-0123456789abcdef") == "re***ef")
        #expect(AppSettings.maskedToken("monitor-1a2b3c4d") == "mo***4d")
        #expect(AppSettings.maskedToken("secret1") == "se***t1")   // 7 chars: shortest elidable
        #expect(AppSettings.maskedToken("abcdef") == "******")     // too short to elide
        #expect(AppSettings.maskedToken("ab") == "**")
        #expect(AppSettings.maskedToken("") == "")                 // empty stays empty (prompt shows)
    }

    /// A value is persisted verbatim, including zero — unlike the old
    /// `Config` (a static enum reading straight from `UserDefaults`), where
    /// zero was indistinguishable from "never set" and silently snapped back
    /// to a default. `AppSettings` reads persisted values once at `init` (via
    /// `object(forKey:)`, which *can* distinguish absent from zero), so that
    /// ambiguity — and the surprising implicit clamp-on-write it required —
    /// no longer exists.
    @Test func thresholdAcceptsExplicitZero() {
        let s = Self.makeSettings()
        s.targetLow = 0
        #expect(s.targetLow == 0)
    }
}

// MARK: - Threshold migration

extension SugargliderTests {
    @Test func migrationScalesLegacyMmolToMgdl() {
        let defaults = UserDefaults(suiteName: "SugargliderTests-\(UUID().uuidString)")!
        // Seed legacy mmol-scale values (all < 40) and no migration flag.
        defaults.set(3.9, forKey: "targetLow"); defaults.set(10.0, forKey: "targetHigh")
        defaults.set(3.0, forKey: "extremeLow"); defaults.set(13.9, forKey: "extremeHigh")
        let s = AppSettings(defaults: defaults)
        #expect(s.targetLow == 70)     // 3.9 * 18 = 70.2 → 70
        #expect(s.targetHigh == 180)   // 10.0 * 18 = 180
        #expect(s.extremeLow == 54)    // 3.0 * 18 = 54
        #expect(s.extremeHigh == 250)  // 13.9 * 18 = 250.2 → 250
    }

    @Test func migrationLeavesMgdlValuesAlone() {
        let defaults = UserDefaults(suiteName: "SugargliderTests-\(UUID().uuidString)")!
        defaults.set(180.0, forKey: "targetHigh")   // already mg/dL (>= 40)
        let s = AppSettings(defaults: defaults)
        #expect(s.targetHigh == 180)
    }

    @Test func migrationIsIdempotent() {
        let defaults = UserDefaults(suiteName: "SugargliderTests-\(UUID().uuidString)")!
        defaults.set(3.9, forKey: "targetLow")
        _ = AppSettings(defaults: defaults)          // runs migration, sets the flag, persists 70
        #expect(defaults.double(forKey: "targetLow") == 70)

        defaults.set(3.9, forKey: "targetLow")       // a fresh small value, flag already set
        let s2 = AppSettings(defaults: defaults)
        #expect(s2.targetLow == 3.9)                 // no re-scaling — migration already ran
    }
}

// MARK: - Colors

extension SugargliderTests {
    @Test func colorDefaultsWhenUnset() {
        let s = Self.makeSettings()
        #expect(AppSettings.colorsMatch(s.inRangeColor, AppSettings.defaultInRangeColor))
        #expect(AppSettings.colorsMatch(s.bandColor, AppSettings.defaultBandColor))
        #expect(AppSettings.colorsMatch(s.sliderColor, AppSettings.defaultSliderColor))
    }

    @Test func colorRoundTripThroughArchive() {
        let s = Self.makeSettings()
        let custom = Color(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.4)
        s.inRangeColor = custom
        #expect(AppSettings.colorsMatch(s.inRangeColor, custom))
    }

    @Test func resetColorsRestoresDefaultsAndClearsBackground() {
        let s = Self.makeSettings()
        s.inRangeColor = Color(red: 1, green: 0, blue: 0, opacity: 1)
        s.chartBackgroundEnabled = true
        #expect(!AppSettings.colorsMatch(s.inRangeColor, AppSettings.defaultInRangeColor))

        s.resetColors()
        #expect(AppSettings.colorsMatch(s.inRangeColor, AppSettings.defaultInRangeColor))
        #expect(s.chartBackgroundEnabled == false)
    }

    @Test func colorsMatchComparesResolvedChannels() {
        let red = Color(red: 1, green: 0, blue: 0, opacity: 1)
        #expect(AppSettings.colorsMatch(red, red))
        #expect(AppSettings.colorsMatch(red, Color(red: 1, green: 0, blue: 0, opacity: 1)))
        #expect(!AppSettings.colorsMatch(red, Color(red: 0, green: 0, blue: 1, opacity: 1)))
    }
}

// MARK: - Color presets

extension SugargliderTests {
    @Test func colorKeysAreTheEightConfigurableColors() {
        #expect(AppSettings.colorKeys == [
            "bandColor", "inRangeColor", "belowColor", "aboveColor",
            "extremeLowColor", "extremeHighColor", "sliderColor", "chartBackgroundColor",
        ])
    }

    @Test func presetsDefaultEmpty() {
        #expect(Self.makeSettings().colorPresets.isEmpty)
    }

    @Test func savePresetRoundTrips() {
        let s = Self.makeSettings()
        let red = Color(red: 1, green: 0, blue: 0, opacity: 1)
        let green = Color(red: 0, green: 1, blue: 0, opacity: 1)
        s.saveColorPreset(.init(name: "P", colors: ["bandColor": red, "sliderColor": green],
                                 backgroundEnabled: true))
        let presets = s.colorPresets
        #expect(presets.count == 1)
        let p = try! #require(presets.first)
        #expect(p.name == "P")
        #expect(p.backgroundEnabled == true)
        #expect(AppSettings.colorsMatch(try! #require(p.colors["bandColor"]), red))
        #expect(AppSettings.colorsMatch(try! #require(p.colors["sliderColor"]), green))
    }

    @Test func savePresetWithSameNameReplaces() {
        let s = Self.makeSettings()
        let red = Color(red: 1, green: 0, blue: 0, opacity: 1)
        let blue = Color(red: 0, green: 0, blue: 1, opacity: 1)
        s.saveColorPreset(.init(name: "P", colors: ["bandColor": red], backgroundEnabled: false))
        s.saveColorPreset(.init(name: "P", colors: ["bandColor": blue], backgroundEnabled: true))
        #expect(s.colorPresets.count == 1)
        let p = try! #require(s.colorPresets.first)
        #expect(p.backgroundEnabled == true)
        #expect(AppSettings.colorsMatch(try! #require(p.colors["bandColor"]), blue))
    }

    @Test func deletePreset() {
        let s = Self.makeSettings()
        s.saveColorPreset(.init(name: "A", colors: [:], backgroundEnabled: false))
        s.saveColorPreset(.init(name: "B", colors: [:], backgroundEnabled: false))
        s.deleteColorPreset(named: "A")
        #expect(s.colorPresets.map(\.name) == ["B"])
        s.deleteColorPreset(named: "does-not-exist")   // no-op
        #expect(s.colorPresets.map(\.name) == ["B"])
    }

    @Test func defaultPresetNameSkipsTakenNames() {
        let s = Self.makeSettings()
        #expect(s.defaultPresetName() == "Palette 1")
        s.saveColorPreset(.init(name: "Palette 1", colors: [:], backgroundEnabled: false))
        #expect(s.defaultPresetName() == "Palette 2")
    }

    @Test func matchingPresetFindsSavedPalette() {
        let s = Self.makeSettings()
        s.saveColorPreset(s.currentPreset(name: "cur"))   // snapshot of the live colors
        #expect(s.matchingPreset()?.name == "cur")
    }

    @Test func matchingPresetNilWhenNoFullMatch() {
        let s = Self.makeSettings()
        // A preset missing most colorKeys can never fully match the current colors.
        s.saveColorPreset(.init(name: "partial",
                                 colors: ["bandColor": Color(red: 1, green: 0, blue: 0, opacity: 1)],
                                 backgroundEnabled: false))
        #expect(s.matchingPreset() == nil)
    }

    @Test func applyPresetSetsColorsAndBackgroundFlag() {
        let s = Self.makeSettings()
        let band = Color(red: 1, green: 0, blue: 0, opacity: 1)
        let bg = Color(red: 0, green: 0, blue: 1, opacity: 1)
        let preset = AppSettings.ColorPreset(name: "P", colors: ["bandColor": band, "chartBackgroundColor": bg],
                                             backgroundEnabled: true)
        s.apply(preset)
        #expect(AppSettings.colorsMatch(s.bandColor, band))
        #expect(AppSettings.colorsMatch(s.chartBackgroundColor, bg))
        #expect(s.chartBackgroundEnabled == true)
    }
}
