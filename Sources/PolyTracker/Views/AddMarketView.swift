import SwiftUI

struct AddMarketView: View {
    @EnvironmentObject private var store: TrackedMarketsStore
    @Binding var route: Route

    @State private var query = ""
    @State private var results: [SearchResultItem] = []
    @State private var loading = false
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { route = .list } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            TextField("Search markets or paste URL", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _, _ in scheduleSearch() }
                .onSubmit { scheduleSearch(immediate: true) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else if let message {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { item in
                        ResultRow(item: item, tracked: store.isTracked(item.id)) {
                            add(item)
                        }
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .frame(maxHeight: 380)
        }
    }

    // MARK: Search

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            results = []
            message = "Type at least 2 characters"
            loading = false
            return
        }
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)   // debounce
                if Task.isCancelled { return }
            }
            await runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        loading = true
        message = nil
        do {
            let hits = try await PolymarketAPI.search(q)
            if Task.isCancelled { return }
            results = hits
            message = hits.isEmpty ? "No markets found" : nil
        } catch {
            if Task.isCancelled { return }
            results = []
            message = "Search failed — check your connection"
        }
        loading = false
    }

    // MARK: Add

    private func add(_ item: SearchResultItem) {
        guard !store.isTracked(item.id) else { return }
        Task {
            // Fetch the full market to guarantee clobTokenIds for price history.
            let full = try? await PolymarketAPI.market(id: item.market.id)
            let tracked: TrackedMarket
            if let full {
                tracked = TrackedMarket(from: full, eventSlug: item.eventSlug,
                                        fallbackTitle: item.eventTitle)
            } else {
                tracked = TrackedMarket(from: item.market, eventSlug: item.eventSlug,
                                        fallbackTitle: item.eventTitle)
            }
            store.add(tracked)
            route = .list
        }
    }
}

private struct ResultRow: View {
    let item: SearchResultItem
    let tracked: Bool
    let onAdd: () -> Void

    private var probability: String? {
        if let p = item.market.outcomePrices.first { return Fmt.percent(p) }
        if let p = item.market.lastTradePrice { return Fmt.percent(p) }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                let title = item.market.question ?? item.eventTitle
                if !item.eventTitle.isEmpty && item.eventTitle != title {
                    Text(item.eventTitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            if let probability {
                Text(probability)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button(action: onAdd) {
                Image(systemName: tracked ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(tracked ? Color.green : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(tracked)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
