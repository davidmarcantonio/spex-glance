import Foundation

public enum KalshiError: Error, LocalizedError {
    case http(Int, String)
    case transport(String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .http(let code, let msg):
            switch code {
            case 401: return "Kalshi rejected the key (401). Check the Key ID and that the key is still active."
            case 403: return "Forbidden (403). The key may lack read access."
            case 429: return "Rate limited (429). Try again in a minute."
            default: return "Kalshi returned \(code): \(msg)"
            }
        case .transport(let s): return "Network error: \(s)"
        case .notConnected: return "No Kalshi key on file. Open the app and tap Connect Kalshi."
        }
    }
}

/// Minimal, read-only Kalshi Trade API v2 client. Every request is signed with the
/// credential's private key; no write endpoints exist here on purpose.
public struct KalshiClient: Sendable {
    public let credential: KalshiCredential
    private let session: URLSession

    public init(credential: KalshiCredential, session: URLSession = .shared) {
        self.credential = credential
        self.session = session
    }

    // MARK: Endpoints

    public func balance() async throws -> BalanceResponse {
        try await get("/portfolio/balance")
    }

    /// The account's API keys and their scopes.
    public func apiKeys() async throws -> [ApiKeyInfo] {
        let r: ApiKeysResponse = try await get("/api_keys")
        return r.api_keys
    }

    /// Verdict on whether *this* credential's key is a plain Read key.
    public enum KeyScopeCheck: Sendable, Equatable {
        /// Only "Read" is checked on Kalshi's key page.
        case readOnly
        /// Something under Granular Access is checked (Trade / Transfers / Accept block trades), or Read is missing.
        case notReadOnly(extras: [String], missingRead: Bool)
        case unknown(String)
    }
    public func checkOwnKeyScope() async -> KeyScopeCheck {
        do {
            let keys = try await apiKeys()
            guard let mine = keys.first(where: { $0.api_key_id.lowercased() == credential.keyID.lowercased() }) else {
                return .unknown("Kalshi didn't list this key ID")
            }
            if mine.isReadOnlyKey { return .readOnly }
            return .notReadOnly(extras: Array(Set(mine.disallowedScopes)).sorted(), missingRead: !mine.hasReadScope)
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    /// One sentence a person can act on, for the wizard and the launch banner.
    public static func scopeProblem(extras: [String], missingRead: Bool) -> String {
        var parts: [String] = []
        if !extras.isEmpty { parts.append("has \(extras.joined(separator: ", ")) checked") }
        if missingRead { parts.append("doesn't have Read all data checked") }
        return "This key " + parts.joined(separator: " and ") + ". Spex Glance only accepts a key with Read all data checked and nothing else — on Kalshi, delete it and create a new key that way."
    }

    /// Only positions with non-zero contracts.
    public func openPositions() async throws -> [MarketPosition] {
        var all: [MarketPosition] = []
        var cursor: String? = nil
        repeat {
            var q = ["count_filter": "position", "limit": "200"]
            if let c = cursor { q["cursor"] = c }
            let page: PositionsResponse = try await get("/portfolio/positions", query: q)
            all += page.market_positions
            cursor = (page.cursor?.isEmpty == false) ? page.cursor : nil
        } while cursor != nil
        return all.filter { ($0.position_fp?.value ?? 0) != 0 }
    }

    public func restingOrders() async throws -> [Order] {
        var all: [Order] = []
        var cursor: String? = nil
        repeat {
            var q = ["status": "resting", "limit": "200"]
            if let c = cursor { q["cursor"] = c }
            let page: OrdersResponse = try await get("/portfolio/orders", query: q)
            all += page.orders
            cursor = (page.cursor?.isEmpty == false) ? page.cursor : nil
        } while cursor != nil
        return all
    }

    /// Every settlement, newest first as Kalshi returns them. `since` adds `min_ts` so an
    /// incremental refresh only pages what's new.
    public func settlements(since: Date? = nil) async throws -> [Settlement] {
        var all: [Settlement] = []
        var cursor: String? = nil
        repeat {
            var q = ["limit": "1000"]
            if let since { q["min_ts"] = String(Int(since.timeIntervalSince1970)) }
            if let c = cursor { q["cursor"] = c }
            let page: SettlementsResponse = try await get("/portfolio/settlements", query: q)
            all += page.settlements
            cursor = (page.cursor?.isEmpty == false) ? page.cursor : nil
        } while cursor != nil
        return all
    }

    /// Batch lookup. Kalshi accepts a comma-separated `tickers` filter; chunk to stay polite.
    public func markets(tickers: [String]) async throws -> [Market] {
        var out: [Market] = []
        for chunk in tickers.chunked(50) {
            let page: MarketsResponse = try await get("/markets", query: ["tickers": chunk.joined(separator: ","), "limit": "200"])
            out += page.markets
        }
        return out
    }

    public func event(_ ticker: String) async throws -> Event {
        let r: EventResponse = try await get("/events/\(ticker)")
        return r.event
    }

    public func series(_ ticker: String) async throws -> Series {
        let r: SeriesResponse = try await get("/series/\(ticker)")
        return r.series
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let env = credential.environment
        let signedPath = env.apiPrefix + path            // NO query string in the signed text
        var comps = URLComponents(url: env.baseURL.appendingPathComponent(signedPath), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let signature = try credential.sign(ts + "GET" + signedPath).base64EncodedString()

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue(credential.keyID, forHTTPHeaderField: "KALSHI-ACCESS-KEY")
        req.setValue(ts, forHTTPHeaderField: "KALSHI-ACCESS-TIMESTAMP")
        req.setValue(signature, forHTTPHeaderField: "KALSHI-ACCESS-SIGNATURE")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw KalshiError.transport(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else { throw KalshiError.transport("no HTTP response") }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = (try? JSONDecoder().decode(KalshiErrorBody.self, from: data))?.message
                ?? String(data: data, encoding: .utf8) ?? ""
            throw KalshiError.http(http.statusCode, body)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
