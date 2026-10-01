import SwiftUI
import AppKit
import ServiceManagement

/// User preferences. Kept in the App Group suite so a future widget option can share them.
enum Prefs {
    static var defaults: UserDefaults { UserDefaults(suiteName: SharedIDs.appGroup) ?? .standard }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var scheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    static let appearanceKey = "appearance"
    static let menuBarShowPnLKey = "menuBarShowPnL"
    /// Work Mode: menu bar shows no Spex icon and no "$" — just a bare number, so a shared
    /// screen doesn't advertise a Kalshi portfolio.
    static let workModeKey = "workMode"
    /// Sport filter for the positions list; empty string means "All".
    static let sportFilterKey = "sportFilter"
    static let sortKey = "groupSort"

    /// Sections of the main window. ⌘1–⌘4; P&L is hidden in Work Mode.
    enum MainTab: String, CaseIterable, Identifiable {
        case positions, orders, settled, pnl
        var id: String { rawValue }
        var label: String {
            switch self {
            case .positions: return "Positions"
            case .orders: return "Orders"
            case .settled: return "Settled"
            case .pnl: return "P&L"
            }
        }
        var shortcutKey: Character {
            switch self {
            case .positions: return "1"
            case .orders: return "2"
            case .settled: return "3"
            case .pnl: return "4"
            }
        }
        /// Tabs shown for the current mode: everything, minus P&L in Work Mode.
        static func visible(workMode: Bool) -> [MainTab] {
            allCases.filter { !(workMode && $0 == .pnl) }
        }
    }

