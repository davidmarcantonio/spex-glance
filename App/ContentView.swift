import SwiftUI
import AppKit

/// App-icon palette (D4): paper ground in light mode, navy ground in dark mode.
/// Type: Space Grotesk (the Spex wordmark face, bundled under OFL) for display text; system for body.
enum Theme {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let name = weight == .bold ? "SpaceGrotesk-Bold" : weight == .medium ? "SpaceGrotesk-Medium" : "SpaceGrotesk-Regular"
        return .custom(name, size: size)
    }

    static let paper = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x0B / 255, green: 0x1E / 255, blue: 0x44 / 255, alpha: 1)
            : NSColor(red: 0xF6 / 255, green: 0xF1 / 255, blue: 0xE4 / 255, alpha: 1)
    })
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.sportFilterKey, store: Prefs.defaults) private var sportFilter = ""
    @AppStorage(Prefs.sortKey, store: Prefs.defaults) private var sort: Prefs.GroupSort = .liveFirst
    @AppStorage(Prefs.workModeKey, store: Prefs.defaults) private var workMode = false

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Group {
                if model.isConnected {
                    connectedView
                } else {
                    welcomeView
                }
            }
        }
        .ignoresSafeArea(edges: .top)   // the title row lives in the (hidden) title bar strip
        .background(Theme.paper)
        .sheet(isPresented: $model.showWizard) {
                ConnectWizardView()
                    .environmentObject(model)
            }
        // A widget tap hands its URL to the app; forward it to the browser.
        .onOpenURL { url in
            if url.scheme == "https" { Browser.open(url) }
        }
    }

    /// Our own title row (the window's title bar is hidden): logo + name dead-center across the
    /// full width, traffic lights on the left, refresh on the right. Draggable like a title bar.
    private var titleBar: some View {
        Color.clear
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .modifier(WindowDrag())
    }

    // MARK: Not connected

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "eyeglasses")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Your open Kalshi sports bets, on your home screen.")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Spex Glance uses a read-only API key that never leaves this device. It cannot place, amend, or cancel orders.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                model.showWizard = true
            } label: {
                Label("Connect Kalshi", systemImage: "link")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
            Text("Not affiliated with Kalshi. Informational only — not trading advice.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .padding()
    }

    // MARK: Connected

    @ViewBuilder
    private var connectedView: some View {
        let snap = model.snapshot
        let allGroups = snap?.groups ?? []
        // Sports present in the snapshot (combo legs included), in Kalshi's own tag spelling,
        // alphabetical, plus a "Combos" pill when any combo is held.
        let sports = SportFilterBar.pills(for: allGroups)
        // A stale selection (no positions in that sport any more) falls back to All.
        let active = sports.contains(sportFilter) ? sportFilter : ""
        let groups = sort.sorted(allGroups.filter { SportFilterBar.matches($0, active) })
        let orders = (snap?.orders ?? []).filter {
            active.isEmpty || $0.sport == active || (active == SportFilterBar.combos && $0.eventTitle.hasPrefix("Combo:"))
        }
        let marketCount = groups.reduce(0) { $0 + $1.bets.count }
        VStack(spacing: 0) {
            // Fixed header: brand, money strip, P&L line, filter row — each block separated by an
            // edge-to-edge rule. Only the positions scroll.
            VStack(spacing: 10) {
                // No wordmark in the window any more; the row only carries the refresh control.
                ZStack {
                    HStack {
                        Spacer()
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            if model.isRefreshing { ProgressView().controlSize(.small).frame(width: 22, height: 22) }
                            else { Image(systemName: "arrow.clockwise.circle.fill").font(.system(size: 22, weight: .semibold)) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(StatTile.cobalt)
                        .help("Refresh (⌘R)")
                        .accessibilityLabel("Refresh")
                        .disabled(model.isRefreshing)
                        .padding(.trailing, 4)
                    }
                }
                // Work Mode (⌘M): no money tiles, just the positions.
                if !workMode {
                    HStack(alignment: .top, spacing: 12) {
                        StatTile(title: "Cash", value: Fmt.dollars(snap?.balanceDollars))
                        StatTile(title: "Positions", value: Fmt.dollars(snap?.totalValue), sub: "pays up to \(Fmt.dollars(snap?.totalMaxPayout))")
                        StatTile(title: "Total", value: Fmt.dollars(snap?.sportsTotal), sub: "cash + positions")
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 18)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if !workMode {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unrealized").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.dollars(snap?.totalUnrealized, signed: true))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(Fmt.pnlColor(snap?.totalUnrealized))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let r = snap?.totalRealized, r != 0 {
                            Text("\(Fmt.dollars(r, signed: true)) realized on open markets")
                                .font(.caption.monospacedDigit()).foregroundStyle(Fmt.pnlColor(r))
                        }
                        if let all = snap?.portfolioValueDollars, let h = snap?.hiddenNonSports, h > 0 {
                            Text("All markets: positions \(Fmt.dollars(all)) incl. \(h) non-sports")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                }
                if !model.health.isOK {
                    Label {
                        Text(model.health.summary + (model.healthChangedAt.map { " · since \(Fmt.gameTime($0))" } ?? "")
                             + ". Numbers may be stale.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote).foregroundStyle(Color(nsColor: model.health.tint ?? .secondaryLabelColor))
                }
                if let err = snap?.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if let w = model.keyScopeWarning {
                    Label(w, systemImage: "lock.open.trianglebadge.exclamationmark")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if let t = snap?.updatedAt {
                    HStack(spacing: 6) {
                        Text("Updated \(Fmt.relative(t))")
                        if case .live = model.liveState {
                            if let lag = model.feedLag, lag > 15, let tk = model.lastTickAt, Date().timeIntervalSince(tk) < 120 {
                                Circle().fill(.orange).frame(width: 6, height: 6)
                                Text("live · \(Int(lag))s behind")
                            } else {
                                Circle().fill(.green).frame(width: 6, height: 6)
                                Text("live")
                            }
                        }
                    }
                    .font(.footnote).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()

            ZStack {
                if sports.count > 1 {
                    SportFilterBar(sports: sports, selection: $sportFilter, active: active)
                }
                HStack {
                    Spacer()
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(Prefs.GroupSort.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                            .padding(6)
                            .background(Color.secondary.opacity(0.15), in: Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Sort: \(sort.label)")
                    .accessibilityLabel("Sort games")
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            Divider()

        List {
            Section(sectionTitle(active: active, games: groups.count, markets: marketCount)) {
                if !groups.isEmpty {
                    ForEach(groups) { g in
                        GroupRow(group: g, expanded: Binding(
                            get: { model.expandedGroups.contains(g.id) },
                            set: { _ in model.toggleExpanded(g.id) }))
                    }
                } else if active.isEmpty {
                    Text(model.isRefreshing ? "Loading…" : "No open sports positions.").foregroundStyle(.secondary)
                } else {
                    Text("No open \(active.lowercased()) positions.").foregroundStyle(.secondary)
                }
                if let h = snap?.hiddenNonSports, h > 0 {
                    Text("\(h) non-sports position\(h == 1 ? "" : "s") not shown")
                        .font(.footnote).foregroundStyle(.tertiary)
                }
            }

            if !orders.isEmpty {
                Section("Resting orders (\(orders.count))") {
                    ForEach(orders) { o in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(o.eventTitle).lineLimit(1)
                                Text("\(o.isBuy ? "Buy" : "Sell") \(Fmt.contracts(o.remaining)) \(o.sideTitle)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.cents(o.limitDollars)).monospacedDigit()
                        }
                    }
                }
            }

        }
        .refreshable { await model.refresh() }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)

        if !workMode {
        Divider()
        HStack {
            Button {
                Browser.open(model.credential?.environment.portfolioURL ?? URL(string: "https://kalshi.com")!)
            } label: { Label("Open Kalshi portfolio", systemImage: "safari") }
            .buttonStyle(SpexButtonStyle(filled: true))
            Spacer()
            Button("Disconnect") { model.disconnect() }
                .buttonStyle(SpexButtonStyle(filled: false))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        }
        }
        .background(Theme.paper)
    }

    private func sectionTitle(active: String, games: Int, markets: Int) -> String {
        let what = active.isEmpty ? "Open sports bets" : "Open \(active.lowercased()) bets"
        return "\(what) (\(games) game\(games == 1 ? "" : "s") · \(markets) market\(markets == 1 ? "" : "s"))"
    }

}

/// One game (or one combo). Collapsed: title, time, and each position with its value and payout.
/// Expanded: cost, chance, qualifier and P&L per position; legs for a combo.
struct GroupRow: View {
    let group: EventGroup
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Group {
                if group.isCombo, let bet = group.bets.first, let legs = bet.legs {
                    comboSummary(bet)
                    if expanded {
                        ComboLegsView(legs: legs).padding(.leading, 2).padding(.top, 2)
                    }
                } else {
                    ForEach(group.bets) { PositionRow(bet: $0, expanded: expanded) }
                }
            }
            .padding(.leading, 22)   // align with the title, right of the chevron
        }
        .padding(.vertical, 4)
        .padding(.trailing, 14)  // breathing room so the value column isn't flush with the edge
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 14)
                .accessibilityLabel(expanded ? "Collapse" : "Expand")
            VStack(alignment: .leading, spacing: 2) {
                if group.isCombo, let bet = group.bets.first {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.caption2)
                        Text("\(bet.legs?.count ?? 0) MARKET COMBO").font(.caption.weight(.semibold)).tracking(0.5)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text(group.title).font(.headline).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let st = Fmt.gameStatus(start: group.startTime, isLive: group.isLive, isFinal: group.isFinal) {
                        Text(st).font(.caption.weight(group.isLive ? .bold : .regular))
                            .foregroundStyle(group.isLive ? Color.red : Color.secondary)
                    }
                    if let sp = group.sport {
                        Label(sp, systemImage: SportGlyph.symbol(for: sp)).font(.caption).foregroundStyle(.secondary)
                    } else if group.isCombo, group.sports.count > 1 {
                        Text(group.sports.sorted().joined(separator: " / ")).font(.caption).foregroundStyle(.secondary)
                    }
                    if group.isHedged {
                        Text("hedged").font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2)).clipShape(Capsule())
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.dollars(group.unrealized, signed: true))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Fmt.pnlColor(group.unrealized))
                if group.realized != 0 {
                    Text("\(Fmt.dollars(group.realized, signed: true)) realized")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Fmt.pnlColor(group.realized))
                }
            }
        }
    }

    /// Collapsed combo line: what it pays and what it's worth now; cost and chance when expanded.
    private func comboSummary(_ bet: OpenBet) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pays \(Fmt.dollars(bet.maxPayout))").fontWeight(.semibold).monospacedDigit()
                if expanded {
                    Text("Cost \(Fmt.dollars(bet.costDollars))").font(.caption).foregroundStyle(.secondary)
                    if !bet.isYes { Text("You hold NO — pays if any leg misses").font(.caption).foregroundStyle(.orange) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                ValueLabel(bet: bet)
                if expanded { ChanceLabel(bet: bet, font: .caption) }
            }
        }
    }
}

/// Horizontal row of pills: All, then one per sport present in the snapshot.
/// Sports come from Kalshi's series tags, so new leagues show up without a code change.
struct SportFilterBar: View {
    /// Pseudo-sport for the "Combos" pill.
    static let combos = "Combos"
    /// Every sport present (combo legs included), alphabetical, then "Combos" if any are held.
    static func pills(for groups: [EventGroup]) -> [String] {
        var sports = Array(groups.reduce(into: Set<String>()) { $0.formUnion($1.sports) }).sorted()
        if groups.contains(where: \.isCombo) { sports.append(combos) }
        return sports
    }
    static func matches(_ g: EventGroup, _ active: String) -> Bool {
        if active.isEmpty { return true }
        if active == combos { return g.isCombo }
        return g.sports.contains(active)
    }

    let sports: [String]
    @Binding var selection: String
    /// The selection after fallback (a sport with no positions collapses to All).
    let active: String

    var body: some View {
        HStack(spacing: 6) {
            pill("All", value: "")
            ForEach(sports, id: \.self) { pill($0, value: $0) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by sport")
    }

    private func pill(_ title: String, value: String) -> some View {
        let on = (active == value)
        return Button {
            selection = value
        } label: {
            HStack(spacing: 4) {
                Image(systemName: SportGlyph.symbol(for: value)).font(.caption2)
                Text(title)
            }
            .font(.caption.weight(on ? .semibold : .regular))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(on ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(on ? Color.white : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Header money tile in the app-icon palette: cobalt block, cream digits, rounded corners.
/// Square at small values; grows to the right as the number gets longer ($100 → $123,456.78).
struct StatTile: View {
    let title: String
    let value: String
    var sub: String? = nil

    static let cobalt = Color(red: 0x1E / 255, green: 0x5E / 255, blue: 0xFF / 255)
    static let cream = Color(red: 0xFF / 255, green: 0xF4 / 255, blue: 0xD6 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(Theme.display(10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Self.cream.opacity(0.8))
            Text(value)
                .font(Theme.display(24, weight: .bold).monospacedDigit())
                .foregroundStyle(Self.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub ?? " ")
                .font(Theme.display(10, weight: .regular))
                .foregroundStyle(Self.cream.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 84, minHeight: 84, alignment: .leading)
        .background(Self.cobalt, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

/// Lets the custom title row move the window, like a real title bar.
struct WindowDrag: ViewModifier {
    func body(content: Content) -> some View {
        content.gesture(WindowDragGesture())
    }
}

/// Pill buttons in the icon palette: filled cobalt with cream text, or a cobalt outline.
struct SpexButtonStyle: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(filled ? StatTile.cream : StatTile.cobalt)
            .background(filled ? StatTile.cobalt : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(StatTile.cobalt, lineWidth: filled ? 0 : 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
