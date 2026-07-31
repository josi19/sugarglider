import Testing
import Foundation
@testable import Sugarglider

// MARK: - Relative time formatting

extension SugargliderTests {
    @Test func relativeTimeBuckets() {
        #expect(ReadingStore.relative(Date().addingTimeInterval(-5)) == "just now")
        #expect(ReadingStore.relative(Date().addingTimeInterval(-65)) == "1 min ago")
        #expect(ReadingStore.relative(Date().addingTimeInterval(-200)) == "3 min ago")
        #expect(ReadingStore.relative(Date().addingTimeInterval(-3660)) == "1 h ago")
        #expect(ReadingStore.relative(Date().addingTimeInterval(-7320)) == "2 h ago")
    }

    /// The status-bar form: short enough for the menu bar, and it must never
    /// round *up* — claiming more time has passed than actually has would be the
    /// one direction that misleads.
    @Test func compactAgeForTheStatusBar() {
        #expect(ReadingStore.compactAge(Date().addingTimeInterval(-13 * 60)) == "13m")
        #expect(ReadingStore.compactAge(Date().addingTimeInterval(-59 * 60 - 59)) == "59m")
        #expect(ReadingStore.compactAge(Date().addingTimeInterval(-3600 - 30)) == "1h")
        #expect(ReadingStore.compactAge(Date().addingTimeInterval(-50 * 3600)) == "2d")
        #expect(ReadingStore.compactAge(Date().addingTimeInterval(30)) == "0m")   // clock skew
    }
}

// MARK: - Staleness

extension SugargliderTests {
    @Test func isStaleAfterThreshold() {
        let store = ReadingStore(settings: Self.makeSettings())
        #expect(store.isStale == false)   // no reading yet
        store.lastReading = reading(100, minutesAgo: 5)
        #expect(store.isStale == false)
        store.lastReading = reading(100, minutesAgo: 12)   // past the 11 min default
        #expect(store.isStale == true)
    }

    /// The threshold is the user's `staleAfterMinutes`, read live — not a
    /// constant baked into the store, and not a value captured at launch.
    @Test func isStaleFollowsTheConfiguredDelay() {
        let settings = Self.makeSettings()
        let store = ReadingStore(settings: settings)
        store.lastReading = reading(100, minutesAgo: 15)
        #expect(store.isStale == true)          // at the default of 11 min

        settings.staleAfterMinutes = 20
        #expect(store.isStale == false)         // same reading, longer grace period
        settings.staleAfterMinutes = 5
        #expect(store.isStale == true)
    }
}

// MARK: - Delta between readings

extension SugargliderTests {
    @Test func deltaOffIsNil() {
        let settings = Self.makeSettings()
        settings.deltaDisplay = .off
        let store = ReadingStore(settings: settings)
        let now = Date()
        store.lastReading = reading(108, minutesAgo: 0, from: now)
        store.previousReading = reading(90, minutesAgo: 5, from: now)
        #expect(store.deltaText() == nil)
    }

    @Test func deltaNilWithoutPreviousReading() {
        let settings = Self.makeSettings()
        settings.deltaDisplay = .menu
        let store = ReadingStore(settings: settings)
        store.lastReading = reading(108, minutesAgo: 0)
        store.previousReading = nil
        #expect(store.deltaText() == nil)
    }

    @Test func deltaMmolFormatting() {
        let settings = Self.makeSettings()
        settings.deltaDisplay = .menu
        settings.units = .mmol
        let store = ReadingStore(settings: settings)
        let now = Date()
        store.lastReading = reading(108, minutesAgo: 0, from: now)   // 6.0 mmol
        store.previousReading = reading(90, minutesAgo: 5, from: now) // 5.0 mmol
        #expect(store.deltaText() == "+1.0")
    }

    @Test func deltaMgdlFormatting() {
        let settings = Self.makeSettings()
        settings.deltaDisplay = .menu
        settings.units = .mgdl
        let store = ReadingStore(settings: settings)
        let now = Date()
        store.lastReading = reading(108, minutesAgo: 0, from: now)
        store.previousReading = reading(90, minutesAgo: 5, from: now)
        #expect(store.deltaText() == "+18")
    }

