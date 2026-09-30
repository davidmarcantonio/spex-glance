import WidgetKit
import SwiftUI

struct OpenBetsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OpenBetsEntry

    var body: some View {
        if entry.notConnected {
            notConnected
        } else if let snap = entry.snapshot {
            switch family {
            case .systemSmall: SmallView(snap: snap)
            case .systemMedium: MediumView(snap: snap)
            case .systemLarge: LargeView(snap: snap)
            default: SmallView(snap: snap)
            }
        } else {
            VStack {
                Image(systemName: "eyeglasses").font(.title)
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var notConnected: some View {
        VStack(spacing: 6) {
            Image(systemName: "link.badge.plus").font(.title2)
            Text("Open Spex Glance to connect Kalshi").font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding()
    }
}

// MARK: - Shared bits

private func pnlColor(_ v: Double?) -> Color { Fmt.pnlColor(v) }

private struct Header: View {
    let snap: PortfolioSnapshot
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "eyeglasses").font(.caption).foregroundStyle(.secondary)
            Text("Spex").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if snap.environment == .demo {
                Text("DEMO").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange)
            }
            Spacer()
            if snap.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
            }
            if !compact {
                Text(snap.updatedAt, style: .time).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct GroupLine: View {
    let group: EventGroup
    var showEvent = true

    /// "Yes · Vegas 24% · Yes · Vegas (2nd Period) 93%" or the combo's legs.
    private var widgetDetail: String {
        if let b = group.bets.first, let legs = b.legs {
            let pct = b.sideProbability.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""
            return legs.map(\.sideTitle).joined(separator: " + ") + pct
        }
        return group.bets.map { bet in
            let pct = bet.sideProbability.map { " \(Int(($0 * 100).rounded()))%" } ?? ""
            return bet.positionLabel + pct
        }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(group.isCombo ? Color.purple : group.isHedged ? Color.orange : (group.primary.isYes ? Color.green : Color.red))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(group.isCombo ? "\(group.bets.first?.legs?.count ?? 0)-leg combo" : group.title)
                        .font(.caption.weight(.medium)).lineLimit(1)
                    if group.isLive { Text("LIVE").font(.system(size: 8, weight: .bold)).foregroundStyle(.red) }
                    else if let st = group.startTime { Text(Fmt.gameTime(st)).font(.system(size: 8)).foregroundStyle(.tertiary) }
                    else if let s = group.sport { Text(s).font(.system(size: 8)).foregroundStyle(.tertiary) }
                }
                Text(widgetDetail)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.dollars(group.unrealized, signed: true))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(pnlColor(group.unrealized))
                if group.realized != 0 {
                    Text("\(Fmt.dollars(group.realized, signed: true)) rlzd")
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(pnlColor(group.realized))
                } else {
                    Text("max \(Fmt.dollars(group.maxPayout))")
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Families

struct SmallView: View {
    let snap: PortfolioSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Header(snap: snap, compact: true)
            Spacer(minLength: 0)
            Text(Fmt.dollars(snap.totalUnrealized, signed: true))
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(pnlColor(snap.totalUnrealized))
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(snap.totalRealized != 0 ? "unrealized · \(Fmt.dollars(snap.totalRealized, signed: true)) rlzd" : "unrealized")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            HStack {
                Text("\(snap.groups.count) games").font(.caption)
                Spacer()
                Text(Fmt.dollars(snap.totalAtRisk)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("at risk").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

struct MediumView: View {
    let snap: PortfolioSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Header(snap: snap)
            if snap.bets.isEmpty {
                Spacer()
                Text("No open sports bets").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(snap.groups.prefix(3)) { GroupLine(group: $0, showEvent: false) }
                if snap.groups.count > 3 {
                    Text("+\(snap.groups.count - 3) more").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text("Cash \(Fmt.dollars(snap.balanceDollars)) · Pos \(Fmt.dollars(snap.totalValue))").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.dollars(snap.totalUnrealized, signed: true))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(pnlColor(snap.totalUnrealized))
            }
        }
    }
}

struct LargeView: View {
    let snap: PortfolioSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(snap: snap)
            HStack {
                VStack(alignment: .leading) {
                    Text("Cash").font(.caption2).foregroundStyle(.secondary)
                    Text(Fmt.dollars(snap.balanceDollars)).font(.headline.monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Unrealized").font(.caption2).foregroundStyle(.secondary)
                    Text(Fmt.dollars(snap.totalUnrealized, signed: true))
                        .font(.headline.monospacedDigit()).foregroundStyle(pnlColor(snap.totalUnrealized))
                    if snap.totalRealized != 0 {
                        Text("\(Fmt.dollars(snap.totalRealized, signed: true)) realized")
                            .font(.caption2.monospacedDigit()).foregroundStyle(pnlColor(snap.totalRealized))
                    }
                }
            }
            Divider()
            if snap.bets.isEmpty {
                Text("No open sports bets").foregroundStyle(.secondary)
            } else {
                ForEach(snap.groups.prefix(7)) { GroupLine(group: $0) }
                if snap.groups.count > 7 {
                    Text("+\(snap.groups.count - 7) more").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if !snap.orders.isEmpty {
                Divider()
                Text("Resting orders").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(snap.orders.prefix(3)) { o in
                    HStack {
                        Text("\(o.isBuy ? "Buy" : "Sell") \(Fmt.contracts(o.remaining)) \(o.sideTitle)").font(.caption2).lineLimit(1)
                        Spacer()
                        Text("@ \(Fmt.cents(o.limitDollars))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if snap.hiddenNonSports > 0 {
                Text("\(snap.hiddenNonSports) non-sports not shown").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            if let e = snap.errorMessage {
                Text(e).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }
}


#Preview("Medium", as: .systemMedium) {
    OpenBetsWidget()
} timeline: {
    OpenBetsEntry(date: .now, snapshot: .sample, notConnected: false)
}
