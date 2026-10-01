import SwiftUI

/// ⌘1 — the original view: sport pills and sort on top, the grouped positions list below.
struct PositionsTab: View {
    @EnvironmentObject var model: AppModel
    let sports: [String]
    let active: String
    @Binding var sportFilter: String
    @Binding var sort: Prefs.GroupSort
    let groups: [EventGroup]
    let marketCount: Int
    let hiddenNonSports: Int

    var body: some View {
        VStack(spacing: 0) {
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
                Section(sectionTitle) {
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
                    if hiddenNonSports > 0 {
                        Text("\(hiddenNonSports) non-sports position\(hiddenNonSports == 1 ? "" : "s") not shown")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                }
            }
            .refreshable { await model.refresh() }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
        }
    }

    private var sectionTitle: String {
        let games = groups.count
        let what = active.isEmpty ? "Open sports bets" : "Open \(active.lowercased()) bets"
        return "\(what) (\(games) game\(games == 1 ? "" : "s") · \(marketCount) market\(marketCount == 1 ? "" : "s"))"
    }
}
