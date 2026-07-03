import Foundation

/// Live, transient reading state — decoupled from persisted `AppSettings`.
/// Polls Nightscout on a 60s timer and exposes the latest/previous reading,
/// chart history, and any error, all reactively via Observation. `init` is
/// deliberately inert (no timer, no network) so tests can construct a store
/// and exercise its formatting/delta logic without side effects; `start()` is
/// the explicit trigger the real app calls once at launch.
@MainActor
@Observable
final class ReadingStore {
    private let settings: AppSettings

    var lastReading: Reading?
    var previousReading: Reading?
    var lastError: String?
    var readings: [Reading] = []      // history for the chart
    private var historyFetchedAt: Date?
    private(set) var timer: Timer?

    /// Bumped by `reconnect()`. In-flight fetches capture the value at launch
    /// and discard their response if it changed — otherwise a slow response
    /// from the *previous* Nightscout site could land after a URL change and
    /// repopulate the store with the wrong site's data.
    private var generation = 0
    private var reconnectDebounce: Task<Void, Never>?

    /// Readings arrive every ~5 min; flag as stale after two missed cycles.
    static let staleThreshold: TimeInterval = 11 * 60
    private let pollInterval: TimeInterval = 60

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Starts polling. Called once from the app's launch path.
    func start() {
        if settings.isConfigured { refresh() }
        startTimer()
    }

    func startTimer() {
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Generous tolerance lets macOS coalesce the wakeup, cutting energy use.
        t.tolerance = pollInterval * 0.5
        // `.common` keeps the poll firing during event tracking (e.g. while
        // the range slider is being dragged), where `.default`-mode timers stall.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard settings.isConfigured else { return }
        // Two readings so the delta to the previous value is always available.
        let gen = generation
        Task {
            do {
                let fetched = try await Nightscout.fetchEntries(count: 2, baseURL: settings.baseURL, token: settings.token)
                guard gen == generation else { return }
                lastReading = fetched.last
                if fetched.count >= 2 { previousReading = fetched[fetched.count - 2] }
                lastError = nil
            } catch {
                guard gen == generation else { return }
                lastError = (error as? NightscoutError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func refreshHistory(force: Bool) {
        guard settings.isConfigured else { return }
        if !force, let at = historyFetchedAt, Date().timeIntervalSince(at) < 60 { return }
        // 48h at one reading per 5 min ≈ 576; a margin covers jitter.
        let gen = generation
        Task {
            guard let fetched = try? await Nightscout.fetchEntries(count: 600, baseURL: settings.baseURL, token: settings.token),
                  gen == generation else { return }
            historyFetchedAt = Date()
            readings = fetched
            // History includes the newest points; keep the bar in sync.
            if let newest = fetched.last {
                lastReading = newest
                if fetched.count >= 2 { previousReading = fetched[fetched.count - 2] }
                lastError = nil
            }
        }
    }

    /// Drop cached state and re-fetch — called when the connection info
    /// (base URL / token) changes, since a new site invalidates everything.
    /// State clears immediately, but the re-fetch is debounced: Settings is
    /// non-modal, so this fires on *every keystroke* while the URL/token field
    /// is edited — without the delay each character would trigger two requests
    /// against a half-typed URL.
    func reconnect() {
        generation += 1
        lastReading = nil
        previousReading = nil
        lastError = nil
        readings = []
        historyFetchedAt = nil
        reconnectDebounce?.cancel()
        reconnectDebounce = Task {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            refresh()
            refreshHistory(force: true)
        }
    }

    /// Signed change since the previous reading in the current unit, e.g. "+0.3"
    /// (mmol/L) or "+5" (mg/dL). Nil when delta is off, there's no prior reading,
    /// or the gap is too large to be a meaningful consecutive delta.
    func deltaText() -> String? {
        guard settings.deltaDisplay != .off,
              let cur = lastReading, let prev = previousReading else { return nil }
        let gap = cur.date.timeIntervalSince(prev.date)
        guard gap > 0, gap < 12 * 60 else { return nil }
        let units = settings.units
        let d = cur.value(in: units) - prev.value(in: units)
        return units == .mmol ? String(format: "%+.1f", d) : String(format: "%+.0f", d)
    }

    var isStale: Bool {
        guard let r = lastReading else { return false }
        return Date().timeIntervalSince(r.date) > Self.staleThreshold
    }

    /// Compact relative time, e.g. "just now", "3 min ago", "2 h ago".
    static func relative(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 30 { return "just now" }
        if secs < 90 { return "1 min ago" }
        if secs < 3600 { return "\(secs / 60) min ago" }
        if secs < 7200 { return "1 h ago" }
        return "\(secs / 3600) h ago"
    }
}
