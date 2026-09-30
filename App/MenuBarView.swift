import SwiftUI

import AppKit
struct MenuBarView: View {
    @AppStorage(Prefs.sortKey, store: Prefs.defaults) private var sort: Prefs.GroupSort = .liveFirst
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(nsImage: MenuBarIcon.image).accessibilityHidden(true)
                Text("Spex Glance").font(.headline)
                Spacer()
                liveDot
            }
            Divider()
            if let s = model.snapshot, !s.bets.isEmpty {
                ForEach(sort.sorted(s.groups)) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            if g.isCombo, let b = g.bets.first {
                                Text("\(b.legs?.count ?? 0) MARKET COMBO · \(Fmt.dollars(b.costDollars)) pays \(Fmt.dollars(b.maxPayout))")
                                    .font(.body.weight(.medium))
                            } else {
                                Text(g.title).font(.body.weight(.medium)).lineLimit(1)
                            }
                            if let st = Fmt.gameStatus(start: g.startTime, isLive: g.isLive, isFinal: g.isFinal) {
                                Text(st).font(.caption2.weight(g.isLive ? .bold : .regular))
                                    .foregroundStyle(g.isLive ? Color.red : Color.secondary)
                            }
                            Spacer()
                            Text(Fmt.dollars(g.unrealized, signed: true))
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Fmt.pnlColor(g.unrealized))
                        }
                        if g.isCombo, let b = g.bets.first, let legs = b.legs {
                            HStack(spacing: 6) {
                                ChanceLabel(bet: b, font: .caption)
                                Spacer()
                            }
                            ForEach(legs) { leg in
                                HStack {
                                    Text("  \(leg.label)").font(.caption2)
                                        .foregroundStyle(leg.outcome == .missed ? Color.red : Color.secondary)
                                    Spacer()
                                    switch leg.outcome {
                                    case .hit: Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                                    case .missed: Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.red)
                                    case .pending:
                                        Text(leg.hitProbability.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        } else {
                            ForEach(g.bets) { bet in
                                HStack {
                                    Text("  " + bet.positionLabel + (bet.qualifier.map { " · \($0)" } ?? ""))
                                        .font(.caption).lineLimit(1)
                                    Spacer()
                                    ChanceLabel(bet: bet, font: .caption)
                                    Text(Fmt.dollars(bet.unrealizedPnL, signed: true))
                                        .font(.caption.monospacedDigit()).foregroundStyle(Fmt.pnlColor(bet.unrealizedPnL))
                                        .frame(width: 64, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Divider()
                HStack {
                    Text("Cash \(Fmt.dollars(s.balanceDollars))").foregroundStyle(.secondary)
                    Spacer()
                    Text("Positions \(Fmt.dollars(s.totalValue))").foregroundStyle(.secondary)
                    Spacer()
                    Text("Total \(Fmt.dollars(s.sportsTotal))").fontWeight(.medium)
                }
                .font(.caption.monospacedDigit())
                HStack {
                    Text("Unrealized").foregroundStyle(.secondary)
                    Spacer()
                    Text(Fmt.dollars(s.totalUnrealized, signed: true))
                        .monospacedDigit().fontWeight(.bold)
                        .foregroundStyle(Fmt.pnlColor(s.totalUnrealized))
                }
                if s.totalRealized != 0 {
                    HStack {
                        Text("Realized").foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.dollars(s.totalRealized, signed: true)).monospacedDigit()
                            .foregroundStyle(Fmt.pnlColor(s.totalRealized))
                    }
                }
                if s.hiddenNonSports > 0 {
                    Text("\(s.hiddenNonSports) non-sports not shown").font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Text(model.isConnected ? "No open sports bets" : "Not connected").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Refresh") { Task { await model.refresh() } }.disabled(model.isRefreshing)
                Button("Open Spex Glance") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                SettingsLink { Text("Settings…") }
                Button("Update…") { Updater.shared.checkForUpdates() }.disabled(!Updater.shared.canCheck)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.caption)
        }
        .padding(12)
        .frame(width: 360)
    }

    private var liveDot: some View {
        let (color, text): (Color, String) = {
            switch model.liveState {
            case .live: return (.green, model.lastTickAt.map { "live · " + Fmt.relative($0) } ?? "live")
            case .connecting: return (.yellow, "connecting")
            case .backoff(let s): return (.orange, "retry in \(s)s")
            case .failed(let m): return (.red, "socket: \(m)")
            case .idle: return (.gray, "polling")
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
