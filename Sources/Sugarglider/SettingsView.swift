import SwiftUI
import AppKit

/// Settings, presented via SwiftUI's native `Settings` scene (⌘,): a real,
/// non-modal window — edits apply live to `AppSettings`, no Save/Cancel.
/// Each tab is a `.grouped` form (the System Settings look), which scrolls
/// when content outgrows the window.
struct SettingsView: View {
    var settings: AppSettings

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ColorsTab(settings: settings)
                .tabItem { Label("Colors", systemImage: "paintpalette") }
            GlucoseTab(settings: settings)
                .tabItem { Label("Glucose", systemImage: "drop") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 480)
        // NOT `.windowTheme(_:)` here: SwiftUI actively manages the Settings
        // scene window's `NSWindow.appearance` and resets a manual override
        // milliseconds after it's applied. `preferredColorScheme` feeds that
        // same machinery, so SwiftUI sets the window appearance itself —
        // which also retints the AppKit dynamic colors the preview chart
        // draws with. The MenuBarExtra dropdown is the opposite case: it
        // ignores `preferredColorScheme` entirely and needs `.windowTheme`.
        .preferredColorScheme(settings.theme.colorScheme)
    }
}

/// Connection (URL, token, live status probe) plus the basic display options.
private struct GeneralTab: View {
    @Bindable var settings: AppSettings
    @FocusState private var tokenFieldFocused: Bool
    @State private var status: ConnectionStatus = .unconfigured

    private enum ConnectionStatus: Equatable {
        case unconfigured
        case checking
        case connected
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("Nightscout URL", text: $settings.baseURL,
                          prompt: Text("https://your-site.nightscout.app"))
                TextField("Access token", text: tokenText,
                          prompt: Text("e.g. monitor-1a2b3c4d"))
                    .focused($tokenFieldFocused)
                LabeledContent("Status") { statusView }
            } footer: {
                Text("Leave the token empty if your site allows unauthenticated reads.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Theme", selection: $settings.theme) {
                    Text("Automatic").tag(AppSettings.Theme.system)
                    Text("Light").tag(AppSettings.Theme.light)
                    Text("Dark").tag(AppSettings.Theme.dark)
                }
                Picker("Units", selection: $settings.units) {
                    Text("mmol/L").tag(AppSettings.Units.mmol)
                    Text("mg/dL").tag(AppSettings.Units.mgdl)
                }
                Picker("Show delta", selection: $settings.deltaDisplay) {
                    Text("Off").tag(AppSettings.DeltaDisplay.off)
                    Text("In Dropdown").tag(AppSettings.DeltaDisplay.menu)
                    Text("In Dropdown + Menu Bar").tag(AppSettings.DeltaDisplay.menuAndStatusBar)
                }
                LabeledContent("Refresh") {
                    // Wide enough for the 3-digit maximum; out-of-range input
                    // snaps back because the setting clamps on write.
                    intervalField("Every", value: $settings.pollIntervalSeconds,
                                  unit: "seconds", limits: AppSettings.pollIntervalLimits)
                }
                LabeledContent("Stale warning") {
                    intervalField("After", value: $settings.staleAfterMinutes,
                                  unit: "minutes", limits: AppSettings.staleAfterLimits)
                }
            } header: {
                Text("Display")
            } footer: {
                Text("A reading with no successor for the stale delay is marked with ⚠ and its "
                     + "age in the menu bar.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .autocorrectionDisabled()
        // Restarting the task on every URL/token edit cancels the previous
        // probe, so only the latest values ever report a result.
        .task(id: settings.baseURL + "\n" + settings.token) { await checkConnection() }
    }

    /// A "<prefix> [n] <unit>" row, as used by the refresh interval and the stale
    /// delay. The tooltip carries the accepted range; typing outside it snaps
    /// back, since both settings clamp on write.
    private func intervalField(_ prefix: String, value: Binding<Int>,
                               unit: String, limits: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Text(prefix)
            TextField("", value: value, format: AppSettings.wholeNumberFormat)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 36)
            Text(unit)
                .help("\(limits.lowerBound)–\(limits.upperBound) \(unit)")
        }
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .unconfigured:
            Text("Not configured").foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    /// Runs `Nightscout.probe` with the current URL/token — a successful read
    /// proves the URL is valid *and* the token authenticates. Debounced so
    /// probes fire between keystrokes, not on each one.
    private func checkConnection() async {
        guard settings.isConfigured else { status = .unconfigured; return }
        status = .checking
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        let result = await Nightscout.probe(baseURL: settings.baseURL, token: settings.token)
        guard !Task.isCancelled else { return }   // superseded by a newer probe
        switch result {
        case .connected: status = .connected
        case .failed(let message): status = .failed(message)
        }
    }

    /// Shows the token masked ("mo***4d") while the field is unfocused;
    /// clicking in reveals the real value for editing. The setter ignores the
    /// mask itself so a stray commit can never overwrite the stored token.
    private var tokenText: Binding<String> {
        Binding(
            get: { tokenFieldFocused ? settings.token : AppSettings.maskedToken(settings.token) },
            set: { newValue in
                guard newValue != AppSettings.maskedToken(settings.token) else { return }
                settings.token = newValue
            }
        )
    }
}

