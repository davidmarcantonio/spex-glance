import SwiftUI
import WidgetKit

@main
struct SpexGlanceApp: App {
    @StateObject private var model = AppModel()
    @AppStorage(Prefs.appearanceKey, store: Prefs.defaults) private var appearance: Prefs.Appearance = .system
    @AppStorage(Prefs.menuBarShowPnLKey, store: Prefs.defaults) private var menuBarShowPnL = true
    @AppStorage(Prefs.workModeKey, store: Prefs.defaults) private var workMode = false

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(appearance.scheme)
                .task { await model.refresh() }
                .frame(minWidth: 560, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)   // ContentView draws its own centered title row
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.canCheck)
            }
            CommandMenu("Positions") {
                Button("Expand / Collapse All") { model.toggleExpandAll() }
                    .keyboardShortcut("e", modifiers: .command)
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                // ⌘M: same switch as Settings → Menu bar → Work Mode. Hides the menu bar icon,
                // the "$" sign, the money tiles and the bottom buttons; leaves the positions.
                Toggle("Work Mode", isOn: $workMode)
                    .keyboardShortcut("m", modifiers: .command)
            }
        }

        Settings {
            SettingsView().preferredColorScheme(appearance.scheme)
        }

        // Live menu bar item: net P&L in the bar, live percentages in the dropdown.
        MenuBarExtra {
            MenuBarView().environmentObject(model).preferredColorScheme(appearance.scheme)
        } label: {
            if workMode {
                // Work Mode: no logo, no "$" — a bare signed number, or a neutral dot.
                if menuBarShowPnL, let n = model.menuBarNumber { Text(n) }
                else { Image(systemName: "circle.dotted") }
            } else if menuBarShowPnL {
                Label {
                    Text(model.menuBarTitle)
                } icon: {
                    Image(nsImage: MenuBarIcon.image)
                }
                .labelStyle(.titleAndIcon)
            } else {
                Image(nsImage: MenuBarIcon.image)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var credential: KalshiCredential? = KeychainStore.load()
    @Published var snapshot: PortfolioSnapshot? = SnapshotCache.load()
    @Published var isRefreshing = false
    @Published var showWizard = false
    @Published var liveState: LiveTicker.State = .idle
    @Published var lastTickAt: Date?
    /// Group ids (game keys / combo tickers) currently expanded in the positions list.
    @Published var expandedGroups: Set<String> = []
    /// Set when the connected key turns out to have write scopes (checked once per launch).
    @Published var keyScopeWarning: String?
    private var scopeChecked = false

    func toggleExpanded(_ id: String) {
        if expandedGroups.contains(id) { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
    }
    /// ⌘E: if anything is open, close everything; otherwise open everything.
    func toggleExpandAll() {
        let ids = Set((snapshot?.groups ?? []).map(\.id))
        expandedGroups = expandedGroups.isEmpty ? ids : []
    }

    private let ticker = LiveTicker()
    private var pollTimer: Timer?
    private var inFlight: Task<Void, Never>?
    /// When each market last ticked over the socket, so a REST refresh doesn't clobber a newer quote.
    private var tickTimes: [String: Date] = [:]

    var isConnected: Bool { credential != nil }

    var menuBarTitle: String {
        guard let s = snapshot, !s.bets.isEmpty else { return "Spex" }
        return Fmt.dollars(s.totalUnrealized, signed: true)
    }
    /// Work Mode title: "+305.57" — no currency sign, nil when there is nothing to show.
    var menuBarNumber: String? {
        guard let s = snapshot, !s.bets.isEmpty else { return nil }
        return Fmt.dollars(s.totalUnrealized, signed: true).replacingOccurrences(of: "$", with: "")
    }

    init() {
        ticker.onTick = { [weak self] t, bid, ask, last in self?.applyTick(t, bid, ask, last) }
        ticker.onState = { [weak self] s in self?.liveState = s }
        // Positions change without a tick (fills, settlements): poll every 5 min while the app runs.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    /// Coalesces overlapping calls: a refresh already in flight is awaited, not duplicated.
    func refresh() async {
        guard isConnected else { return }
        if let t = inFlight { await t.value; return }
        let task = Task { await self.performRefresh() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        if !scopeChecked, let cred = credential {
            scopeChecked = true
            if case .notReadOnly(let extras, let missingRead) = await KalshiClient(credential: cred).checkOwnKeyScope() {
                keyScopeWarning = "Your Kalshi key " + (extras.isEmpty ? "doesn't have Read all data checked" : "has \(extras.joined(separator: ", ")) checked")
                    + ". Spex Glance never uses those permissions, but replace the key: Disconnect, then create a new one on Kalshi with only Read all data checked."
                    + (missingRead && !extras.isEmpty ? " (It is also missing Read.)" : "")
            } else {
                keyScopeWarning = nil
            }
        }
        var fresh = await Refresher.refresh()
        // Keep any socket quote newer than the REST response.
        if let old = snapshot, old.environment == fresh.environment {
            for i in fresh.bets.indices {
                let t = fresh.bets[i].ticker
                if let tickAt = tickTimes[t], tickAt > fresh.fetchedAt,
                   let prev = old.bets.first(where: { $0.ticker == t }) {
                    fresh.bets[i].applyTick(yesBid: prev.yesBid, yesAsk: prev.yesAsk, last: prev.yesLast)
                }
                // Same for combo legs.
                for leg in old.bets.first(where: { $0.ticker == t })?.legs ?? [] {
                    if let tickAt = tickTimes[leg.ticker], tickAt > fresh.fetchedAt {
                        fresh.bets[i].applyLegTick(ticker: leg.ticker, yesBid: leg.yesBid, yesAsk: leg.yesAsk, last: leg.yesLast)
                    }
                }
            }
        }
        snapshot = fresh
        WidgetCenter.shared.reloadTimelines(ofKind: SharedIDs.widgetKind)
        startLive()
    }

    private func startLive() {
        guard let cred = credential, let s = snapshot else { return }
        let tickers = s.liveTickers
        if tickers.isEmpty { ticker.stop() } else { ticker.start(credential: cred, tickers: tickers) }
    }

    private func applyTick(_ t: String, _ bid: Double?, _ ask: Double?, _ last: Double?) {
        guard var s = snapshot else { return }
        if s.applyTick(ticker: t, yesBid: bid, yesAsk: ask, last: last) {
            snapshot = s
            let now = Date()
            tickTimes[t] = now
            lastTickAt = now
        }
    }

    func connect(_ cred: KalshiCredential) throws {
        try KeychainStore.save(cred)
        credential = cred
        SnapshotCache.clear()
        snapshot = nil
        tickTimes = [:]
        scopeChecked = false
        keyScopeWarning = nil
        Task { await refresh() }
    }

    func disconnect() {
        ticker.stop()
        KeychainStore.delete()
        SnapshotCache.clear()
        credential = nil
        snapshot = nil
        tickTimes = [:]
        WidgetCenter.shared.reloadTimelines(ofKind: SharedIDs.widgetKind)
    }
}
