import Foundation

/// One glucose reading from Nightscout. `sgv` is always mg/dL (Nightscout's
/// internal unit); we convert to mmol/L for display.
struct Reading {
    let sgv: Int
    let direction: String
    let date: Date

    /// Reading value in the given display unit.
    func value(in units: AppSettings.Units) -> Double { units.value(fromMgdl: sgv) }
    /// Formatted reading, e.g. "5.2" (mmol/L) or "94" (mg/dL).
    func text(in units: AppSettings.Units) -> String { units.text(fromMgdl: sgv) }

    /// Trend arrow matching Nightscout's `direction` field. Doubles use paired
    /// single glyphs (`↑↑`) rather than `⇈`/`⇊`, which render thin and small.
    var trendArrow: String {
        switch direction {
        case "DoubleUp":      return "↑↑"
        case "SingleUp":      return "↑"
        case "FortyFiveUp":   return "↗"
        case "Flat":          return "→"
        case "FortyFiveDown": return "↘"
        case "SingleDown":    return "↓"
        case "DoubleDown":    return "↓↓"
        default:              return ""   // NONE / NOT COMPUTABLE / RATE OUT OF RANGE
        }
    }
}

enum NightscoutError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int)
    case empty
    case decode

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Not configured"
        case .badURL:        return "Invalid URL"
        case .http(let c):   return "HTTP \(c)"
        case .empty:         return "No readings"
        case .decode:        return "Bad response"
        }
    }
}

/// A pure HTTP client with no hidden dependency on app state — connection info
/// is passed in by the caller (`ReadingStore`, which reads it from
/// `AppSettings`) rather than reached for globally. `@MainActor` because the
/// only caller is main-actor `ReadingStore`; the network wait itself still
/// happens off the main thread inside `URLSession`.
@MainActor
enum Nightscout {
    /// One shared, lightweight session. 15s timeout keeps a stalled request
    /// from pinning the timer, and `waitsForConnectivity` avoids spurious
    /// failures when the network blips.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = false
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: cfg)
    }()

    /// Reused across requests; every decode happens on the main actor, so one
    /// instance is enough.
    private static let decoder = JSONDecoder()

    /// One raw row of `entries/sgv.json`. Decoded leniently — each field
    /// individually — so a single odd row can't fail the whole response the way
    /// a strict `Decodable` would: a missing `direction` is normal, and sites
    /// exist that emit a non-numeric `sgv`. `sgv` is read as a `Double` because
    /// some uploaders report fractional mg/dL.
    private struct Entry: Decodable {
        let sgv: Double?
        let direction: String?
        let millis: Double?

        private enum CodingKeys: String, CodingKey { case sgv, direction, date }

        init(from decoder: any Decoder) throws {
            let row = try decoder.container(keyedBy: CodingKeys.self)
            sgv = try? row.decodeIfPresent(Double.self, forKey: .sgv)
            direction = try? row.decodeIfPresent(String.self, forKey: .direction)
            millis = try? row.decodeIfPresent(Double.self, forKey: .date)
        }

        /// Nil for a row without the two fields a plottable reading needs.
        var reading: Reading? {
            guard let sgv, let millis else { return nil }
            return Reading(sgv: Int(sgv.rounded()), direction: direction ?? "",
                           date: Date(timeIntervalSince1970: millis / 1000))
        }
    }

    /// Fetch up to `count` recent SGV entries, returned oldest-first so they can
    /// be plotted left-to-right.
    ///
    /// `since` restricts the response to entries *newer* than that instant
    /// (Nightscout's Mongo-style `find[date][$gt]` on the epoch-millisecond
    /// `date` field), which is what makes topping a cached history up cheap
    /// instead of re-downloading the whole window. An empty response is an
    /// error only for a full fetch: with `since` set, "nothing new since then"
    /// is the normal, expected answer.
    static func fetchEntries(count: Int, since: Date? = nil,
                             baseURL: String, token: String) async throws -> [Reading] {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { throw NightscoutError.notConfigured }
        while base.hasSuffix("/") { base.removeLast() }

        guard var comps = URLComponents(string: base + "/api/v1/entries/sgv.json") else {
            throw NightscoutError.badURL
        }
        var items = [URLQueryItem(name: "count", value: String(count))]
        if let since {
            let ms = (since.timeIntervalSince1970 * 1000).rounded()
            items.append(URLQueryItem(name: "find[date][$gt]", value: String(Int64(ms))))
        }
        let token = token.trimmingCharacters(in: .whitespaces)
        if !token.isEmpty { items.append(URLQueryItem(name: "token", value: token)) }
        comps.queryItems = items

        guard let url = comps.url else { throw NightscoutError.badURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NightscoutError.http(http.statusCode)
        }
        guard let entries = try? decoder.decode([Entry].self, from: data) else {
            throw NightscoutError.decode
        }
        let readings = entries.compactMap(\.reading).sorted { $0.date < $1.date }

        guard !readings.isEmpty || since != nil else { throw NightscoutError.empty }
        return readings
    }

    /// Result of a connection probe: can the site be reached and read with
    /// these credentials?
    enum ProbeResult: Equatable {
        case connected
        case failed(String)
    }

    /// Check whether `baseURL`/`token` identify a reachable Nightscout site
    /// the token can read from. A site with no readings yet still counts as
    /// connected — the credentials work, there's just no data.
    static func probe(baseURL: String, token: String) async -> ProbeResult {
        do {
            _ = try await fetchEntries(count: 1, baseURL: baseURL, token: token)
            return .connected
        } catch NightscoutError.empty {
            return .connected
        } catch NightscoutError.http(401), NightscoutError.http(403) {
            return .failed("Authentication failed — check the token")
        } catch let error as NightscoutError {
            return .failed(error.errorDescription ?? "Connection failed")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
