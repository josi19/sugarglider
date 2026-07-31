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

    /// Out-of-order thresholds are surfaced, not corrected — the fields persist
    /// as you type, so moving a neighbouring value would fight anyone swapping a
    /// range around. Settings shows the message; the values stay untouched.
    @Test func thresholdOrderWarning() {
        let s = Self.makeSettings()
        #expect(s.thresholdOrderWarning == nil)          // defaults are in order

        s.targetLow = 200                                 // above targetHigh (180)
        #expect(s.thresholdOrderWarning == "Low must be below High.")
        #expect(s.targetLow == 200)                       // and nothing was clamped

        let low = Self.makeSettings()
        low.extremeLow = 90                               // above targetLow (70)
        #expect(low.thresholdOrderWarning == "Very low can't be above Low.")

        let high = Self.makeSettings()
        high.extremeHigh = 100                            // below targetHigh (180)
        #expect(high.thresholdOrderWarning == "Very high can't be below High.")

        // Touching bounds are legal: it just means no separate extreme zone.
        let touching = Self.makeSettings()
        touching.extremeLow = touching.targetLow
        touching.extremeHigh = touching.targetHigh
        #expect(touching.thresholdOrderWarning == nil)
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
        s.rangeHours = 72                 // the widest range, 3 days
        #expect(s.rangeHours == 72)
        s.rangeHours = 100                // clamped to 72
        #expect(s.rangeHours == 72)
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

    @Test func colorSchemeForTheme() {
        // The Settings window's variant of the override (see Theme.colorScheme).
        #expect(AppSettings.Theme.system.colorScheme == nil)
        #expect(AppSettings.Theme.light.colorScheme == .light)
        #expect(AppSettings.Theme.dark.colorScheme == .dark)
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

    /// These three default to *true*, so they can't be loaded with
    /// `bool(forKey:)` — an unset key would read back as false and silently
    /// turn the shading and zone-colored dot off on first launch.
    @Test func trueByDefaultFlagsSurviveAnEmptyStore() {
        let s = Self.makeSettings()
        #expect(s.lineShadingEnabled == true)
        #expect(s.lineShadingUsesLineColor == true)
        #expect(s.dotUsesZoneColor == true)
    }

    @Test func trueByDefaultFlagsRoundTripWhenTurnedOff() {
        let defaults = UserDefaults(suiteName: "SugargliderTests-\(UUID().uuidString)")!
        let s = AppSettings(defaults: defaults)
        s.lineShadingEnabled = false
        s.lineShadingUsesLineColor = false
        s.dotUsesZoneColor = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.lineShadingEnabled == false)
        #expect(reloaded.lineShadingUsesLineColor == false)
        #expect(reloaded.dotUsesZoneColor == false)
    }

    @Test func dotSizeDefaultsClampingAndRoundTrip() {
        let defaults = UserDefaults(suiteName: "SugargliderTests-\(UUID().uuidString)")!
        let s = AppSettings(defaults: defaults)
        #expect(s.dotRadius == AppSettings.defaultDotRadius)
        #expect(s.dotHaloRadius == AppSettings.defaultDotHaloRadius)

        s.dotRadius = 0                 // 0 is a valid value: hides the dot
        #expect(s.dotRadius == 0)
        s.dotRadius = -3                // clamped
        #expect(s.dotRadius == 0)
        s.dotRadius = 99                // clamped
        #expect(s.dotRadius == 12)
        s.dotHaloRadius = 99
        #expect(s.dotHaloRadius == 24)

        s.dotRadius = 6.5
        #expect(AppSettings(defaults: defaults).dotRadius == 6.5)
    }

    @Test func clampLimitsAreTheOnesTheUIOffers() {
        // The Settings sliders and the dropdown's range slider are built from
        // these, so a clamp that disagreed with them would fight the control.
        #expect(AppSettings.rangeHoursLimits == 2...72)
        #expect(AppSettings.dotRadiusLimits == 0...12)
        #expect(AppSettings.dotHaloRadiusLimits == 0...24)
        #expect(AppSettings.pollIntervalLimits == 3...300)
        #expect(AppSettings.staleAfterLimits == 5...240)
    }

    @Test func staleDelayDefaultClampingAndPersistence() {
        let defaults = UserDefaults(suiteName: "SugargliderTests-\(UUID().uuidString)")!
        let s = AppSettings(defaults: defaults)
        #expect(s.staleAfterMinutes == 11)
        #expect(s.staleAfterMinutes == AppSettings.defaultStaleAfterMinutes)
        #expect(s.staleThreshold == 11 * 60)        // exposed to ReadingStore in seconds
        s.staleAfterMinutes = 20
        #expect(s.staleThreshold == 20 * 60)
        s.staleAfterMinutes = 1                     // below the lower bound
        #expect(s.staleAfterMinutes == AppSettings.staleAfterLimits.lowerBound)
        s.staleAfterMinutes = 9999
        #expect(s.staleAfterMinutes == AppSettings.staleAfterLimits.upperBound)
        s.staleAfterMinutes = 30
        #expect(AppSettings(defaults: defaults).staleAfterMinutes == 30)
    }

    @Test func pollIntervalDefaultAndClamping() {
        let s = Self.makeSettings()
        #expect(s.pollIntervalSeconds == 60)
        s.pollIntervalSeconds = 30
        #expect(s.pollIntervalSeconds == 30)
        s.pollIntervalSeconds = 1
        #expect(s.pollIntervalSeconds == AppSettings.pollIntervalLimits.lowerBound)
        s.pollIntervalSeconds = 9999
        #expect(s.pollIntervalSeconds == AppSettings.pollIntervalLimits.upperBound)
    }

    /// The clamped setters re-enter themselves with the corrected value, so the
    /// change hook must still fire exactly once — and only for a real change.
    @Test func changeHooksFireOncePerChange() {
        let s = Self.makeSettings()
        var range = 0, poll = 0, connection = 0
        s.onRangeHoursChanged = { range += 1 }
        s.onPollIntervalChanged = { poll += 1 }
        s.onConnectionChanged = { connection += 1 }

        s.rangeHours = 12
        #expect(range == 1)
        s.rangeHours = 999          // clamped on the way in
        #expect(range == 2)
        #expect(s.rangeHours == AppSettings.rangeHoursLimits.upperBound)
        s.rangeHours = AppSettings.rangeHoursLimits.upperBound   // no change
        #expect(range == 2)

        s.pollIntervalSeconds = 9999
        #expect(poll == 1)
        s.pollIntervalSeconds = AppSettings.pollIntervalLimits.upperBound
        #expect(poll == 1)

        s.baseURL = "https://a"
        s.token = "t"
        s.baseURL = "https://a"     // no change
        #expect(connection == 2)
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

// MARK: - Number formatting

extension SugargliderTests {
    /// Every number is written with a dot and no grouping, whatever the system
    /// region is, so an entry field can't show "5,6" next to a reading rendered
    /// as "5.6" (`String(format:)` is locale-independent, `FormatStyle` isn't).
    @Test func numberFormatsAlwaysUseADot() {
        #expect(AppSettings.numberLocale.decimalSeparator == ".")
        #expect(1234.formatted(AppSettings.wholeNumberFormat) == "1234")   // never "1,234"
        let s = Self.makeSettings()
        s.units = .mmol
        #expect(10.5.formatted(s.thresholdFormat) == "10.5")
        #expect(10.0.formatted(s.thresholdFormat) == "10")     // trailing zero dropped
        s.units = .mgdl
        #expect(180.4.formatted(s.thresholdFormat) == "180")   // mg/dL is integral
        #expect(AppSettings.Units.mmol.text(fromMgdl: 189) == "10.5")   // the display path agrees
        // The same style type with a comma locale really does differ, so the
        // assertions above prove the pin rather than this machine's region.
        let commaStyle = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "de_DE"))
            .precision(.fractionLength(0...1))
        #expect(10.5.formatted(commaStyle) == "10,5")
    }

    /// The fields parse through the same styles they render with, so a dotted
    /// number typed into one has to round-trip.
    @Test func numberFormatsParseWhatTheyRender() throws {
        let s = Self.makeSettings()
        s.units = .mmol
        let threshold = try s.thresholdFormat.parseStrategy.parse("10.5")
        #expect(threshold == 10.5)
        let whole = try AppSettings.wholeNumberFormat.parseStrategy.parse("48")
        #expect(whole == 48)
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
        #expect(AppSettings.colorsMatch(s.lineShadingColor, AppSettings.defaultLineShadingColor))
        #expect(AppSettings.colorsMatch(s.dotColor, AppSettings.defaultDotColor))
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

    @Test func resetColorsRestoresShadingAndDotAppearance() {
        let s = Self.makeSettings()
        s.blendLineColors = true
        s.lineShadingEnabled = false
        s.lineShadingUsesLineColor = false
        s.lineShadingColor = Color(red: 1, green: 0, blue: 0, opacity: 1)
        s.dotUsesZoneColor = false
        s.dotColor = Color(red: 0, green: 1, blue: 0, opacity: 1)
        s.dotRadius = 1
        s.dotHaloRadius = 20

        s.resetColors()
        // Every appearance option the Colors tab offers, not just the colors.
        #expect(s.appearance == AppSettings.defaultAppearance)
        #expect(s.blendLineColors == false)
        #expect(s.lineShadingEnabled == true)
        #expect(s.lineShadingUsesLineColor == true)
        #expect(s.dotUsesZoneColor == true)
        #expect(s.dotRadius == AppSettings.defaultDotRadius)
        #expect(s.dotHaloRadius == AppSettings.defaultDotHaloRadius)
        #expect(AppSettings.colorsMatch(s.lineShadingColor, AppSettings.defaultLineShadingColor))
        #expect(AppSettings.colorsMatch(s.dotColor, AppSettings.defaultDotColor))
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
    @Test func colorKeysAreEveryConfigurableColor() {
        #expect(AppSettings.colorKeys == [
            "bandColor", "inRangeColor", "belowColor", "aboveColor",
            "extremeLowColor", "extremeHighColor", "lineShadingColor", "dotColor",
            "sliderColor", "chartBackgroundColor",
        ])
    }

    /// `colorSlots` is the one table the load, the reset and the preset
    /// round-trip all read, so each row has to point at the property it names
    /// and carry that property's default.
    @Test func colorSlotsPointAtTheirOwnProperty() {
        let s = Self.makeSettings()
        #expect(AppSettings.colorSlots.count == AppSettings.colorKeys.count)
        for slot in AppSettings.colorSlots {
            // Untouched settings hold the defaults, so the slot's default and the
            // value behind its key path must agree.
            #expect(AppSettings.colorsMatch(s[keyPath: slot.keyPath], slot.defaultValue),
                    "\(slot.key) default mismatch")
            // Writing through the key path has to land in a distinct property.
            let probe = Color(red: 0.42, green: 0.17, blue: 0.93, opacity: 1)
            s[keyPath: slot.keyPath] = probe
            let hits = AppSettings.colorSlots.filter { AppSettings.colorsMatch(s[keyPath: $0.keyPath], probe) }
            #expect(hits.map(\.key) == [slot.key], "\(slot.key) key path is not unique")
            s[keyPath: slot.keyPath] = slot.defaultValue
        }
    }

    /// Loading writes the colors through their real setters (a key-path write
    /// can't skip observers the way a direct `init` assignment does), so the
    /// suppression has to hold: archiving the defaults back would pin a color
    /// the user never chose, and a later change to that default would never
    /// reach them.
    @Test func loadingDoesNotWriteDefaultsBackToTheStore() {
        let defaults = UserDefaults(suiteName: "SugargliderTests-\(UUID().uuidString)")!
        _ = AppSettings(defaults: defaults)
        let archived = AppSettings.colorKeys.filter { defaults.data(forKey: $0) != nil }
        #expect(archived.isEmpty, "loading archived: \(archived)")
    }

    /// Every key in `colorKeys` must be wired into both directions of the
    /// preset round-trip — a key that `apply` or `currentPreset` doesn't know
    /// about would make `matchingPreset()` permanently report "Custom".
    @Test func everyColorKeyRoundTripsThroughAPreset() {
        let s = Self.makeSettings()
        let distinct = AppSettings.colorKeys.enumerated().reduce(into: [String: Color]()) { dict, pair in
            dict[pair.element] = Color(red: Double(pair.offset) / 16, green: 0.3, blue: 0.7, opacity: 1)
        }
        s.apply(.init(name: "P", colors: distinct, backgroundEnabled: true))
        let snapshot = s.currentPreset(name: "P")
        for key in AppSettings.colorKeys {
            let expected = try! #require(distinct[key])
            let actual = try! #require(snapshot.colors[key], "\(key) missing from currentPreset")
            #expect(AppSettings.colorsMatch(actual, expected), "\(key) not applied")
        }
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

    /// `appearance` is a computed view over the stored flags, so it has to write
    /// through to each of them (and read back what they hold).
    @Test func appearanceIsAViewOverTheStoredFlags() {
        let s = Self.makeSettings()
        s.appearance = AppSettings.Appearance(blendLineColors: true, lineShadingEnabled: false,
                                              lineShadingUsesLineColor: false, dotUsesZoneColor: false,
                                              dotRadius: 2, dotHaloRadius: 9)
        #expect(s.blendLineColors == true)
        #expect(s.lineShadingEnabled == false)
        #expect(s.lineShadingUsesLineColor == false)
        #expect(s.dotUsesZoneColor == false)
        #expect(s.dotRadius == 2)
        #expect(s.dotHaloRadius == 9)
        s.dotRadius = 5
        #expect(s.appearance.dotRadius == 5)
    }

    /// A preset is the whole look, not just the palette: switching to one has to
    /// bring its line/shading/dot settings along, survive a relaunch, and count
    /// as "not selected" as soon as any of them is changed by hand.
    @Test func presetsCarryTheAppearance() throws {
        let defaults = UserDefaults(suiteName: "SugargliderTests-\(UUID().uuidString)")!
        let s = AppSettings(defaults: defaults)
        let look = AppSettings.Appearance(blendLineColors: true, lineShadingEnabled: false,
                                         lineShadingUsesLineColor: true, dotUsesZoneColor: false,
                                         dotRadius: 6.5, dotHaloRadius: 0)
        s.appearance = look
        s.chartBackgroundEnabled = true
        s.saveColorPreset(s.currentPreset(name: "full"))

        #expect(s.colorPresets.first?.appearance == look)
        #expect(s.matchingPreset()?.name == "full")
        s.blendLineColors = false
        #expect(s.matchingPreset() == nil)             // one flag is enough to diverge

        s.appearance = AppSettings.defaultAppearance
        s.apply(try #require(s.colorPresets.first))
        #expect(s.appearance == look)

        #expect(AppSettings(defaults: defaults).colorPresets.first?.appearance == look)
    }

    /// Presets saved before appearances were part of one carry no `appearance`:
    /// they must apply their colors and leave the current line/dot settings
    /// alone, and must still register as the selected preset rather than
    /// silently becoming "Custom" after the update.
    @Test func presetsWithoutAnAppearanceApplyColorsOnly() {
        let s = Self.makeSettings()
        let look = AppSettings.Appearance(blendLineColors: true, lineShadingEnabled: false,
                                         lineShadingUsesLineColor: true, dotUsesZoneColor: false,
                                         dotRadius: 6.5, dotHaloRadius: 0)
        s.appearance = look
        var legacy = s.currentPreset(name: "legacy")
        legacy.appearance = nil
        s.saveColorPreset(legacy)

        #expect(s.matchingPreset()?.name == "legacy")
        s.apply(legacy)
        #expect(s.appearance == look)
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
