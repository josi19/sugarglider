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

    // Subscriptions, not settings — `ReadingStore.start()` installs all three,
    // and no view observes them, so they stay out of change tracking.

    /// Fired when `baseURL`/`token` change, so `ReadingStore` (constructed
    /// separately, and not always alive as a view) can invalidate its cache
    /// and re-fetch. Not called during `init`'s initial load.
    @ObservationIgnored var onConnectionChanged: (() -> Void)?

    /// Fired when `pollIntervalSeconds` changes, so `ReadingStore` can rebuild
    /// its timer with the new interval immediately. Not called during `init`'s
    /// initial load.
    @ObservationIgnored var onPollIntervalChanged: (() -> Void)?

    /// Fired when `rangeHours` changes, so `ReadingStore` can fetch the history
    /// a *widened* window needs — the cache is only ever sized to the window
    /// that was asked for. Not called during `init`'s initial load.
    @ObservationIgnored var onRangeHoursChanged: (() -> Void)?

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

    // MARK: - Number formatting

    /// Every number the app shows or accepts uses a **dot** as the decimal
    /// separator and no digit grouping, whatever the system region says — a
    /// reading rendered as "5.6" must not sit next to an entry field showing
    /// "5,6". `String(format:)` (the readings, the delta, the chart's axis
    /// labels) is locale-independent already; `FormatStyle` is *not* unless it
    /// is pinned, which is what these two do. The flip side is that the entry
    /// fields expect a dot too — "5,6" won't parse.
    static let numberLocale = Locale(identifier: "en_US_POSIX")

    /// For the whole-number entry fields: chart range and refresh interval.
    static let wholeNumberFormat = IntegerFormatStyle<Int>(locale: numberLocale).grouping(.never)

    /// For the glucose-threshold entry fields: one decimal in mmol/L, none in
    /// mg/dL — matching `Units.text(fromMgdl:)`.
    var thresholdFormat: FloatingPointFormatStyle<Double> {
        FloatingPointFormatStyle<Double>(locale: Self.numberLocale)
            .precision(.fractionLength(0...(units == .mmol ? 1 : 0)))
            .grouping(.never)
    }

    /// Optimal/target glucose range, stored in mg/dL (Nightscout's native unit).
    /// Defaults to the common 70–180 mg/dL (≈ 3.9–10.0 mmol/L) range.
    var targetLow: Double = 70 { didSet { defaults.set(targetLow, forKey: "targetLow") } }
    var targetHigh: Double = 180 { didSet { defaults.set(targetHigh, forKey: "targetHigh") } }

    /// Extreme thresholds (mg/dL). Readings beyond these use the extreme colors.
    var extremeLow: Double = 54 { didSet { defaults.set(extremeLow, forKey: "extremeLow") } }
    var extremeHigh: Double = 250 { didSet { defaults.set(extremeHigh, forKey: "extremeHigh") } }

    /// What's wrong with the order of the four thresholds, or nil if they're
    /// usable. The fields are deliberately *not* clamped against each other —
    /// they persist as you type, so silently moving a neighbouring value would
    /// fight anyone swapping a range around — but out-of-order thresholds make
    /// the zone coloring meaningless (`ChartMath.color(for:zones:)` tests them
    /// in order, so with Low above High the in-range color becomes unreachable
    /// and the target band disappears). Settings shows this as a warning instead.
    var thresholdOrderWarning: String? {
        if targetLow >= targetHigh { return "Low must be below High." }
        if extremeLow > targetLow { return "Very low can't be above Low." }
        if extremeHigh < targetHigh { return "Very high can't be below High." }
        return nil
    }

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
    /// can't swallow the chart. Single source of truth: the Settings sliders
    /// read the same limits the write-through clamps to.
    static let defaultDotRadius: Double = 4
    static let defaultDotHaloRadius: Double = 7
    static let dotRadiusLimits: ClosedRange<Double> = 0...12
    static let dotHaloRadiusLimits: ClosedRange<Double> = 0...24

    var dotRadius: Double = defaultDotRadius {
        didSet { writeThrough(\.dotRadius, key: "dotRadius", limits: Self.dotRadiusLimits) }
    }
    var dotHaloRadius: Double = defaultDotHaloRadius {
        didSet { writeThrough(\.dotHaloRadius, key: "dotHaloRadius", limits: Self.dotHaloRadiusLimits) }
    }

    /// The Colors tab's *non-color* options in one value: how the line, its
    /// shading and the latest-reading dot are drawn. Bundling them means the
    /// defaults, the reset and the presets share one definition of "the look"
    /// instead of three lists that can fall out of step. `Codable` so a preset
    /// can persist it without a per-field serializer.
    struct Appearance: Codable, Equatable {
        var blendLineColors: Bool
        var lineShadingEnabled: Bool
        var lineShadingUsesLineColor: Bool
        var dotUsesZoneColor: Bool
        var dotRadius: Double
        var dotHaloRadius: Double
    }

    static let defaultAppearance = Appearance(
        blendLineColors: false, lineShadingEnabled: true, lineShadingUsesLineColor: true,
        dotUsesZoneColor: true, dotRadius: defaultDotRadius, dotHaloRadius: defaultDotHaloRadius
    )

    /// A view over the stored flags above — *computed*, which is fine here and
    /// not a violation of the "Observation only tracks stored properties" rule:
    /// the getter reads those stored properties, so a view reading `appearance`
    /// still tracks them. (What doesn't work is a computed property backed by
    /// `UserDefaults` directly, which reads nothing observable.)
    var appearance: Appearance {
        get {
            Appearance(blendLineColors: blendLineColors,
                       lineShadingEnabled: lineShadingEnabled,
                       lineShadingUsesLineColor: lineShadingUsesLineColor,
                       dotUsesZoneColor: dotUsesZoneColor,
                       dotRadius: dotRadius, dotHaloRadius: dotHaloRadius)
        }
        set {
            blendLineColors = newValue.blendLineColors
            lineShadingEnabled = newValue.lineShadingEnabled
            lineShadingUsesLineColor = newValue.lineShadingUsesLineColor
            dotUsesZoneColor = newValue.dotUsesZoneColor
            dotRadius = newValue.dotRadius
            dotHaloRadius = newValue.dotHaloRadius
        }
    }

    /// Restore every appearance setting the Colors tab offers to its default:
    /// all colors, plus the line-blending, shading, dot and background options
    /// that go with them. Nothing outside that tab is touched (connection,
    /// units, thresholds, chart range stay as they are).
    func resetColors() {
        for slot in Self.colorSlots { self[keyPath: slot.keyPath] = slot.defaultValue }
        chartBackgroundEnabled = false
        appearance = Self.defaultAppearance
    }

    // MARK: - Color presets

    /// One configurable chart color: its archive key, the property holding it,
    /// and its default. Everything that treats the colors as a *set* — the
    /// initial load, `resetColors()`, and the whole preset round-trip — drives
    /// off `colorSlots`, so a new color means a stored property plus one row
    /// here and nothing else. (Each property still names its own key in `didSet`;
    /// Observation only tracks stored properties, so the write-through can't be
    /// generated away.)
    struct ColorSlot {
        let key: String
        let keyPath: ReferenceWritableKeyPath<AppSettings, Color>
        let defaultValue: Color
    }

    static let colorSlots: [ColorSlot] = [
        .init(key: "bandColor", keyPath: \.bandColor, defaultValue: defaultBandColor),
        .init(key: "inRangeColor", keyPath: \.inRangeColor, defaultValue: defaultInRangeColor),
        .init(key: "belowColor", keyPath: \.belowColor, defaultValue: defaultBelowColor),
        .init(key: "aboveColor", keyPath: \.aboveColor, defaultValue: defaultAboveColor),
        .init(key: "extremeLowColor", keyPath: \.extremeLowColor, defaultValue: defaultExtremeLowColor),
        .init(key: "extremeHighColor", keyPath: \.extremeHighColor, defaultValue: defaultExtremeHighColor),
        .init(key: "lineShadingColor", keyPath: \.lineShadingColor, defaultValue: defaultLineShadingColor),
        .init(key: "dotColor", keyPath: \.dotColor, defaultValue: defaultDotColor),
        .init(key: "sliderColor", keyPath: \.sliderColor, defaultValue: defaultSliderColor),
        .init(key: "chartBackgroundColor", keyPath: \.chartBackgroundColor,
              defaultValue: defaultChartBackgroundColor),
    ]

    /// The archive keys of every configurable color, in table order. A preset is
    /// just a snapshot keyed by these, so it round-trips through the same color
    /// storage.
    static var colorKeys: [String] { colorSlots.map(\.key) }

    /// A named snapshot of the whole Colors tab — every chart color, the
    /// background-enable flag, and the line/shading/dot `Appearance` — so a user
    /// can keep several looks and switch between them.
    ///
    /// `appearance` is optional because presets saved before it existed don't
    /// carry one: those apply their colors and leave the current line/dot
    /// settings alone, rather than silently resetting them.
    struct ColorPreset {
        var name: String
        var colors: [String: Color]   // keyed by `colorKeys`
        var backgroundEnabled: Bool
        /// Omitted (nil) means "colors only" — see the note above.
        var appearance: Appearance? = nil
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

    /// Bounds for `rangeHours`. Single source of truth: the slider's range, the
    /// clamp below and `ReadingStore`'s history sizing all read it, since a
    /// wider window silently needs a longer fetch to fill it.
    static let rangeHoursLimits: ClosedRange<Int> = 2...72

    /// Selected chart window in hours (2–72, in 2h steps on the slider; any
    /// whole hour can be typed). Defaults to 6.
    var rangeHours: Int = 6 {
        didSet {
            guard writeThrough(\.rangeHours, key: "rangeHours", limits: Self.rangeHoursLimits) else { return }
            if oldValue != rangeHours { onRangeHoursChanged?() }
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

    /// How long a reading may go without a successor before it's flagged as
    /// stale, in minutes. It's a setting rather than a constant because the right
    /// value depends on the CGM and uploader: how often a site receives readings
    /// varies, so no single delay is "one missed reading" for everyone. 11 is a
    /// middle-of-the-road default — long enough that a brief upload hiccup passes
    /// unremarked, short enough to notice a feed that stopped. The lower bound
    /// keeps the flag from being on more often than off: a reading is already
    /// some minutes old by the time it arrives.
    static let defaultStaleAfterMinutes = 11
    static let staleAfterLimits: ClosedRange<Int> = 5...240

    var staleAfterMinutes: Int = defaultStaleAfterMinutes {
        didSet { writeThrough(\.staleAfterMinutes, key: "staleAfterMinutes", limits: Self.staleAfterLimits) }
    }

    /// `staleAfterMinutes` as the interval `ReadingStore.isStale` compares against.
    var staleThreshold: TimeInterval { Double(staleAfterMinutes) * 60 }

    /// How often `ReadingStore` polls Nightscout for the latest reading, in
    /// seconds. Clamped to 3–300s (readings arrive every ~5 min, so anything
    /// far outside that is either wasteful or pointless).
    static let pollIntervalLimits: ClosedRange<Int> = 3...300

    var pollIntervalSeconds: Int = 60 {
        didSet {
            guard writeThrough(\.pollIntervalSeconds, key: "pollIntervalSeconds",
                               limits: Self.pollIntervalLimits) else { return }
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

    /// The saved preset whose look exactly matches the current settings, if any
    /// — i.e. the one currently in use. A preset without an `appearance` is
    /// judged on its colors alone, so presets saved by an older version keep
    /// showing as selected instead of turning into "Custom".
    func matchingPreset() -> ColorPreset? {
        let current = currentColors()
        return colorPresets.first { preset in
            preset.backgroundEnabled == chartBackgroundEnabled
                && (preset.appearance == nil || preset.appearance == appearance)
                && Self.colorSlots.allSatisfy { slot in
                    guard let a = preset.colors[slot.key], let b = current[slot.key] else { return false }
                    return Self.colorsMatch(a, b)
                }
        }
    }

    /// Apply everything `preset` carries: its colors, the background flag, and
    /// its line/shading/dot appearance if it has one. Colors it doesn't carry
    /// are left as they are.
    func apply(_ preset: ColorPreset) {
        for slot in Self.colorSlots {
            if let color = preset.colors[slot.key] { self[keyPath: slot.keyPath] = color }
        }
        chartBackgroundEnabled = preset.backgroundEnabled
        if let appearance = preset.appearance { self.appearance = appearance }
    }

    /// Snapshot the whole current look into a named preset.
    func currentPreset(name: String) -> ColorPreset {
        ColorPreset(name: name, colors: currentColors(),
                    backgroundEnabled: chartBackgroundEnabled, appearance: appearance)
    }

    /// First unused "Palette N" name, so repeated saves don't collide by default.
    func defaultPresetName() -> String {
        let names = Set(colorPresets.map(\.name))
        var n = 1
        while names.contains("Palette \(n)") { n += 1 }
        return "Palette \(n)"
    }

    /// Every live color, keyed by archive key — the shape a preset stores.
    private func currentColors() -> [String: Color] {
        Self.colorSlots.reduce(into: [:]) { dict, slot in dict[slot.key] = self[keyPath: slot.keyPath] }
    }

    // MARK: - Init / persistence plumbing

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateThresholdsToMgdl(in: defaults)

        if let v = defaults.string(forKey: "baseURL") { baseURL = v }
        if let v = defaults.string(forKey: "token") { token = v }
        if let v = defaults.string(forKey: "units").flatMap(Units.init) { units = v }
        if let v = defaults.object(forKey: "targetLow") as? Double { targetLow = v }
        if let v = defaults.object(forKey: "targetHigh") as? Double { targetHigh = v }
        if let v = defaults.object(forKey: "extremeLow") as? Double { extremeLow = v }
        if let v = defaults.object(forKey: "extremeHigh") as? Double { extremeHigh = v }
        // Unlike the direct assignments above, these go through the real setters
        // (a key-path write can't skip observers the way `init` does), so
        // `isLoading` keeps them from archiving straight back what they read —
        // which would also freeze today's defaults into the store for colors
        // the user never touched.
        for slot in Self.colorSlots {
            self[keyPath: slot.keyPath] = Self.loadColor(slot.key, default: slot.defaultValue, from: defaults)
        }
        isLoading = false
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
        if let v = defaults.object(forKey: "staleAfterMinutes") as? Int { staleAfterMinutes = v }
    }

    /// One-time migration: earlier versions stored thresholds in mmol/L. Any
    /// stored value below 40 is clearly mmol, so scale it to mg/dL. Runs
    /// against the raw store before values are read into this instance.
    private static func migrateThresholdsToMgdl(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: "thresholdsMgdl") else { return }
        for key in ["targetLow", "targetHigh", "extremeLow", "extremeHigh"] {
            if let v = defaults.object(forKey: key) as? Double, v > 0, v < 40 {
                defaults.set((v * 18).rounded(), forKey: key)
            }
        }
        defaults.set(true, forKey: "thresholdsMgdl")
    }

    /// Write-through for a clamped numeric setting, called from that property's
    /// own `didSet`. A value outside `limits` is re-assigned in clamped form —
    /// which re-enters this method through the setter — and `false` is returned
    /// so the outer pass skips persisting and any change hook: the settling pass
    /// does both. In range, the value is persisted and `true` returned.
    @discardableResult
    private func writeThrough<T: Comparable>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>,
                                            key: String, limits: ClosedRange<T>) -> Bool {
        let value = self[keyPath: keyPath]
        let clamped = min(max(value, limits.lowerBound), limits.upperBound)
        guard clamped == value else { self[keyPath: keyPath] = clamped; return false }
        defaults.set(value, forKey: key)
        return true
    }

    /// True only while `init` populates the colors from the store — see the loop
    /// there for why the write-back has to be suppressed.
    private var isLoading = true

    private func persistColor(_ color: Color, _ key: String) {
        guard !isLoading else { return }
        defaults.set(Self.archive(color), forKey: key)
    }

    private static func archive(_ color: Color) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: NSColor(color), requiringSecureCoding: true)
    }

    private static func loadColor(_ key: String, default fallback: Color, from defaults: UserDefaults) -> Color {
        guard let data = defaults.data(forKey: key),
              let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { return fallback }
        return Color(nsColor: ns)
    }

    private func persistPresets(_ presets: [ColorPreset]) {
        let raw: [[String: Any]] = presets.map { preset in
            var stored: [String: Any] = [
                "name": preset.name,
                "colors": preset.colors.compactMapValues(Self.archive),
                "backgroundEnabled": preset.backgroundEnabled,
            ]
            // JSON rather than a field-per-key dictionary: adding an option to
            // `Appearance` then needs no serializer change here.
            if let appearance = preset.appearance,
               let data = try? JSONEncoder().encode(appearance) {
                stored["appearance"] = data
            }
            return stored
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
            // Absent for presets saved before appearances were part of one, and
            // for anything that fails to decode — both mean "colors only".
            let appearance = (dict["appearance"] as? Data)
                .flatMap { try? JSONDecoder().decode(Appearance.self, from: $0) }
            return ColorPreset(name: name, colors: colors,
                               backgroundEnabled: dict["backgroundEnabled"] as? Bool ?? false,
                               appearance: appearance)
        }
    }
}
