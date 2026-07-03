import SwiftUI

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
        }
        .frame(width: 500, height: 480)
        .windowTheme(settings.theme)
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
            Section("Display") {
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
            }
        }
        .formStyle(.grouped)
        .autocorrectionDisabled()
        // Restarting the task on every URL/token edit cancels the previous
        // probe, so only the latest values ever report a result.
        .task(id: settings.baseURL + "\n" + settings.token) { await checkConnection() }
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
private struct ColorsTab: View {
    @Bindable var settings: AppSettings
    @State private var showingSavePreset = false
    @State private var newPresetName = ""

    var body: some View {
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
            Section("Chart") {
                ColorPicker("Range band", selection: $settings.bandColor)
                ColorPicker("Slider", selection: $settings.sliderColor)
                Toggle("Graph background", isOn: $settings.chartBackgroundEnabled)
                ColorPicker("Background color", selection: $settings.chartBackgroundColor)
            }
            Button("Reset Colors to Default") { settings.resetColors() }
        }
        .formStyle(.grouped)
        .alert("Save color preset", isPresented: $showingSavePreset) {
            TextField("Name", text: $newPresetName)
            Button("Save") {
                let name = newPresetName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                settings.saveColorPreset(settings.currentPreset(name: name))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a new name, or pick an existing one to overwrite it.")
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
        }
        .formStyle(.grouped)
    }

    /// One threshold row. The value-based field commits on Return or focus
    /// loss (a text-based binding would reformat on every keystroke and fight
    /// the user's typing) and rejects non-numeric input on its own.
    private func thresholdField(_ label: String, _ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, value: displayValue(keyPath), format: thresholdFormat)
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

    /// mmol/L shows one decimal; mg/dL is integral.
    private var thresholdFormat: FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(0...(settings.units == .mmol ? 1 : 0)))
    }
}
