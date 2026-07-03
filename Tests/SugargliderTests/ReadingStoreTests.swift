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
}

// MARK: - Staleness

extension SugargliderTests {
    @Test func isStaleAfterThreshold() {
        let store = ReadingStore(settings: Self.makeSettings())
        #expect(store.isStale == false)   // no reading yet
        store.lastReading = reading(100, minutesAgo: 5)
        #expect(store.isStale == false)
        store.lastReading = reading(100, minutesAgo: 12)   // past the 11 min threshold
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
}
