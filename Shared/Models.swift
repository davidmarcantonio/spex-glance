import Foundation

/// Kalshi is mid-migration from integer cents to fixed-point dollar strings, and
/// some fields show up as either. `Flex` swallows string / int / double.
public struct Flex: Codable, Equatable, Sendable {
    public var value: Double?

    public init(_ v: Double?) { value = v }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

// MARK: - Wire types (fields we use plus the legacy/new pairs Kalshi is migrating between;
// everything optional so a schema change degrades a field, not the whole decode)

/// GET /api_keys — every key on the account with its scopes. Used to verify the key handed to
/// Spex Glance is read-only before we accept it, and again on launch.
public struct ApiKeysResponse: Codable, Sendable {
    public var api_keys: [ApiKeyInfo]
}
public struct ApiKeyInfo: Codable, Sendable {
    public var api_key_id: String
    public var name: String?
    /// "read", "write", "read::portfolio_balance", "write::trade", "write::transfer", …
    public var scopes: [String]?

    /// The only scopes a Spex Glance key may carry: Kalshi's "Read all data" box and the two
    /// read-side granular scopes it auto-includes (Portfolio balance, Read block trades).
    /// "Full access" and the write-side granular boxes — Trade, Transfers, Accept block trades —
    /// are refused, as is any scope we've never seen.
    public static let allowedScopes: Set<String> = ["read", "read::portfolio_balance", "read::block_trade_accept"]

    /// Scopes on this key that Spex Glance does not accept, in Kalshi's UI wording.
    public var disallowedScopes: [String] {
        (scopes ?? []).filter { !Self.allowedScopes.contains($0.lowercased()) }.map(Self.label)
    }
    public var hasReadScope: Bool { (scopes ?? []).contains { $0.lowercased() == "read" } }
    public var isReadOnlyKey: Bool { hasReadScope && disallowedScopes.isEmpty }

    static func label(_ scope: String) -> String {
        switch scope.lowercased() {
        case "write": return "Full access"
        case "write::trade": return "Trade"
        case "write::transfer": return "Transfers"
        case "write::block_trade_accept": return "Accept block trades"
        case "write::fcm_risk": return "FCM risk"
        default: return scope
        }
    }
}

public struct BalanceResponse: Codable, Sendable {
    /// Legacy integer cents.
    public var balance: Flex?
    public var balance_dollars: Flex?
    public var portfolio_value: Flex?
    public var portfolio_value_dollars: Flex?

    public var balanceDollars: Double? {
        balance_dollars?.value ?? balance?.value.map { $0 / 100 }
    }
    public var portfolioValueDollars: Double? {
        portfolio_value_dollars?.value ?? portfolio_value?.value.map { $0 / 100 }
    }
}

public struct MarketPosition: Codable, Sendable {
    public var ticker: String
    /// Positive = YES contracts, negative = NO contracts (fixed-point string).
    public var position_fp: Flex?
    /// Legacy integer form of the same.
    public var position: Flex?
    public var market_exposure_dollars: Flex?
    public var market_exposure: Flex?          // legacy cents
    public var realized_pnl_dollars: Flex?
    public var realized_pnl: Flex?             // legacy cents
    public var fees_paid_dollars: Flex?
    public var fees_paid: Flex?                // legacy cents

    public var contractsSigned: Double { position_fp?.value ?? position?.value ?? 0 }
    public var exposureDollars: Double { market_exposure_dollars?.value ?? market_exposure?.value.map { $0 / 100 } ?? 0 }
    public var realizedDollars: Double? { realized_pnl_dollars?.value ?? realized_pnl?.value.map { $0 / 100 } }
    public var feesDollars: Double? { fees_paid_dollars?.value ?? fees_paid?.value.map { $0 / 100 } }
}

public struct PositionsResponse: Codable, Sendable {
    public var market_positions: [MarketPosition]
    public var cursor: String?
}

public struct Order: Codable, Sendable {
    public var order_id: String?
    public var ticker: String
    public var status: String?
    /// Legacy direction fields.
    public var side: String?          // "yes" | "no"
    public var action: String?        // "buy" | "sell"
    /// Newer direction fields.
    public var outcome_side: String?  // "yes" | "no"
    public var book_side: String?     // "bid" | "ask"
    public var yes_price_dollars: Flex?
    public var no_price_dollars: Flex?
    public var yes_price: Flex?       // legacy cents
    public var no_price: Flex?
    public var remaining_count_fp: Flex?
    public var remaining_count: Flex?

    public var isYes: Bool { (outcome_side ?? side ?? "yes").lowercased() == "yes" }
    public var isBuy: Bool {
        if let b = book_side { return b.lowercased() == "bid" }
        return (action ?? "buy").lowercased() == "buy"
    }
    /// Contracts still resting. 0 when Kalshi omits the field rather than guessing from the initial size.
    public var remaining: Double {
        remaining_count_fp?.value ?? remaining_count?.value ?? 0
    }
    /// Limit price for the side of the order, in dollars.
    public var priceDollars: Double? {
        if isYes {
            return yes_price_dollars?.value ?? yes_price?.value.map { $0 / 100 }
        } else {
            return no_price_dollars?.value ?? no_price?.value.map { $0 / 100 }
        }
    }
}

public struct OrdersResponse: Codable, Sendable {
    public var orders: [Order]
    public var cursor: String?
}

public struct Market: Codable, Sendable {
    public var ticker: String
    public var event_ticker: String?
    public var title: String?          // deprecated upstream but often present
    public var yes_sub_title: String?
    public var no_sub_title: String?
    public var status: String?
    public var result: String?         // "yes" / "no" once settled, else empty
    public var close_time: String?
    /// Kalshi sets this to roughly game start + 3h; used to infer the start time.
    public var expected_expiration_time: String?
    public var last_price_dollars: Flex?
    public var yes_bid_dollars: Flex?
    public var yes_ask_dollars: Flex?
    /// Set on combo (multivariate / parlay) markets: the legs this contract is built from.
    public var mve_collection_ticker: String?
    public var mve_selected_legs: [MVELeg]?
    public var isCombo: Bool { !(mve_selected_legs ?? []).isEmpty }
}

public struct MVELeg: Codable, Sendable {
    public var event_ticker: String?
    public var market_ticker: String
    public var side: String?           // "yes" / "no"
}

public struct MarketsResponse: Codable, Sendable {
    public var markets: [Market]
    public var cursor: String?
}

public struct Event: Codable, Sendable {
    public var event_ticker: String
    public var title: String?
    public var sub_title: String?
    public var category: String?
    public var series_ticker: String?
}

public struct EventResponse: Codable, Sendable {
    public var event: Event
}

/// Series carry the category/tag metadata Kalshi uses for discovery.
/// Sports series look like: category "Sports", tags ["Baseball"].
public struct Series: Codable, Sendable {
    public var ticker: String
    public var title: String?
    public var category: String?
    public var categories: [String]?
    public var tags: [String]?

    public var isSports: Bool {
        let all = ([category] + (categories ?? [])).compactMap { $0?.lowercased() }
        return all.contains("sports")
    }
    /// "Baseball", "Tennis", "Hockey"… — first tag, which is the sport for sports series.
    public var sport: String? { tags?.first }
}

public struct SeriesResponse: Codable, Sendable {
    public var series: Series
}

public struct KalshiErrorBody: Codable, Sendable {
    public var code: String?
    public var message: String?
    public var details: String?
}