    enum GroupSort: String, CaseIterable, Identifiable {
        case liveFirst, soonest, latest
        var id: String { rawValue }
        var label: String {
            switch self {
            case .liveFirst: return "Live first"
            case .soonest: return "Earliest start first"
            case .latest: return "Latest start first"
            }
        }
        var symbol: String {
            switch self {
            case .liveFirst: return "dot.radiowaves.left.and.right"
            case .soonest: return "arrow.up"
            case .latest: return "arrow.down"
            }
        }
        func sorted(_ groups: [EventGroup]) -> [EventGroup] {
            let far = Date.distantFuture
            switch self {
            case .liveFirst:
                // live → upcoming (soonest first) → finals awaiting settlement
                func rank(_ g: EventGroup) -> Int { g.isLive ? 0 : g.isFinal ? 2 : 1 }
                return groups.sorted {
                    if rank($0) != rank($1) { return rank($0) < rank($1) }
                    return ($0.startTime ?? far) < ($1.startTime ?? far)
                }
            case .soonest: return groups.sorted { ($0.startTime ?? far) < ($1.startTime ?? far) }
            case .latest: return groups.sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.appearanceKey, store: Prefs.defaults) private var appearance: Prefs.Appearance = .system
    @AppStorage(Prefs.menuBarShowPnLKey, store: Prefs.defaults) private var menuBarShowPnL = true
    @AppStorage(Prefs.workModeKey, store: Prefs.defaults) private var workMode = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @ObservedObject private var updater = Updater.shared
    @State private var autoUpdate = Updater.shared.automaticallyChecks

    var body: some View {
        VStack(spacing: 0) {
        // macOS 26+ pins window titles to the left. Hide the real one and add our own label
        // as a subview of the title bar itself, centered — the title bar can't paint over its own child.
        Color.clear.frame(height: 0)
            .background(WindowConfigurator { w in
                w.title = "Settings"
                w.toolbar = nil
                w.titleVisibility = .hidden
                guard let bar = w.standardWindowButton(.closeButton)?.superview,
                      bar.subviews.first(where: { $0.identifier?.rawValue == "spex.centeredTitle" }) == nil else { return }
                let label = NSTextField(labelWithString: "Settings")
                label.identifier = NSUserInterfaceItemIdentifier("spex.centeredTitle")
                label.font = NSFont.titleBarFont(ofSize: NSFont.systemFontSize)
                label.textColor = .labelColor
                label.alignment = .center
                label.sizeToFit()
                label.frame.origin = NSPoint(x: (bar.bounds.width - label.frame.width) / 2,
                                             y: (bar.bounds.height - label.frame.height) / 2)
                label.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
                bar.addSubview(label)
            })
        Image(nsImage: NSApp.applicationIconImage)
            .resizable().interpolation(.high)
            .frame(width: 95, height: 95)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .accessibilityHidden(true)
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(Prefs.Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("System follows your Mac or iPhone's light/dark setting, including automatic switching.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle("Show unrealized P&L next to the icon", isOn: $menuBarShowPnL)
                Toggle("Work Mode", isOn: $workMode)
                Text("Hides the Spex icon and the $ sign in the menu bar, so a shared screen shows only a plain number (or a neutral dot when P&L is off). Nothing else changes.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let e = loginError {
                    Text(e).font(.footnote).foregroundStyle(.red)
                }
                Text("Also visible under System Settings → General → Login Items.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, on in Updater.shared.automaticallyChecks = on }
                    .disabled(!updater.isConfigured)
                Button("Check Now") { Updater.shared.checkForUpdates() }
                    .disabled(!updater.canCheck)
                Text(updater.isConfigured
                     ? "Updates come from GitHub Releases and are verified against a signing key built into the app."
                     : "This build was made from source without a release signing key, so automatic updates are off. Pull the repo and rebuild to update.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Text("Spex Glance is a cleaner way to keep track of your open Kalshi sports positions — in a window and from the menu bar. It uses a free, read-only API key from your own Kalshi account; nothing leaves your Mac except requests to Kalshi.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Not affiliated with Kalshi. Does not place, amend, or cancel orders. Informational only — not trading advice. Prices and settlements are relayed from Kalshi as-is and can lag or be wrong; always confirm on Kalshi before acting.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    Browser.open(URL(string: "https://github.com/davidmarcantonio/spex-glance")!)
                } label: { Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                Button {
                    // Support is a GitHub issue. Pre-fill the environment so the report is useful on arrival.
                    let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                    let os = ProcessInfo.processInfo.operatingSystemVersionString
                    let body = "**Spex Glance** \(app) · **macOS** \(os)\n\n**What happened**\n\n\n**What you expected**\n\n"
                    var c = URLComponents(string: "https://github.com/davidmarcantonio/spex-glance/issues/new")!
                    c.queryItems = [URLQueryItem(name: "body", value: body)]
                    Browser.open(c.url!)
                } label: { Label("Report a problem or ask a question", systemImage: "questionmark.bubble") }
                Text("Support is handled through GitHub issues. Please include what you saw and what you expected; your app and macOS versions are filled in for you.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") { NSWorkspace.shared.open(url) }
                } label: { Label("Third-party licenses", systemImage: "doc.text") }
                Text("MIT licensed, provided as-is with no warranty. Built with Claude. Includes Sparkle (MIT) and Space Grotesk (SIL OFL 1.1).")
                    .font(.footnote).foregroundStyle(.tertiary)
            }

            Section("Want to help keep this project running?") {
                HStack {
                    Button {
                        Browser.open(URL(string: "https://ko-fi.com/U4B527UPTU")!)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "cup.and.saucer.fill")
                            Text("Support me on Ko-fi").fontWeight(.semibold)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(Color(red: 1.0, green: 0.37, blue: 0.36), in: Capsule())   // Ko-fi coral
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Support me on Ko-fi (opens in your browser)")
                    Spacer()
                }
                Text("Spex Glance is free. Tips go toward the Apple developer account that keeps it signed and notarized.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        }
        .frame(width: 440)
        .padding(.bottom, 8)
    }
}

/// Runs a closure against the hosting NSWindow once it exists.
struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { configure(w) } }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { if let w = v.window { configure(w) } }
    }
}
