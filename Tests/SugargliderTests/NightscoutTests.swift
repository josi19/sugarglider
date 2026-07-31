import Testing
import Foundation
@testable import Sugarglider

/// The `NightscoutError` message for a failed result (each case has a unique one),
/// or nil on success — a terse way to assert which error occurred.
func errorText<T>(_ result: Result<T, Error>) -> String? {
    if case .failure(let e) = result {
        return (e as? NightscoutError)?.errorDescription ?? e.localizedDescription
    }
    return nil
}

func successReadings(_ result: Result<[Reading], Error>) -> [Reading]? {
    if case .success(let r) = result { return r }
    return nil
}

// MARK: - Error paths that need no network

extension SugargliderTests {
    @Test func fetchNotConfigured() async {
        #expect(errorText(await fetchEntriesAsync(count: 1, baseURL: "")) == "Not configured")
    }

    @Test func fetchBadURL() async {
        // embedded space → URLComponents fails
        #expect(errorText(await fetchEntriesAsync(count: 1, baseURL: "http://exa mple.com")) == "Invalid URL")
    }
}

// MARK: - Full request/response against a loopback server

extension SugargliderTests {
    @Test func fetchSuccessParsesAndSortsAscending() async throws {
        let server = try LocalHTTPServer(json: """
            [{"sgv":150,"direction":"Flat","date":1700000300000},
             {"sgv":100,"direction":"FortyFiveUp","date":1700000000000}]
            """)
        defer { server.stop() }

        let readings = try #require(successReadings(await fetchEntriesAsync(count: 10, baseURL: server.baseURL)))
        #expect(readings.count == 2)
        #expect(readings[0].sgv == 100)                 // earlier date sorts first
        #expect(readings[0].direction == "FortyFiveUp")
        #expect(readings[0].date.timeIntervalSince1970 == 1_700_000_000)  // ms → s
        #expect(readings[1].sgv == 150)
    }

    /// Each field is decoded on its own (`try?` per key), so one unusable row
    /// costs only that row — a strict `Decodable` would fail the whole response.
    @Test func fetchSkipsMalformedRows() async throws {
        let server = try LocalHTTPServer(json: """
            [{"sgv":100,"direction":"Flat","date":1700000000000},
             {"direction":"Flat","date":1700000100000},
             {"sgv":110,"date":1700000200000},
             {"sgv":"bad","date":1700000300000},
             {"sgv":120,"direction":null,"date":null},
             {}]
            """)
        defer { server.stop() }

        let readings = try #require(successReadings(await fetchEntriesAsync(count: 10, baseURL: server.baseURL)))
        #expect(readings.count == 2)               // rows missing sgv/date, or with a non-numeric sgv
        #expect(readings[0].sgv == 100)
        #expect(readings[1].sgv == 110)
        #expect(readings[1].direction == "")       // missing direction defaults to ""
    }

    /// `sgv` is read as a `Double` and rounded: some uploaders report fractional
    /// mg/dL, and those readings used to be dropped as malformed.
    @Test func fetchRoundsFractionalSgv() async throws {
        let server = try LocalHTTPServer(json: """
            [{"sgv":100.4,"direction":"Flat","date":1700000000000},
             {"sgv":100.5,"direction":"Flat","date":1700000100000}]
            """)
        defer { server.stop() }

        let readings = try #require(successReadings(await fetchEntriesAsync(count: 10, baseURL: server.baseURL)))
        #expect(readings.map(\.sgv) == [100, 101])
    }

    @Test func fetchEmptyArrayIsEmptyError() async throws {
        let server = try LocalHTTPServer(json: "[]")
        defer { server.stop() }
        #expect(errorText(await fetchEntriesAsync(count: 10, baseURL: server.baseURL)) == "No readings")
    }

