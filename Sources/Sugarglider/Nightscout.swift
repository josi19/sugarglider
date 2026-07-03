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

    /// Fetch the most recent SGV entry.
    static func fetchLatest(baseURL: String, token: String) async throws -> Reading {
        guard let latest = try await fetchEntries(count: 1, baseURL: baseURL, token: token).last else {
            throw NightscoutError.empty
        }
        return latest
    }

    /// Fetch up to `count` recent SGV entries, returned oldest-first so they can
    /// be plotted left-to-right.
    static func fetchEntries(count: Int, baseURL: String, token: String) async throws -> [Reading] {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { throw NightscoutError.notConfigured }
        while base.hasSuffix("/") { base.removeLast() }

        guard var comps = URLComponents(string: base + "/api/v1/entries/sgv.json") else {
            throw NightscoutError.badURL
        }
        var items = [URLQueryItem(name: "count", value: String(count))]
        let token = token.trimmingCharacters(in: .whitespaces)
        if !token.isEmpty { items.append(URLQueryItem(name: "token", value: token)) }
        comps.queryItems = items

        guard let url = comps.url else { throw NightscoutError.badURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NightscoutError.http(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NightscoutError.decode
        }
        // `date` is epoch milliseconds; `sgv` is mg/dL. Skip malformed rows.
        let readings = json.compactMap { entry -> Reading? in
            guard let sgv = entry["sgv"] as? Int,
                  let ms = entry["date"] as? Double else { return nil }
            return Reading(
                sgv: sgv,
                direction: entry["direction"] as? String ?? "",
                date: Date(timeIntervalSince1970: ms / 1000.0)
            )
        }.sorted { $0.date < $1.date }

        guard !readings.isEmpty else { throw NightscoutError.empty }
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
