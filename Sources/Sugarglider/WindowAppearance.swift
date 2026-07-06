import SwiftUI
import AppKit

extension View {
    /// Applies the user's theme override to the hosting `NSWindow`'s
    /// `appearance` (nil follows the system). This is the right mechanism for
    /// the `MenuBarExtra(.window)` dropdown:
    ///
    /// - `preferredColorScheme` never reaches the borderless panel that
    ///   `MenuBarExtra(.window)` creates, so the dropdown would ignore the
    ///   theme entirely.
    /// - Setting the window appearance retints *everything* consistently —
    ///   the glass material, SwiftUI semantic styles (`.primary` etc.), and
    ///   AppKit dynamic colors (`.labelColor`, `.separatorColor`) the chart
    ///   draws with. An environment-only override would leave the AppKit
    ///   colors resolving against the system appearance.
    /// - `NSApp.appearance` is deliberately NOT set: that would also retint
    ///   the status-bar item, which must follow the menu bar to stay legible.
    ///
    /// It does NOT work for the `Settings` scene window: SwiftUI manages that
    /// window's `appearance` itself and resets a manual override milliseconds
    /// after it's applied (verified via KVO on macOS 26). The Settings window
    /// uses `preferredColorScheme` instead — SwiftUI's own machinery then
    /// sets the window-level appearance, so AppKit dynamic colors follow too.
    func windowTheme(_ theme: AppSettings.Theme) -> some View {
        background(WindowThemeApplier(appearance: theme.nsAppearance))
    }
}

/// Zero-size helper view that forwards the desired appearance to whatever
/// window it ends up in. Re-applied on window attach (the dropdown's content
/// view is recreated each time it opens) and on every theme change.
private struct WindowThemeApplier: NSViewRepresentable {
    var appearance: NSAppearance?

    func makeNSView(context: Context) -> ApplierView { ApplierView() }

    func updateNSView(_ view: ApplierView, context: Context) {
        view.desired = appearance
    }

    final class ApplierView: NSView {
        var desired: NSAppearance? {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window, window.appearance?.name != desired?.name else { return }
            window.appearance = desired
        }
    }
}
