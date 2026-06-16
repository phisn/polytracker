import SwiftUI

/// In-popover navigation. Sheets are unreliable inside a `.window` MenuBarExtra,
/// so we route between views with simple state instead.
enum Route: Equatable {
    case list
    case add
    case detail(String)   // market id
}

struct PopoverView: View {
    @EnvironmentObject private var store: TrackedMarketsStore
    @State private var route: Route = .list

    var body: some View {
        Group {
            switch route {
            case .list:
                MarketListView(route: $route)
            case .add:
                AddMarketView(route: $route)
            case .detail(let id):
                if let market = store.markets.first(where: { $0.id == id }) {
                    MarketDetailView(market: market, route: $route)
                } else {
                    // Market was removed underneath us — bounce back.
                    Color.clear.onAppear { route = .list }
                }
            }
        }
        .frame(width: 340)
    }
}
