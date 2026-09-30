import Foundation

/// Streams Kalshi's `ticker` channel for the markets we hold and pushes price
/// updates into the model. Read-only: the socket only ever sends `subscribe`.
/// Reconnects with backoff on transport errors; a server-side rejection stops it (the
/// 5-minute REST poll keeps the app honest either way).
@MainActor
final class LiveTicker {
    enum State: Equatable { case idle, connecting, live, backoff(Int), failed(String) }

    private(set) var state: State = .idle
    var onTick: ((_ ticker: String, _ yesBid: Double?, _ yesAsk: Double?, _ last: Double?) -> Void)?
    var onState: ((State) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var credential: KalshiCredential?
    private var tickers: Set<String> = []
    private var nextID = 1
    private var attempts = 0
    private var generation = 0

    func start(credential: KalshiCredential, tickers: [String]) {
        let newSet = Set(tickers)
        if self.credential == credential, newSet == self.tickers, state == .live { return }
        self.credential = credential
        self.tickers = newSet
        reconnect()
    }

    func stop() {
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        set(.idle)
    }

    // MARK: Internals

    private func set(_ s: State) {
        state = s
        onState?(s)
    }

    private func reconnect() {
        guard let cred = credential, !tickers.isEmpty else { stop(); return }
        generation += 1
        let gen = generation
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        set(.connecting)

        let env = cred.environment
        var req = URLRequest(url: env.wsURL)
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        guard let sig = try? cred.sign(ts + "GET" + env.wsPath).base64EncodedString() else { set(.idle); return }
        req.setValue(cred.keyID, forHTTPHeaderField: "KALSHI-ACCESS-KEY")
        req.setValue(ts, forHTTPHeaderField: "KALSHI-ACCESS-TIMESTAMP")
        req.setValue(sig, forHTTPHeaderField: "KALSHI-ACCESS-SIGNATURE")

        let s = URLSession(configuration: .default)
        session = s
        let t = s.webSocketTask(with: req)
        task = t
        t.resume()

        let sub: [String: Any] = [
            "id": nextID, "cmd": "subscribe",
            "params": ["channels": ["ticker"], "market_tickers": Array(tickers).sorted()],
        ]
        nextID += 1
        if let data = try? JSONSerialization.data(withJSONObject: sub), let str = String(data: data, encoding: .utf8) {
            t.send(.string(str)) { [weak self] err in
                Task { @MainActor in
                    guard let self, self.generation == gen else { return }
                    if err != nil { self.scheduleRetry() }
                }
            }
        }
        receiveLoop(t, gen: gen)
    }

    private func receiveLoop(_ t: URLSessionWebSocketTask, gen: Int) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                switch result {
                case .failure:
                    self.scheduleRetry()
                case .success(let msg):
                    if case .string(let s) = msg { self.handle(s) }
                    else if case .data(let d) = msg, let s = String(data: d, encoding: .utf8) { self.handle(s) }
                    self.receiveLoop(t, gen: gen)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = obj["type"] as? String
        if type == "subscribed" || type == "ok" {
            attempts = 0
            set(.live)
            return
        }
        if type == "error" {
            // The server rejected the command (bad channel, unknown ticker, auth). Retrying the
            // same request won't help; stop and show why.
            let msg = (obj["msg"] as? [String: Any])?["msg"] as? String
                ?? (obj["msg"] as? String) ?? "subscription rejected"
            generation += 1
            task?.cancel(with: .normalClosure, reason: nil)
            set(.failed(msg))
            return
        }
        guard type == "ticker", let m = obj["msg"] as? [String: Any],
              let ticker = m["market_ticker"] as? String else { return }

        func num(_ keys: [String], cents: Bool = false) -> Double? {
            for k in keys {
                if let v = m[k] {
                    if let d = v as? Double { return cents ? d / 100 : d }
                    if let i = v as? Int { return cents ? Double(i) / 100 : Double(i) }
                    if let s = v as? String, let d = Double(s) { return cents ? d / 100 : d }
                }
            }
            return nil
        }
        let bid = num(["yes_bid_dollars"]) ?? num(["yes_bid"], cents: true)
        let ask = num(["yes_ask_dollars"]) ?? num(["yes_ask"], cents: true)
        let last = num(["price_dollars"]) ?? num(["price"], cents: true)
        if state != .live { attempts = 0; set(.live) }
        onTick?(ticker, bid, ask, last)
    }

    private func scheduleRetry() {
        attempts += 1
        let delay = min(60, Int(pow(2.0, Double(min(attempts, 6)))))   // 2,4,8,…,60s
        set(.backoff(delay))
        let gen = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard let self, self.generation == gen else { return }
            self.reconnect()
        }
    }
}
