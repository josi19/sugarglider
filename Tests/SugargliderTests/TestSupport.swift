import Testing
import Foundation
import Darwin
@testable import Sugarglider

/// Root suite for the whole bundle. `@MainActor` because `AppSettings`/
/// `ReadingStore`/views are all main-actor isolated. No shared mutable state
/// to reset between tests — `makeSettings()` gives each test an isolated
/// `UserDefaults` suite instead of resetting the process-wide `.standard`
/// domain, so tests can run in any order with no cross-test bleed.
@Suite @MainActor
struct SugargliderTests {
    /// A fresh `AppSettings` backed by its own throwaway `UserDefaults` suite.
    static func makeSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "SugargliderTests-\(UUID().uuidString)")!)
    }
}

/// A throwaway HTTP/1.1 server bound to the loopback interface, used to exercise
/// `Nightscout.fetchEntries` end-to-end. `Nightscout` builds its own private
/// `URLSession`, so a `URLProtocol` stub can't intercept it — a real socket can.
///
/// Loopback (`127.0.0.1`) binding is deliberate: it never triggers the macOS
/// incoming-connection firewall prompt that an all-interfaces bind can. Each
/// accepted connection gets the same canned status + body, then is closed.
final class LocalHTTPServer {
    let port: UInt16
    private let fd: Int32
    private var stopped = false

    /// Request lines ("GET /path?query HTTP/1.1") as received, so a test can
    /// assert on what the client actually asked for. Written from the serving
    /// thread, read from the test's, hence the lock.
    private static let requestsLock = NSLock()
    nonisolated(unsafe) private static var requestsByPort: [UInt16: [String]] = [:]

    var requestLines: [String] {
        Self.requestsLock.withLock { Self.requestsByPort[port] ?? [] }
    }

    enum ServerError: Error { case socketFailed, bindFailed, listenFailed }

    init(status: Int = 200, json: String) throws {
        let body = Data(json.utf8)
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw ServerError.socketFailed }

        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")   // loopback only
        addr.sin_port = 0                                // OS picks a free port

        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { close(sock); throw ServerError.bindFailed }
        guard listen(sock, 8) == 0 else { close(sock); throw ServerError.listenFailed }

        // Read back the OS-assigned ephemeral port.
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) }
        }
        self.port = UInt16(bigEndian: addr.sin_port)
        self.fd = sock

        // Serve on a background thread. The closure captures only value types, so
        // there's no reference back to `self` (and thus no init-order trouble).
        let serverFD = sock
        let statusCode = status
        let servedPort = self.port
        Thread.detachNewThread {
            while true {
                let client = accept(serverFD, nil, nil)
                if client < 0 { break }              // socket closed by stop() → exit
                var buf = [UInt8](repeating: 0, count: 4096)
                let read_ = read(client, &buf, buf.count)
                if read_ > 0,
                   let request = String(bytes: buf[0..<read_], encoding: .utf8),
                   let line = request.split(separator: "\r\n").first {
                    Self.requestsLock.withLock {
                        Self.requestsByPort[servedPort, default: []].append(String(line))
                    }
                }
                let reason = statusCode == 200 ? "OK"
                    : (statusCode == 500 ? "Internal Server Error" : "Status")
                let head = "HTTP/1.1 \(statusCode) \(reason)\r\n"
                    + "Content-Length: \(body.count)\r\n"
                    + "Content-Type: application/json\r\n"
                    + "Connection: close\r\n\r\n"
                var out = Data(head.utf8); out.append(body)
                out.withUnsafeBytes { raw in
                    var sent = 0
                    while sent < raw.count {
                        let n = write(client, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                        if n <= 0 { break }
                        sent += n
                    }
                }
                close(client)
            }
        }
    }

    /// The base URL a fetch should point at to reach this server.
    var baseURL: String { "http://127.0.0.1:\(port)" }

    func stop() {
        guard !stopped else { return }
        stopped = true
        close(fd)   // unblocks accept() so the serving thread exits
        Self.requestsLock.withLock { Self.requestsByPort[port] = nil }
    }

    deinit { stop() }
}

/// Bridge `Nightscout`'s throwing async API to `Result` for concise tests.
func fetchEntriesAsync(count: Int, since: Date? = nil, baseURL: String,
                       token: String = "") async -> Result<[Reading], Error> {
    do {
        return .success(try await Nightscout.fetchEntries(count: count, since: since,
                                                         baseURL: baseURL, token: token))
    } catch { return .failure(error) }
}

/// Polls `condition` until it holds, then returns; records an issue after ~2s.
/// `ReadingStore`'s fetches run in detached `Task`s with no handle to await, so
/// an integration test has to observe the resulting state instead.
@MainActor
func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting for \(what)")
}

/// Epoch milliseconds, rounded the way `Nightscout.fetchEntries` rounds them.
func epochMillis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
}

/// A `Reading` at a fixed offset before a shared "now", for deterministic tests.
func reading(_ sgv: Int, direction: String = "Flat", minutesAgo: Double = 0,
             from now: Date = Date()) -> Reading {
    Reading(sgv: sgv, direction: direction, date: now.addingTimeInterval(-minutesAgo * 60))
}
