import SwiftUI

struct MarketListView: View {
    @EnvironmentObject private var store: TrackedMarketsStore
    @Binding var route: Route

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.markets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.markets) { market in
                            MarketRowView(
                                market: market,
                                snapshot: store.snapshot(for: market.id),
                                onTogglePin: { store.togglePin(market) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { route = .detail(market.id) }

                            if market.id != store.markets.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("PolyTracker")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing
                               ? .linear(duration: 1).repeatForever(autoreverses: false)
                               : .default, value: store.isRefreshing)
            }
            .buttonStyle(.borderless)
            .help("Refresh now")

            Button { route = .add } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add a market")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No markets tracked")
                .font(.system(size: 12, weight: .medium))
            Button("Add a market") { route = .add }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack {
            Text("Updated \(Fmt.relative(store.lastRefresh))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
