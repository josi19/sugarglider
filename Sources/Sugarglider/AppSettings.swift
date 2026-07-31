import SwiftUI

/// Persisted settings, backed by `UserDefaults` and observed reactively via the
/// Observation framework. Every property is a plain stored var whose `didSet`
/// writes through to `defaults` — SwiftUI views bound to an `AppSettings`
/// instance (via `@Bindable`/`@Environment`) update automatically on change.
/// `init(defaults:)` is injectable so tests can use an isolated `UserDefaults`
/// suite instead of resetting the shared `.standard` domain.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    /// Fired when `baseURL`/`token` change, so `ReadingStore` (constructed
    /// separately, and not always alive as a view) can invalidate its cache
    /// and re-fetch. Not called during `init`'s initial load.
    var onConnectionChanged: (() -> Void)?

    /// Fired when `pollIntervalSeconds` changes, so `ReadingStore` can rebuild
    /// its timer with the new interval immediately. Not called during `init`'s
    /// initial load.
    var onPollIntervalChanged: (() -> Void)?

    /// Base URL of the Nightscout instance, e.g. "https://my-cgm.up.railway.app".
    var baseURL: String = "" {
        didSet {
            defaults.set(baseURL, forKey: "baseURL")
            if oldValue != baseURL { onConnectionChanged?() }
        }
    }

    /// Nightscout API access token (e.g. "monitor-1a2b3c4d"). Empty if the
    /// instance allows unauthenticated reads.
    var token: String = "" {
        didSet {
            defaults.set(token, forKey: "token")
            if oldValue != token { onConnectionChanged?() }
        }
    }

    /// Display units. Nightscout stores mg/dL internally; mmol/L divides by 18.
    enum Units: String {
        case mmol, mgdl

        var label: String { self == .mmol ? "mmol/L" : "mg/dL" }

        /// Convert an mg/dL quantity to the display unit.
        func display(_ mgdl: Double) -> Double { self == .mmol ? mgdl / 18.0 : mgdl }
        func value(fromMgdl sgv: Int) -> Double { display(Double(sgv)) }
        func text(fromMgdl sgv: Int) -> String {
            self == .mmol ? String(format: "%.1f", Double(sgv) / 18.0) : String(sgv)
        }

        /// Convert a display-unit value back to mg/dL (for storage).
        func toMgdl(_ value: Double) -> Double { self == .mmol ? value * 18.0 : value }
    }

    var units: Units = .mmol { didSet { defaults.set(units.rawValue, forKey: "units") } }

    /// Optimal/target glucose range, stored in mg/dL (Nightscout's native unit).
    /// Defaults to the common 70–180 mg/dL (≈ 3.9–10.0 mmol/L) range.
    var targetLow: Double = 70 { didSet { defaults.set(targetLow, forKey: "targetLow") } }
    var targetHigh: Double = 180 { didSet { defaults.set(targetHigh, forKey: "targetHigh") } }

    /// Extreme thresholds (mg/dL). Readings beyond these use the extreme colors.
    var extremeLow: Double = 54 { didSet { defaults.set(extremeLow, forKey: "extremeLow") } }
    var extremeHigh: Double = 250 { didSet { defaults.set(extremeHigh, forKey: "extremeHigh") } }

    /// Chart colors, each independently configurable and archived as `NSColor`
    /// (alpha included, so the band can be translucent). Defaults are
    /// monochromatic — the adaptive label color — so the chart is subtle until
    /// the user assigns zone colors.
    static let defaultBandColor = Color(nsColor: .labelColor).opacity(0.08)
    static let defaultInRangeColor = Color(nsColor: .labelColor)
    static let defaultBelowColor = Color(nsColor: .labelColor)
    static let defaultAboveColor = Color(nsColor: .labelColor)
    static let defaultExtremeLowColor = Color(nsColor: .labelColor)
    static let defaultExtremeHighColor = Color(nsColor: .labelColor)
    /// Translucent by default, matching the peak opacity of the gradient the
    /// area fill used before it became configurable.
    static let defaultLineShadingColor = Color(nsColor: .labelColor).opacity(0.14)
    static let defaultDotColor = Color(nsColor: .labelColor)
    /// A stand-in for the stock slider's neutral grey fill, so the default look
    /// is unchanged from when `sliderColor` was (silently) ignored.
    static let defaultSliderColor = Color(nsColor: .tertiaryLabelColor)
    // Opaque starting swatch so the color picker's opacity slider opens at 100%
    // rather than trapping a freshly-picked color at zero alpha. Whether it's
    // actually painted is governed by `chartBackgroundEnabled`.
    static let defaultChartBackgroundColor = Color(nsColor: .controlBackgroundColor)

    var bandColor: Color = defaultBandColor { didSet { persistColor(bandColor, "bandColor") } }
    var inRangeColor: Color = defaultInRangeColor { didSet { persistColor(inRangeColor, "inRangeColor") } }
    var belowColor: Color = defaultBelowColor { didSet { persistColor(belowColor, "belowColor") } }
    var aboveColor: Color = defaultAboveColor { didSet { persistColor(aboveColor, "aboveColor") } }
    var extremeLowColor: Color = defaultExtremeLowColor { didSet { persistColor(extremeLowColor, "extremeLowColor") } }
    var extremeHighColor: Color = defaultExtremeHighColor { didSet { persistColor(extremeHighColor, "extremeHighColor") } }
    var lineShadingColor: Color = defaultLineShadingColor { didSet { persistColor(lineShadingColor, "lineShadingColor") } }
    var dotColor: Color = defaultDotColor { didSet { persistColor(dotColor, "dotColor") } }
    var sliderColor: Color = defaultSliderColor { didSet { persistColor(sliderColor, "sliderColor") } }
    var chartBackgroundColor: Color = defaultChartBackgroundColor { didSet { persistColor(chartBackgroundColor, "chartBackgroundColor") } }

    /// Whether the chart is painted with `chartBackgroundColor`. Off by default,
    /// so the menu's glass material shows through.
    var chartBackgroundEnabled: Bool = false { didSet { defaults.set(chartBackgroundEnabled, forKey: "chartBackgroundEnabled") } }

    /// When true, the line's zone colors blend smoothly across thresholds via a
    /// vertical gradient instead of switching abruptly at each boundary.
    var blendLineColors: Bool = false { didSet { defaults.set(blendLineColors, forKey: "blendLineColors") } }

    /// Whether the area between the line and the bottom of the plot is filled
    /// with a fading gradient. On by default — the chart has always drawn it.
    var lineShadingEnabled: Bool = true { didSet { defaults.set(lineShadingEnabled, forKey: "lineShadingEnabled") } }

    /// When true (the default, and what the chart did before the shading became
    /// configurable) the shading is derived from the in-range zone color rather
    /// than from `lineShadingColor`, so it follows the line's palette.
    var lineShadingUsesLineColor: Bool = true {
        didSet { defaults.set(lineShadingUsesLineColor, forKey: "lineShadingUsesLineColor") }
    }

    /// When true (the default) the dot marking the latest reading is colored by
    /// that reading's range zone — a low reading shows a low-colored dot —
    /// rather than by the fixed `dotColor`.
    var dotUsesZoneColor: Bool = true { didSet { defaults.set(dotUsesZoneColor, forKey: "dotUsesZoneColor") } }

    /// Radius of the latest-reading dot and of the soft halo behind it, in
    /// points. Either at 0 hides that part; both are clamped to a range that
    /// can't swallow the chart.
    static let defaultDotRadius: Double = 4
    static let defaultDotHaloRadius: Double = 7

    var dotRadius: Double = defaultDotRadius {
        didSet {
            let clamped = min(12, max(0, dotRadius))
            if clamped != dotRadius { dotRadius = clamped; return }   // re-enter with the clamped value
            defaults.set(dotRadius, forKey: "dotRadius")
        }
    }
    var dotHaloRadius: Double = defaultDotHaloRadius {
        didSet {
            let clamped = min(24, max(0, dotHaloRadius))
            if clamped != dotHaloRadius { dotHaloRadius = clamped; return }
            defaults.set(dotHaloRadius, forKey: "dotHaloRadius")
        }
    }

    /// Restore all colors — and the shading/dot appearance they belong to — to
    /// their defaults, and clear the background.
    func resetColors() {
        bandColor = Self.defaultBandColor
        inRangeColor = Self.defaultInRangeColor
        belowColor = Self.defaultBelowColor
        aboveColor = Self.defaultAboveColor
        extremeLowColor = Self.defaultExtremeLowColor
        extremeHighColor = Self.defaultExtremeHighColor
        lineShadingColor = Self.defaultLineShadingColor
        dotColor = Self.defaultDotColor
        sliderColor = Self.defaultSliderColor
        chartBackgroundColor = Self.defaultChartBackgroundColor
        chartBackgroundEnabled = false
        lineShadingEnabled = true
        lineShadingUsesLineColor = true
        dotUsesZoneColor = true
        dotRadius = Self.defaultDotRadius
        dotHaloRadius = Self.defaultDotHaloRadius
    }

    // MARK: - Color presets

    /// The archive keys of every configurable color. A preset is just a snapshot
    /// keyed by these, so it round-trips through the same color storage.
    static let colorKeys = ["bandColor", "inRangeColor", "belowColor", "aboveColor",
                            "extremeLowColor", "extremeHighColor", "lineShadingColor", "dotColor",
                            "sliderColor", "chartBackgroundColor"]

    /// A named snapshot of every chart color plus the background-enable flag, so a
    /// user can keep several palettes and switch between them.
    struct ColorPreset {
        var name: String
        var colors: [String: Color]   // keyed by `colorKeys`
        var backgroundEnabled: Bool
    }

    /// Saved color presets, in the user's list order.
    var colorPresets: [ColorPreset] = [] { didSet { persistPresets(colorPresets) } }

    /// Add `preset`, replacing any existing one with the same name.
    func saveColorPreset(_ preset: ColorPreset) {
        if let i = colorPresets.firstIndex(where: { $0.name == preset.name }) {
            colorPresets[i] = preset
        } else {
            colorPresets.append(preset)
        }
    }

    func deleteColorPreset(named name: String) {
        colorPresets.removeAll { $0.name == name }
    }

    /// Selected chart window in hours (2–48, in 2h steps). Defaults to 6.
    var rangeHours: Int = 6 {
        didSet {
            let clamped = min(48, max(2, rangeHours))
            if clamped != rangeHours { rangeHours = clamped; return }   // re-enter with the clamped value
            defaults.set(rangeHours, forKey: "rangeHours")
        }
    }

    /// Appearance override. `.system` follows the OS setting.
    enum Theme: String {
        case system, light, dark

        /// The AppKit appearance for this override, or nil to follow the
        /// system. Applied per-window via `View.windowTheme(_:)` — see
        /// WindowAppearance.swift for why it must be `NSWindow.appearance`.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }

        /// The SwiftUI color-scheme override, or nil to follow the system.
        /// Used (via `preferredColorScheme`) only for the Settings window,
        /// whose appearance SwiftUI manages itself — see the theme bullet in
        /// CLAUDE.md's Conventions.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
    var theme: Theme = .system { didSet { defaults.set(theme.rawValue, forKey: "theme") } }

    /// Where to show the change since the previous reading.
    enum DeltaDisplay: Int { case off = 0, menu = 1, menuAndStatusBar = 2 }
    var deltaDisplay: DeltaDisplay = .menu { didSet { defaults.set(deltaDisplay.rawValue, forKey: "deltaDisplay") } }

    /// How often `ReadingStore` polls Nightscout for the latest reading, in
    /// seconds. Clamped to 3–300s (readings arrive every ~5 min, so anything
    /// far outside that is either wasteful or pointless).
    var pollIntervalSeconds: Int = 60 {
        didSet {
            let clamped = min(300, max(3, pollIntervalSeconds))
            if clamped != pollIntervalSeconds { pollIntervalSeconds = clamped; return }   // re-enter with the clamped value
            defaults.set(pollIntervalSeconds, forKey: "pollIntervalSeconds")
            if oldValue != pollIntervalSeconds { onPollIntervalChanged?() }
        }
    }

    var isConfigured: Bool { !baseURL.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A recognizable-but-unreadable form of an access token for display:
    /// first and last two characters with the middle elided, e.g.
    /// "reader-0123456789abcdef" → "re***ef". Tokens too short to elide
    /// meaningfully are masked entirely.
    static func maskedToken(_ token: String) -> String {
        guard token.count > 6 else { return String(repeating: "*", count: token.count) }
        return "\(token.prefix(2))***\(token.suffix(2))"
    }

    /// Compare two colors by their resolved sRGB channels — `Color ==` can
    /// report unequal for colors that render identically but were produced
    /// via different color spaces (e.g. one loaded from an archive).
    static func colorsMatch(_ a: Color, _ b: Color, eps: CGFloat = 0.01) -> Bool {
        guard let x = NSColor(a).usingColorSpace(.sRGB), let y = NSColor(b).usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) < eps
            && abs(x.greenComponent - y.greenComponent) < eps
            && abs(x.blueComponent - y.blueComponent) < eps
            && abs(x.alphaComponent - y.alphaComponent) < eps
    }

    /// The saved preset whose colors and background flag exactly match the
    /// current settings, if any — i.e. the palette currently in use.
    func matchingPreset() -> ColorPreset? {
        let current = Self.colorKeys.reduce(into: [String: Color]()) { dict, key in
            dict[key] = colorValue(for: key)
        }
        return colorPresets.first { preset in
            preset.backgroundEnabled == chartBackgroundEnabled
                && Self.colorKeys.allSatisfy { key in
                    guard let a = preset.colors[key], let b = current[key] else { return false }
                    return Self.colorsMatch(a, b)
                }
        }
    }

    /// Apply every color (and the background-enable flag) from `preset`.
    func apply(_ preset: ColorPreset) {
        if let c = preset.colors["bandColor"] { bandColor = c }
        if let c = preset.colors["inRangeColor"] { inRangeColor = c }
        if let c = preset.colors["belowColor"] { belowColor = c }
        if let c = preset.colors["aboveColor"] { aboveColor = c }
        if let c = preset.colors["extremeLowColor"] { extremeLowColor = c }
        if let c = preset.colors["extremeHighColor"] { extremeHighColor = c }
        if let c = preset.colors["lineShadingColor"] { lineShadingColor = c }
        if let c = preset.colors["dotColor"] { dotColor = c }
        if let c = preset.colors["sliderColor"] { sliderColor = c }
        if let c = preset.colors["chartBackgroundColor"] { chartBackgroundColor = c }
        chartBackgroundEnabled = preset.backgroundEnabled
    }

    /// Snapshot every current color into a named preset.
    func currentPreset(name: String) -> ColorPreset {
        let colors = Self.colorKeys.reduce(into: [String: Color]()) { dict, key in
            dict[key] = colorValue(for: key)
        }
        return ColorPreset(name: name, colors: colors, backgroundEnabled: chartBackgroundEnabled)
    }

    /// First unused "Palette N" name, so repeated saves don't collide by default.
    func defaultPresetName() -> String {
        let names = Set(colorPresets.map(\.name))
        var n = 1
        while names.contains("Palette \(n)") { n += 1 }
        return "Palette \(n)"
    }

    private func colorValue(for key: String) -> Color? {
        switch key {
        case "bandColor": return bandColor
        case "inRangeColor": return inRangeColor
        case "belowColor": return belowColor
        case "aboveColor": return aboveColor
        case "extremeLowColor": return extremeLowColor
        case "extremeHighColor": return extremeHighColor
        case "lineShadingColor": return lineShadingColor
        case "dotColor": return dotColor
        case "sliderColor": return sliderColor
        case "chartBackgroundColor": return chartBackgroundColor
        default: return nil
        }
    }

    // MARK: - Init / persistence plumbing

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateThresholdsToMgdl(in: defaults)

        if let v = defaults.string(forKey: "baseURL") { baseURL = v }
        if let v = defaults.string(forKey: "token") { token = v }
        if let v = defaults.string(forKey: "units").flatMap(Units.init) { units = v }
        if let v = defaults.object(forKey: "targetLow") as? Double { targetLow = v }
        if let v = defaults.object(forKey: "targetHigh") as? Double { targetHigh = v }
        if let v = defaults.object(forKey: "extremeLow") as? Double { extremeLow = v }
        if let v = defaults.object(forKey: "extremeHigh") as? Double { extremeHigh = v }
        bandColor = Self.loadColor("bandColor", default: Self.defaultBandColor, from: defaults)
        inRangeColor = Self.loadColor("inRangeColor", default: Self.defaultInRangeColor, from: defaults)
        belowColor = Self.loadColor("belowColor", default: Self.defaultBelowColor, from: defaults)
        aboveColor = Self.loadColor("aboveColor", default: Self.defaultAboveColor, from: defaults)
        extremeLowColor = Self.loadColor("extremeLowColor", default: Self.defaultExtremeLowColor, from: defaults)
        extremeHighColor = Self.loadColor("extremeHighColor", default: Self.defaultExtremeHighColor, from: defaults)
        lineShadingColor = Self.loadColor("lineShadingColor", default: Self.defaultLineShadingColor, from: defaults)
        dotColor = Self.loadColor("dotColor", default: Self.defaultDotColor, from: defaults)
        sliderColor = Self.loadColor("sliderColor", default: Self.defaultSliderColor, from: defaults)
        chartBackgroundColor = Self.loadColor("chartBackgroundColor", default: Self.defaultChartBackgroundColor, from: defaults)
        chartBackgroundEnabled = defaults.bool(forKey: "chartBackgroundEnabled")
        blendLineColors = defaults.bool(forKey: "blendLineColors")
        // `object(forKey:)`, not `bool(forKey:)` — these default to *true*, and
        // an unset key would otherwise read back as false.
        if let v = defaults.object(forKey: "lineShadingEnabled") as? Bool { lineShadingEnabled = v }
        if let v = defaults.object(forKey: "lineShadingUsesLineColor") as? Bool { lineShadingUsesLineColor = v }
        if let v = defaults.object(forKey: "dotUsesZoneColor") as? Bool { dotUsesZoneColor = v }
        if let v = defaults.object(forKey: "dotRadius") as? Double { dotRadius = v }
        if let v = defaults.object(forKey: "dotHaloRadius") as? Double { dotHaloRadius = v }
        colorPresets = Self.loadPresets(from: defaults)
        if let v = defaults.object(forKey: "rangeHours") as? Int { rangeHours = v }
        if let v = defaults.string(forKey: "theme").flatMap(Theme.init) { theme = v }
        if let v = defaults.object(forKey: "deltaDisplay") as? Int, let d = DeltaDisplay(rawValue: v) { deltaDisplay = d }
        if let v = defaults.object(forKey: "pollIntervalSeconds") as? Int { pollIntervalSeconds = v }
    }

    /// One-time migration: earlier versions stored thresholds in mmol/L. Any
    /// stored value below 40 is clearly mmol, so scale it to mg/dL. Runs
    /// against the raw store before values are read into this instance.
    private func migrateThresholdsToMgdl(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: "thresholdsMgdl") else { return }
        for key in ["targetLow", "targetHigh", "extremeLow", "extremeHigh"] {
            if let v = defaults.object(forKey: key) as? Double, v > 0, v < 40 {
                defaults.set((v * 18).rounded(), forKey: key)
            }
        }
        defaults.set(true, forKey: "thresholdsMgdl")
    }

    private func persistColor(_ color: Color, _ key: String) {
        Self.persistColor(color, key, to: defaults)
    }

    private static func persistColor(_ color: Color, _ key: String, to defaults: UserDefaults) {
        let ns = NSColor(color)
        defaults.set(try? NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: true), forKey: key)
    }

    private static func loadColor(_ key: String, default fallback: Color, from defaults: UserDefaults) -> Color {
        guard let data = defaults.data(forKey: key),
              let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { return fallback }
        return Color(nsColor: ns)
    }

    private func persistPresets(_ presets: [ColorPreset]) {
        let raw: [[String: Any]] = presets.map { preset in
            var archived: [String: Data] = [:]
            for (key, color) in preset.colors {
                let ns = NSColor(color)
                if let d = try? NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: true) {
                    archived[key] = d
                }
            }
            return ["name": preset.name, "colors": archived, "backgroundEnabled": preset.backgroundEnabled]
        }
        defaults.set(raw, forKey: "colorPresets")
    }

    private static func loadPresets(from defaults: UserDefaults) -> [ColorPreset] {
        guard let raw = defaults.array(forKey: "colorPresets") as? [[String: Any]] else { return [] }
        return raw.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let archived = dict["colors"] as? [String: Data] ?? [:]
            var colors: [String: Color] = [:]
            for (key, data) in archived {
                if let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                    colors[key] = Color(nsColor: ns)
                }
            }
            return ColorPreset(name: name, colors: colors,
                               backgroundEnabled: dict["backgroundEnabled"] as? Bool ?? false)
        }
    }
}
