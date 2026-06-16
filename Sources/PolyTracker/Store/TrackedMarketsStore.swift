import Foundation
import SwiftUI

/// Owns the list of tracked markets, their live snapshots, and the refresh loop.
@MainActor
final class TrackedMarketsStore: ObservableObject {
    @Published private(set) var markets: [TrackedMarket] = []
    @Published private(set) var snapshots: [String: MarketSnapshot] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false

    private let defaultsKey = "trackedMarkets.v1"
    private let refreshInterval: TimeInterval = 30   // well within "at least once a minute"
    private var timer: Timer?
    private var activityToken: NSObjectProtocol?

    init() {
        load()

        // Keep the background refresh firing reliably: opt out of App Nap (which would
        // otherwise throttle our timer when no window is focused) while still letting
        // the Mac sleep normally when idle.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Auto-refreshing Polymarket prices"
        )

        // .common mode so the timer keeps firing even while the menu/popover is open.
        let t = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        Task { await refresh() }
    }

    deinit {
        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
        timer?.invalidate()
    }

    // MARK: Derived

    /// Markets shown in the menu bar (any number can be pinned).
    var pinnedMarkets: [TrackedMarket] { markets.filter(\.pinned) }

    func isTracked(_ id: String) -> Bool { markets.contains { $0.id == id } }
    func snapshot(for id: String) -> MarketSnapshot? { snapshots[id] }

    // MARK: Mutations

    func add(_ market: TrackedMarket) {
        guard !isTracked(market.id) else { return }
        markets.append(market)
        save()
        Task { await refresh(only: market) }
    }

    func remove(_ market: TrackedMarket) {
        markets.removeAll { $0.id == market.id }
        snapshots[market.id] = nil
        save()
    }

    func togglePin(_ market: TrackedMarket) {
        update(market.id) { $0.pinned.toggle() }
    }

    func setColor(_ name: String?, for market: TrackedMarket) {
        update(market.id) { $0.colorName = name }
    }

    func setLabel(_ text: String?, for market: TrackedMarket) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        update(market.id) { $0.label = (trimmed?.isEmpty == false) ? trimmed : nil }
    }

    private func update(_ id: String, _ transform: (inout TrackedMarket) -> Void) {
        guard let i = markets.firstIndex(where: { $0.id == id }) else { return }
        transform(&markets[i])
        save()
    }

    // MARK: Refresh

    func refresh() async {
        guard !markets.isEmpty else { lastRefresh = Date(); return }
        isRefreshing = true
        defer { isRefreshing = false }

        let current = markets
        let results = await withTaskGroup(of: (String, MarketSnapshot?).self) { group in
            for m in current {
                group.addTask { (m.id, await Self.fetchSnapshot(for: m)) }
            }
            var acc: [(String, MarketSnapshot?)] = []
            for await r in group { acc.append(r) }
            return acc
        }

        for (id, snap) in results where snap != nil {
            snapshots[id] = snap        // keep the old snapshot if a fetch failed
        }
        lastRefresh = Date()
    }

    private func refresh(only market: TrackedMarket) async {
        if let snap = await Self.fetchSnapshot(for: market) {
            snapshots[market.id] = snap
            lastRefresh = Date()
        }
    }

    private static func fetchSnapshot(for m: TrackedMarket) async -> MarketSnapshot? {
        guard let gm = try? await PolymarketAPI.market(id: m.id),
              let prob = gm.probability(forOutcome: m.outcomeIndex) else { return nil }
        return MarketSnapshot(
            probability: prob,
            volume: gm.volume,
            volume24hr: gm.volume24hr,
            liquidity: gm.liquidity,
            oneDayChange: gm.oneDayPriceChange,
            endDate: gm.endDate,
            updatedAt: Date()
        )
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let arr = try? JSONDecoder().decode([TrackedMarket].self, from: data) else { return }
        markets = arr
    }

    private func save() {
        if let data = try? JSONEncoder().encode(markets) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
