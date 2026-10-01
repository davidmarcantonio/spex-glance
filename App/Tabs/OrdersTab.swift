import SwiftUI

/// ⌘2 — resting orders that haven't filled. Read-only: Spex Glance never places, amends or
/// cancels anything, so the only action is to go to Kalshi.
struct OrdersTab: View {
    @EnvironmentObject var model: AppModel
    let orders: [OpenOrder]

    var body: some View {
        List {
            Section {
                if orders.isEmpty {
                    Text(model.isRefreshing && model.snapshot == nil ? "Loading…" : "No resting orders.")
                        .foregroundStyle(.secondary)
                }
                ForEach(orders) { o in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.eventTitle).font(.headline).lineLimit(2)
                            HStack(spacing: 6) {
                                Text("\(o.isBuy ? "Buy" : "Sell") \(Fmt.contracts(o.remaining)) · \(o.isYes ? "Yes" : "No") · \(o.sideTitle)")
                                if let sp = o.sport {
                                    Label(sp, systemImage: SportGlyph.symbol(for: sp))
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.cents(o.limitDollars)).font(.body.monospacedDigit().weight(.semibold))
                            Text("limit").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Resting orders (\(orders.count))")
            } footer: {
                Text("Spex Glance never places, amends or cancels orders. Manage them on Kalshi.")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
        }
        .refreshable { await model.refresh() }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
    }
}