/// Every configurable chart color and the presets that snapshot them.
/// A live preview chart is pinned above the (scrolling) form: it reads
/// `AppSettings` directly, so every picker edit redraws it immediately. The
/// data is synthetic (`ChartMath.sampleReadings`) — a curve spanning all five
/// zones relative to the current thresholds — never the user's real readings.
private struct ColorsTab: View {
    @Bindable var settings: AppSettings
    @State private var showingSavePreset = false
    @State private var newPresetName = ""
    @State private var previewSliderValue = 0.6

    var body: some View {
        VStack(spacing: 0) {
            preview
            form
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            ChartCanvas(readings: sampleReadings, rangeHours: 3, settings: settings)
                .frame(height: 120)
            // Mirrors the dropdown's range slider purely so the slider color is
            // previewable; it drives local state, not `rangeHours`.
            TintedSlider(value: $previewSliderValue, range: 0...1, tint: settings.sliderColor,
                         accessibilityValueText: "preview only")
                .accessibilityLabel("Range slider color preview")
                .padding(.top, 2)
            Text("Preview — sample data, not your readings")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 8, trailing: 20))
    }

    private var sampleReadings: [Reading] {
        ChartMath.sampleReadings(
            extremeLow: settings.extremeLow, targetLow: settings.targetLow,
            targetHigh: settings.targetHigh, extremeHigh: settings.extremeHigh,
            endingAt: Date()
        )
    }

    private var form: some View {
        Form {
            Section("Color preset") {
                Picker("Preset", selection: presetSelection) {
                    Text("Custom").tag(String?.none)
                    ForEach(settings.colorPresets, id: \.name) { preset in
                        Text(preset.name).tag(String?(preset.name))
                    }
                }
                HStack {
                    Button("Save Current…") {
                        newPresetName = settings.matchingPreset()?.name ?? settings.defaultPresetName()
                        showingSavePreset = true
                    }
                    Button("Delete", role: .destructive) {
                        if let name = settings.matchingPreset()?.name { settings.deleteColorPreset(named: name) }
                    }
                    .disabled(settings.matchingPreset() == nil)
                }
            }
            Section("Zone colors") {
                ColorPicker("Very high", selection: $settings.extremeHighColor)
                ColorPicker("Above optimal", selection: $settings.aboveColor)
                ColorPicker("In range", selection: $settings.inRangeColor)
                ColorPicker("Below optimal", selection: $settings.belowColor)
                ColorPicker("Very low", selection: $settings.extremeLowColor)
                Toggle("Blend line colors", isOn: $settings.blendLineColors)
            }
            Section("Line shading") {
                Toggle("Shade below the line", isOn: $settings.lineShadingEnabled)
                Toggle("Match line color", isOn: $settings.lineShadingUsesLineColor)
                    .disabled(!settings.lineShadingEnabled)
                ColorPicker("Shading color", selection: $settings.lineShadingColor)
                    .disabled(!settings.lineShadingEnabled || settings.lineShadingUsesLineColor)
            }
            Section("Latest reading dot") {
                sizeRow("Dot size", value: $settings.dotRadius, range: AppSettings.dotRadiusLimits)
                sizeRow("Halo size", value: $settings.dotHaloRadius, range: AppSettings.dotHaloRadiusLimits)
                Toggle("Match zone color", isOn: $settings.dotUsesZoneColor)
                ColorPicker("Dot color", selection: $settings.dotColor)
                    .disabled(settings.dotUsesZoneColor)
            }
            Section("Chart") {
                ColorPicker("Range band", selection: $settings.bandColor)
                ColorPicker("Range slider", selection: $settings.sliderColor)
                Toggle("Graph background", isOn: $settings.chartBackgroundEnabled)
                ColorPicker("Background color", selection: $settings.chartBackgroundColor)
            }
            Button("Reset Colors to Default") { settings.resetColors() }
        }
        .formStyle(.grouped)
        // A sheet, not an `.alert`: macOS alerts render only TextFields and
        // Buttons, so a list of existing presets to overwrite can't live there.
        .sheet(isPresented: $showingSavePreset) {
            SavePresetSheet(settings: settings, name: $newPresetName)
        }
    }

    /// A point-size row: a slider plus the live value. Stock `Slider` is fine
    /// here — nothing needs tinting inside Settings. It's continuous with a
    /// rounding binding rather than `step:`, because a stepped macOS slider
    /// draws one tick mark per step and half-point granularity turns the row
    /// into a wall of dots.
    private func sizeRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let halfPoints = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = ($0 * 2).rounded() / 2 }
        )
        return LabeledContent(label) {
            HStack(spacing: 8) {
                Slider(value: halfPoints, in: range)
                Text(String(format: "%g", value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
        }
    }

    /// Selecting a preset applies its colors immediately; the picker's own
    /// selection always reflects whichever saved preset (if any) currently
    /// matches the live colors — there's no separate "selected" state to track.
    private var presetSelection: Binding<String?> {
        Binding(
            get: { settings.matchingPreset()?.name },
            set: { name in
                guard let name, let preset = settings.colorPresets.first(where: { $0.name == name }) else { return }
                settings.apply(preset)
            }
        )
    }
}

/// The save-preset dialog: type a new name, or click an existing preset to
/// overwrite it (the click fills the name field; the button relabels to
/// "Overwrite" whenever the name collides with a saved preset).
private struct SavePresetSheet: View {
    var settings: AppSettings
    @Binding var name: String
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var overwrites: Bool { settings.colorPresets.contains { $0.name == trimmed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save color preset").font(.headline)
            TextField("Name", text: $name)
            if !settings.colorPresets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Or overwrite an existing preset:")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(settings.colorPresets, id: \.name) { preset in
                                Button { name = preset.name } label: {
                                    HStack {
                                        Text(preset.name)
                                        Spacer()
                                        if preset.name == trimmed {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 6)
                                    .background(
                                        preset.name == trimmed ? Color.accentColor.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(overwrites ? "Overwrite" : "Save") {
                    settings.saveColorPreset(settings.currentPreset(name: trimmed))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

/// The optimal *range* (a low–high band) plus the very-low/very-high
/// *thresholds*. Values are edited in the chosen display unit but stored as
/// mg/dL.
private struct GlucoseTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Optimal range") {
                thresholdField("Low", \.targetLow)
                thresholdField("High", \.targetHigh)
            }
            Section("Extreme thresholds") {
                thresholdField("Very low", \.extremeLow)
                thresholdField("Very high", \.extremeHigh)
            }
            // Shown rather than enforced: the fields persist as you type, so
            // clamping them against each other would fight anyone moving a
            // range around. See `AppSettings.thresholdOrderWarning`.
            if let warning = settings.thresholdOrderWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("Until these are in order — very low ≤ low < high ≤ very high — the chart "
                         + "can't color the zones or draw the optimal range.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// One threshold row. The value-based field commits on Return or focus
    /// loss (a text-based binding would reformat on every keystroke and fight
    /// the user's typing) and rejects non-numeric input on its own.
    private func thresholdField(_ label: String, _ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, value: displayValue(keyPath), format: settings.thresholdFormat)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text(settings.units.label).foregroundStyle(.secondary)
            }
        }
    }

    /// An mg/dL-stored threshold exposed in the current display unit.
    private func displayValue(_ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings.units.display(settings[keyPath: keyPath]) },
            set: { settings[keyPath: keyPath] = settings.units.toMgdl($0) }
        )
    }
}

/// Which version is running, where to report a problem, and the one caveat
/// that matters. This tab exists because an `LSUIElement` app has **no app
/// menu** — the usual "About Sugarglider" item simply isn't reachable, so the
/// Settings window is the only place this can live.
private struct AboutTab: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    if let icon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sugarglider").font(.title2.weight(.semibold))
                        Text(AppInfo.versionText)
                            .foregroundStyle(.secondary)
                            // The one string here anyone is ever asked to
                            // repeat back, so let them copy it.
                            .textSelection(.enabled)
                        Text(AppInfo.copyright)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Project") {
                    Link(AppInfo.repositoryLabel, destination: AppInfo.repositoryURL)
                }
                LabeledContent("Report an issue") {
                    Link("GitHub Issues", destination: AppInfo.issuesURL)
                }
                LabeledContent("License") {
                    Link("MIT", destination: AppInfo.licenseURL)
                }
            }
            Section {
                Label {
                    Text("Sugarglider only displays what your Nightscout site reports. It is not a "
                         + "medical device and raises no alarms — don't rely on it to catch a high, "
                         + "a low, or a stopped feed, and don't use it for treatment decisions.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Bundle metadata for the About tab, kept in one place so what Settings shows
/// can only come from the Info.plist `build.sh` writes.
enum AppInfo {
    static let repositoryLabel = "josi19/sugarglider"
    static let repositoryURL = URL(string: "https://github.com/josi19/sugarglider")!
    static let issuesURL = repositoryURL.appending(path: "issues")
    static let licenseURL = repositoryURL.appending(path: "blob/main/LICENSE")

    /// "Version 0.2.0 (73)" from the bundle. A bare `swift build` binary has no
    /// Info.plist at all, so the version keys are missing there rather than
    /// wrong — say so instead of printing a fake number.
    static var versionText: String {
        versionText(short: bundleString("CFBundleShortVersionString"),
                    build: bundleString("CFBundleVersion"))
    }

    static func versionText(short: String?, build: String?) -> String {
        guard let short, !short.isEmpty else { return "Development build" }
        guard let build, !build.isEmpty else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }

    static var copyright: String {
        bundleString("NSHumanReadableCopyright") ?? "© 2026 nevermind.dev"
    }

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