    @Test func deltaNegative() {
        let settings = Self.makeSettings()
        settings.deltaDisplay = .menu
        settings.units = .mmol
        let store = ReadingStore(settings: settings)
        let now = Date()
        store.lastReading = reading(90, minutesAgo: 0, from: now)
        store.previousReading = reading(108, minutesAgo: 5, from: now)
        #expect(store.deltaText() == "-1.0")
    }

    @Test func deltaNilWhenGapTooLarge() {
        let settings = Self.makeSettings()
        settings.deltaDisplay = .menu
        let store = ReadingStore(settings: settings)
        let now = Date()
        store.lastReading = reading(108, minutesAgo: 0, from: now)
        store.previousReading = reading(90, minutesAgo: 20, from: now)  // 20 min > 12 min limit
        #expect(store.deltaText() == nil)
    }

    @Test func deltaNilWhenPreviousIsNewer() {
        let settings = Self.makeSettings()
        settings.deltaDisplay = .menu
        let store = ReadingStore(settings: settings)
        let now = Date()
        store.lastReading = reading(108, minutesAgo: 0, from: now)
        store.previousReading = reading(90, minutesAgo: -5, from: now)  // in the future → gap <= 0
        #expect(store.deltaText() == nil)
    }
}

// MARK: - History sizing and coverage

extension SugargliderTests {
    @Test func historyCountFollowsTheSelectedRange() {
        // Sized for a per-minute cadence, so a 5-min site never reaches it.
        #expect(ReadingStore.historyCount(forRangeHours: 6) == 420)
        #expect(ReadingStore.historyCount(forRangeHours: 24) == 1500)
        // …and capped, so the widest window can't pull an unbounded response.
        #expect(ReadingStore.historyCount(forRangeHours: 72) == 2880)
        for hours in AppSettings.rangeHoursLimits {
            let count = ReadingStore.historyCount(forRangeHours: hours)
            #expect(count > hours * 12)      // covers a 5-min cadence with room to spare
            #expect(count <= 2880)
        }
    }