    /// "Nothing new" is the expected answer for an incremental top-up, so an
    /// empty response must not be an error when `since` is set.
    @Test func fetchSinceToleratesEmptyResponse() async throws {
        let server = try LocalHTTPServer(json: "[]")
        defer { server.stop() }
        let readings = try #require(successReadings(
            await fetchEntriesAsync(count: 10, since: Date(), baseURL: server.baseURL)))
        #expect(readings.isEmpty)
    }

    @Test func fetchSinceSendsTheDateFilterInMilliseconds() async throws {
        let server = try LocalHTTPServer(json: """
            [{"sgv":100,"direction":"Flat","date":1700000400000}]
            """)
        defer { server.stop() }

        let since = Date(timeIntervalSince1970: 1_700_000_000)
        _ = await fetchEntriesAsync(count: 10, since: since, baseURL: server.baseURL)
        let line = try #require(server.requestLines.first)
        // Percent-encoded by URLComponents; Nightscout's query parser decodes it.
        #expect(line.contains("date%5D%5B$gt%5D=1700000000000")
                || line.contains("date][$gt]=1700000000000"))
        #expect(line.contains("count=10"))
    }

    /// The plain fetch must stay plain — no stray filter that would make the
    /// first, full history request return only recent entries.
    @Test func fetchWithoutSinceSendsNoDateFilter() async throws {
        let server = try LocalHTTPServer(json: """
            [{"sgv":100,"direction":"Flat","date":1700000400000}]
            """)
        defer { server.stop() }

        _ = await fetchEntriesAsync(count: 10, baseURL: server.baseURL)
        let line = try #require(server.requestLines.first)
        #expect(!line.contains("gt"))
    }

    @Test func fetchNonJSONIsDecodeError() async throws {
        let server = try LocalHTTPServer(json: "not json at all")
        defer { server.stop() }
        #expect(errorText(await fetchEntriesAsync(count: 10, baseURL: server.baseURL)) == "Bad response")
    }

    @Test func fetchJSONObjectInsteadOfArrayIsDecodeError() async throws {
        let server = try LocalHTTPServer(json: "{\"foo\":1}")
        defer { server.stop() }
        #expect(errorText(await fetchEntriesAsync(count: 10, baseURL: server.baseURL)) == "Bad response")
    }

    @Test func fetchHTTPErrorStatus() async throws {
        let server = try LocalHTTPServer(status: 500, json: "[]")
        defer { server.stop() }
        #expect(errorText(await fetchEntriesAsync(count: 10, baseURL: server.baseURL)) == "HTTP 500")
    }

    /// A trailing slash on the site URL and a blank token must not reach the query.
    @Test func fetchNormalizesBaseURLAndOmitsABlankToken() async throws {
        let server = try LocalHTTPServer(json: #"[{"sgv":100,"direction":"Flat","date":1700000400000}]"#)
        defer { server.stop() }

        _ = await fetchEntriesAsync(count: 10, baseURL: server.baseURL + "///", token: "   ")
        let line = try #require(server.requestLines.first)
        #expect(line.contains("/api/v1/entries/sgv.json"))
        #expect(!line.contains("token"))
    }
}

// MARK: - Connection probe (the Settings status indicator)

extension SugargliderTests {
    @Test func probeConnectedWithReadings() async throws {
        let server = try LocalHTTPServer(json: #"[{"sgv":100,"direction":"Flat","date":1700000000000}]"#)
        defer { server.stop() }
        let result = await Nightscout.probe(baseURL: server.baseURL, token: "")
        #expect(result == .connected)
    }

    @Test func probeConnectedWhenSiteHasNoReadings() async throws {
        let server = try LocalHTTPServer(json: "[]")
        defer { server.stop() }
        let result = await Nightscout.probe(baseURL: server.baseURL, token: "")
        #expect(result == .connected)   // credentials work; there's just no data
    }

    @Test func probeUnauthorizedIsAuthFailure() async throws {
        let server = try LocalHTTPServer(status: 401, json: "[]")
        defer { server.stop() }
        let result = await Nightscout.probe(baseURL: server.baseURL, token: "wrong")
        #expect(result == .failed("Authentication failed — check the token"))
    }

    @Test func probeForbiddenIsAuthFailure() async throws {
        let server = try LocalHTTPServer(status: 403, json: "[]")
        defer { server.stop() }
        let result = await Nightscout.probe(baseURL: server.baseURL, token: "wrong")
        #expect(result == .failed("Authentication failed — check the token"))
    }

    @Test func probeServerErrorReportsStatus() async throws {
        let server = try LocalHTTPServer(status: 500, json: "[]")
        defer { server.stop() }
        let result = await Nightscout.probe(baseURL: server.baseURL, token: "")
        #expect(result == .failed("HTTP 500"))
    }

    @Test func probeInvalidURL() async {
        let result = await Nightscout.probe(baseURL: "http://exa mple.com", token: "")
        #expect(result == .failed("Invalid URL"))
    }
}
