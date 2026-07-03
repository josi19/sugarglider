import SwiftUI

@main
struct SugargliderApp: App {
    @State private var settings: AppSettings
    @State private var store: ReadingStore

    init() {
        let settings = AppSettings()
        let store = ReadingStore(settings: settings)
        settings.onConnectionChanged = { [weak store] in store?.reconnect() }
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        store.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(settings: settings, store: store)
        } label: {
            MenuBarLabel(settings: settings, store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
        }
        .windowResizability(.contentSize)
    }
}

/// The status-bar item's own title: value, an enlarged trend arrow, the
/// bracketed delta (if enabled for the bar), and a staleness warning glyph.
private struct MenuBarLabel: View {
    var settings: AppSettings
    var store: ReadingStore

    var body: some View {
        Group {
            if !settings.isConfigured {
                Text("CGM ⚙")
            } else if let r = store.lastReading {
                barText(r)
            } else if store.lastError != nil {
                Text("CGM ⚠")
            } else {
                Text("CGM …")
            }
        }
        .font(.system(size: 13, design: .monospaced))
    }

    private func barText(_ r: Reading) -> Text {
        var t = Text(r.text(in: settings.units)).font(.system(size: 13, design: .monospaced))
        if !r.trendArrow.isEmpty {
            t = t + Text(" \(r.trendArrow)").font(.system(size: 15, weight: .medium))
        }
        if settings.deltaDisplay == .menuAndStatusBar, let delta = store.deltaText() {
            t = t + Text("  (\(delta))").font(.system(size: 13, design: .monospaced))
        }
        if store.isStale {
            t = t + Text(" ⚠").font(.system(size: 13, design: .monospaced))
        }
        return t
    }
}
