import SwiftUI

/// The content shown when the status-bar item is clicked: the chart, range
/// slider, current reading, and action buttons.
struct MenuBarContentView: View {
    var settings: AppSettings
    var store: ReadingStore
    @Environment(\.openSettings) private var openSettings

    private let contentWidth: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartCanvas(readings: store.readings, rangeHours: settings.rangeHours, settings: settings)
                .frame(width: contentWidth, height: 160)

            HStack(spacing: 8) {
                // TintedSlider, not SwiftUI's Slider: the stock control's track
                // ignores every tint mechanism macOS offers — see TintedSlider.
                TintedSlider(value: rangeBinding, range: 2...48, step: 2,
                             tint: settings.sliderColor,
                             accessibilityValueText: "\(settings.rangeHours) hours")
                    .accessibilityLabel("Chart range")
                Text("\(settings.rangeHours) h")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(width: contentWidth)

            Divider().frame(width: contentWidth)

            VStack(alignment: .leading, spacing: 2) {
                readingRow
                Text(ageText).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Divider().frame(width: contentWidth)

            HStack(spacing: 8) {
                iconButton("arrow.clockwise", label: "Refresh", shortcut: "r") {
                    store.refresh()
                    store.refreshHistory(force: true)
                }
                iconButton("gearshape", label: "Settings…", shortcut: ",") { showSettings() }
                Spacer()
                iconButton("power", label: "Quit", shortcut: "q") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
            .frame(width: contentWidth)
        }
        .padding(18)
        .onAppear { store.refreshHistory(force: false) }
        .windowTheme(settings.theme)
    }

    /// An action button shown as a symbol only — so the label survives just as
    /// the tooltip and the accessibility name.
    private func iconButton(_ symbol: String, label: String, shortcut: KeyEquivalent,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
        }
        .keyboardShortcut(shortcut)
        .help(label)
        .accessibilityLabel(label)
    }

    private var rangeBinding: Binding<Double> {
        Binding(get: { Double(settings.rangeHours) }, set: { settings.rangeHours = Int($0) })
    }

    /// Opens Settings in front *and key*. An accessory (LSUIElement) app is
    /// normally inactive, so the window must be activated explicitly — and a
    /// window that is merely ordered front without key status silently ignores
    /// all typing (text fields can't take focus; mouse-driven controls still
    /// work). The window is created asynchronously, so poll briefly for it.
    private func showSettings() {
        NSApp.activate()
        openSettings()
        Task { @MainActor in
            for _ in 0..<20 {
                if let window = NSApp.windows.first(where: {
                    $0.identifier?.rawValue.hasPrefix("com_apple_SwiftUI_Settings") == true
                }) {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }

    @ViewBuilder private var readingRow: some View {
        if !settings.isConfigured {
            Text("Not configured").font(.system(size: 13)).foregroundStyle(.secondary)
        } else if let r = store.lastReading {
            (valueText(r) + arrowText(r) + deltaText)
        } else if store.lastError != nil {
            Text("No reading yet").font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            Text("Loading…").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func valueText(_ r: Reading) -> Text {
        Text("\(r.text(in: settings.units)) \(settings.units.label)")
            .font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
    }

    private func arrowText(_ r: Reading) -> Text {
        guard !r.trendArrow.isEmpty else { return Text("") }
        return Text(" \(r.trendArrow)").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
    }

    private var deltaText: Text {
        guard let delta = store.deltaText() else { return Text("") }
        return Text("  (\(delta))").font(.system(size: 13)).foregroundStyle(.secondary)
    }

    private var ageText: String {
        guard settings.isConfigured else { return "Open Settings to add your Nightscout URL" }
        if let r = store.lastReading {
            var age = "Reading \(ReadingStore.relative(r.date))" + (store.isStale ? " (stale)" : "")
            if let err = store.lastError { age += " — \(err)" }  // surface errors on the age line
            return age
        } else if let err = store.lastError {
            return err
        }
        return ""
    }
}
