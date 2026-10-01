import SwiftUI

/// Positions / Orders / Settled / P&L, as pills in the sport-filter style. ⌘1–⌘4 jump,
/// ⌘⇧[ and ⌘⇧] cycle. P&L is money, so Work Mode drops it from the row entirely.
struct TabBar: View {
    let selection: Prefs.MainTab
    let workMode: Bool
    let select: (Prefs.MainTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Prefs.MainTab.visible(workMode: workMode)) { tab in
                pill(tab)
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }

    private func pill(_ tab: Prefs.MainTab) -> some View {
        let on = tab == selection
        return Button {
            select(tab)
        } label: {
            HStack(spacing: 5) {
                Text(tab.label)
                Text("⌘\(String(tab.shortcutKey))")
                    .font(.caption2)
                    .opacity(0.6)
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

/// Stand-in for a tab whose content lands in a later beta.
struct PlaceholderTab: View {
    let title: String
    let note: String

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(title).font(.headline)
            Text(note).font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
    }
}