    @Test func coverageComparesAgainstTheRequestedWindow() {
        let now = Date()
        // Nothing fetched yet.
        #expect(ReadingStore.historyCovers(requested: nil, from: now.addingTimeInterval(-3600)) == false)
        // Fetched 6h; a 1h window sits inside it, a 24h one doesn't.
        let asked = now.addingTimeInterval(-6 * 3600)
        #expect(ReadingStore.historyCovers(requested: asked, from: now.addingTimeInterval(-3600)))
        #expect(ReadingStore.historyCovers(requested: asked, from: now.addingTimeInterval(-24 * 3600)) == false)
        // Same window an hour later: its start slid forward, so it stays covered.
        #expect(ReadingStore.historyCovers(requested: asked,
                                           from: now.addingTimeInterval(3600 - 6 * 3600)))
    }

    /// A site with only a few hours of data must not count as uncovered — it
    /// would refetch its whole window on every single call.
    @Test func coverageIgnoresHowMuchDataTheSiteActuallyHad() {
        let now = Date()
        let asked = now.addingTimeInterval(-72 * 3600)
        #expect(ReadingStore.historyCovers(requested: asked, from: now.addingTimeInterval(-72 * 3600)))
    }

    /// The whole point of the incremental scheme: the window is downloaded once,
    /// and every later refresh asks only for what came after the newest entry
    /// already cached.
    @Test func historyAsksForTheWindowOnceThenOnlyForWhatIsNewer() async throws {
        let nowMs = epochMillis(Date())
        let server = try LocalHTTPServer(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs - 300_000)},
             {"sgv":110,"direction":"Flat","date":\(nowMs - 600_000)}]
            """)
        defer { server.stop() }
        let settings = Self.makeSettings()
        settings.baseURL = server.baseURL
        let store = ReadingStore(settings: settings)

        store.refreshHistory(force: true)
        try await waitUntil("the first history fetch") { !store.readings.isEmpty }
        #expect(store.readings.count == 2)
        #expect(store.lastReading?.sgv == 120)          // history keeps the bar in sync
        let windowStart = try #require(store.historyWindowStart)
        #expect(server.requestLines.count == 1)
        #expect(server.requestLines[0].contains("$gt%5D=\(epochMillis(windowStart))"))

        store.refreshHistory(force: true)
        try await waitUntil("the top-up fetch") { server.requestLines.count == 2 }
        let newest = try #require(store.readings.last?.date)
        #expect(server.requestLines[1].contains("$gt%5D=\(epochMillis(newest))"))
        // Re-delivered entries replace rather than duplicate their cached copies.
        #expect(store.readings.count == 2)
    }

    /// Widening the range asks for history that was never fetched, so it has to
    /// trip a refetch. Note what this waits on: the recorded window, not the
    /// request count — the window is only set once the response lands, so
    /// counting requests races the fetch and fails intermittently.
    @Test func wideningTheRangeFetchesTheMissingHistory() async throws {
        let nowMs = epochMillis(Date())
        let server = try LocalHTTPServer(json: """
            [{"sgv":120,"direction":"Flat","date":\(nowMs - 300_000)}]
            """)
        defer { server.stop() }
        let settings = Self.makeSettings()
        settings.baseURL = server.baseURL
        let store = ReadingStore(settings: settings)

        store.refreshHistory(force: true)
        try await waitUntil("the first history fetch") {
            store.coversHistory(from: Date().addingTimeInterval(-6 * 3600))   // the default range
        }
        #expect(store.coversHistory(from: Date().addingTimeInterval(-24 * 3600)) == false)

        settings.rangeHours = 24
        store.ensureHistoryCoverage()        // debounced 400 ms, then bypasses the throttle
        try await waitUntil("the widened window") {
            store.coversHistory(from: Date().addingTimeInterval(-24 * 3600))
        }
        #expect(server.requestLines.count >= 2)
    }

    @Test func reconnectForgetsTheCoveredWindow() {
        let store = ReadingStore(settings: Self.makeSettings())
        store.readings = [reading(100, minutesAgo: 0)]
        store.reconnect()
        #expect(store.historyWindowStart == nil)
        #expect(store.coversHistory(from: Date().addingTimeInterval(-3600)) == false)
    }
}

// MARK: - Reconnect / timer lifecycle

extension SugargliderTests {
    @Test func reconnectClearsCachedState() {
        let store = ReadingStore(settings: Self.makeSettings())
        store.lastReading = reading(100, minutesAgo: 0)
        store.previousReading = reading(90, minutesAgo: 5)
        store.lastError = "boom"
        store.readings = [reading(100, minutesAgo: 0)]
        store.reconnect()   // not configured → refresh()/refreshHistory() no-op, but state still clears
        #expect(store.lastReading == nil)
        #expect(store.previousReading == nil)
        #expect(store.lastError == nil)
        #expect(store.readings.isEmpty)
    }

    @Test func startTimerSetsTimer() {
        let store = ReadingStore(settings: Self.makeSettings())
        #expect(store.timer == nil)      // inert until started
        store.startTimer()
        #expect(store.timer != nil)
        store.timer?.invalidate()
    }

    /// `start()` is where the store subscribes to the settings changes it has to
    /// react to. Without this the app would keep polling a stale URL, ignore a
    /// new refresh interval, and leave a widened chart range unfilled.
    @Test func startSubscribesToTheSettingsItReactsTo() {
        let settings = Self.makeSettings()
        let store = ReadingStore(settings: settings)
        #expect(settings.onConnectionChanged == nil)   // inert until started
        store.start()
        defer { store.timer?.invalidate() }
        #expect(settings.onConnectionChanged != nil)
        #expect(settings.onPollIntervalChanged != nil)
        #expect(settings.onRangeHoursChanged != nil)

        // The connection hook really runs reconnect(). Whitespace keeps the site
        // unconfigured, so the debounced re-fetch can't reach the network.
        store.readings = [reading(100, minutesAgo: 0)]
        settings.baseURL = "   "
        #expect(store.readings.isEmpty)

        // …and the interval hook rebuilds the timer rather than waiting a cycle.
        let first = store.timer
        settings.pollIntervalSeconds = 30
        #expect(store.timer !== first)
    }
}
