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
    private var coverageDebounce: Task<Void, Never>?
    /// Start of the window the last full history fetch asked for — what the
    /// cache is built to cover. See `coversHistory(from:)`.
    private(set) var historyWindowStart: Date?

    /// Readings arrive every ~5 min; flag as stale after two missed cycles.
    static let staleThreshold: TimeInterval = 11 * 60

    /// How far apart two readings may be and still count as one continuous
    /// history — the same threshold the chart uses to break a line on a dropout.
    static let contiguityThreshold: TimeInterval = 15 * 60
    private var pollInterval: TimeInterval { TimeInterval(settings.pollIntervalSeconds) }

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

    /// Rebuilds the poll timer at the current `pollInterval` — called when
    /// `AppSettings.pollIntervalSeconds` changes, so the new interval takes
    /// effect immediately rather than waiting for the next fire.
    func restartTimer() {
        timer?.invalidate()
        startTimer()
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
                // The poll's entries are history too, so folding them in keeps
                // the chart current between history fetches — often making the
                // fetch on the next dropdown open a no-op. Only while they join
                // up with the cache, though: leaving a gap in place preserves
                // the `since` boundary the next top-up needs to fill it.
                if let newest = readings.last, let firstNew = fetched.first,
                   firstNew.date > newest.date,
                   firstNew.date.timeIntervalSince(newest.date) <= Self.contiguityThreshold {
                    merge(fetched)
                }
            } catch {
                guard gen == generation else { return }
                lastError = (error as? NightscoutError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Upper bound on entries per history request. The date filter is what
    /// actually selects the window, so this is only a guard against a site that
    /// uploads far more often than every 5 min (1/min is not unusual): it's
    /// sized for a per-minute cadence, and capped so even a 72h window can't
    /// pull an unbounded response. A normal 5-min site never reaches it — a 6h
    /// window returns ~72 entries whatever this says.
    static func historyCount(forRangeHours hours: Int) -> Int {
        min(hours * 60 + 60, 2880)
    }

    /// Whether the cache was already built for a window reaching back to
    /// `start`, so it only needs topping up at the newest end.
    ///
    /// Deliberately compares against the window that was *requested*, not
    /// against the oldest reading received: a site with nothing older than
    /// yesterday would otherwise look permanently uncovered and refetch its
    /// whole window on every call. Note the comparison also self-heals as time
    /// passes — the recorded start stays put while the window slides forward.
    static func historyCovers(requested: Date?, from start: Date) -> Bool {
        guard let requested else { return false }
        return requested <= start
    }

    func coversHistory(from start: Date) -> Bool {
        Self.historyCovers(requested: historyWindowStart, from: start)
    }

    /// Fetches only what's missing. The first call for a window pulls the whole
    /// thing; afterwards the cache is *topped up* with whatever arrived since
    /// its newest entry, which is normally a handful of readings — or none.
    func refreshHistory(force: Bool) {
        guard settings.isConfigured else { return }
        if !force, let at = historyFetchedAt, Date().timeIntervalSince(at) < 60 { return }
        let windowStart = Date().addingTimeInterval(-Double(settings.rangeHours) * 3600)
        let covered = coversHistory(from: windowStart)
        // Topping up asks for everything after the newest cached entry; a full
        // fetch asks for the window itself. Either way the server does the
        // selecting, so the response carries no entries we already have — and
        // it's never an unfiltered request, not even for a site whose window
        // came back empty (covered, but with no cached entry to top up from).
        let since = (covered ? readings.last?.date : nil) ?? windowStart
        let count = Self.historyCount(forRangeHours: settings.rangeHours)
        let gen = generation
        Task {
            guard let fetched = try? await Nightscout.fetchEntries(
                    count: count, since: since,
                    baseURL: settings.baseURL, token: settings.token),
                  gen == generation else { return }
            historyFetchedAt = Date()
            if !covered { historyWindowStart = windowStart }
            merge(fetched)
        }
    }

    /// Called when the selected range changes: the cache is sized to the window,
    /// so widening it needs history that was never fetched. Debounced, because
    /// dragging the slider walks through every step on the way — and it bypasses
    /// the once-a-minute throttle, since this is a visible gap in the chart
    /// rather than a routine refresh.
    func ensureHistoryCoverage() {
        guard settings.isConfigured else { return }
        let windowStart = Date().addingTimeInterval(-Double(settings.rangeHours) * 3600)
        guard !coversHistory(from: windowStart) else { return }
        coverageDebounce?.cancel()
        coverageDebounce = Task {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            refreshHistory(force: true)
        }
    }

    /// Folds `fetched` into the cache, keyed by timestamp so a re-delivered
    /// entry replaces rather than duplicates its cached copy. Trimmed to the
    /// widest selectable window so a long-running app can't grow the array
    /// without bound.
    private func merge(_ fetched: [Reading]) {
        guard !fetched.isEmpty else { return }
        var byDate = Dictionary(readings.map { ($0.date, $0) }, uniquingKeysWith: { _, new in new })
        for r in fetched { byDate[r.date] = r }
        let cutoff = Date().addingTimeInterval(-Double(AppSettings.rangeHoursLimits.upperBound) * 3600)
        readings = byDate.values.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        // History includes the newest points; keep the bar in sync.
        if let newest = readings.last {
            lastReading = newest
            if readings.count >= 2 { previousReading = readings[readings.count - 2] }
            lastError = nil
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
        historyWindowStart = nil
        coverageDebounce?.cancel()
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
