import SwiftUI
import Charts

struct MarketDetailView: View {
    @EnvironmentObject private var store: TrackedMarketsStore
    let market: TrackedMarket
    @Binding var route: Route

    @State private var interval: ChartInterval = .oneDay
    @State private var points: [PricePoint] = []
    @State private var loading = false
    @State private var labelText = ""

    private var snapshot: MarketSnapshot? { store.snapshot(for: market.id) }
    private var accent: Color? { market.colorName.flatMap(MarketColor.init)?.color }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(market.question)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    headline
                    intervalPicker
                    chart
                    stats
                    Divider()
                    customize
                    if let url = market.webURL {
                        Link(destination: url) {
                            Label("Open in Polymarket", systemImage: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 460)
        }
        .onAppear { labelText = market.label ?? "" }
        .task(id: interval) { await load() }
    }

    private var topBar: some View {
        HStack {
            Button { route = .list } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)

            Spacer()

            Button { store.togglePin(market) } label: {
                Image(systemName: market.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(market.pinned ? (accent ?? Color.accentColor) : .secondary)
            }
            .buttonStyle(.borderless)
            .help(market.pinned ? "Unpin from menu bar" : "Pin to menu bar")

            Button {
                store.remove(market)
                route = .list
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Stop tracking")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(snapshot.map { Fmt.percent($0.probability) } ?? "—")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(market.trackedOutcomeName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            if let c = snapshot?.oneDayChange {
                ChangeBadge(change: c)
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }

    private var intervalPicker: some View {
        Picker("", selection: $interval) {
            ForEach(ChartInterval.allCases) { iv in
                Text(iv.label).tag(iv)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var chart: some View {
        let height: CGFloat = 140
        if loading && points.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: height)
        } else if points.isEmpty {
            Text("No price history")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: height)
        } else {
            let color = trendColor
            Chart(points) { pt in
                AreaMark(
                    x: .value("Time", pt.t),
                    yStart: .value("Low", yDomain.lowerBound),
                    yEnd: .value("Probability", pt.p * 100)
                )
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.25), color.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
                LineMark(
                    x: .value("Time", pt.t),
                    y: .value("Probability", pt.p * 100)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))%").font(.system(size: 9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: xAxisFormat, anchor: .top)
                        .font(.system(size: 9))
                }
            }
            .frame(height: height)
        }
    }

    private var stats: some View {
        VStack(spacing: 6) {
            StatRow(label: "24h volume", value: snapshot?.volume24hr.map(Fmt.usd))
            StatRow(label: "Total volume", value: snapshot?.volume.map(Fmt.usd))
            StatRow(label: "Liquidity", value: snapshot?.liquidity.map(Fmt.usd))
            StatRow(label: "Resolves", value: snapshot?.endDate.map(Fmt.date))
        }
        .padding(.top, 2)
    }

    // Optional personalization — all of this can be left untouched.
    private var customize: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Label").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                TextField("optional", text: $labelText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .onChange(of: labelText) { _, new in store.setLabel(new, for: market) }
            }
            HStack(spacing: 6) {
                Text("Color").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                NoneSwatch(selected: market.colorName == nil) {
                    store.setColor(nil, for: market)
                }
                ForEach(MarketColor.allCases) { mc in
                    Swatch(color: mc.color, selected: market.colorName == mc.rawValue) {
                        store.setColor(mc.rawValue, for: market)
                    }
                }
            }
        }
    }

    // MARK: Derived chart values

    private var yDomain: ClosedRange<Double> {
        let ys = points.map { $0.p * 100 }
        guard let lo = ys.min(), let hi = ys.max() else { return 0...100 }
        let pad = Swift.max(1, (hi - lo) * 0.15)
        return Swift.max(0, lo - pad)...Swift.min(100, hi + pad)
    }

    private var trendColor: Color {
        let first = points.first?.p ?? 0
        let last = points.last?.p ?? 0
        return last >= first ? .green : .red
    }

    private var xAxisFormat: Date.FormatStyle {
        switch interval {
        case .oneHour, .sixHour, .oneDay:
            return .dateTime.hour().minute()
        default:
            return .dateTime.month(.abbreviated).day()
        }
    }

    private func load() async {
        guard let token = market.trackedTokenId else { points = []; return }
        loading = true
        defer { loading = false }
        do {
            points = try await PolymarketAPI.priceHistory(tokenId: token, interval: interval)
        } catch {
            points = []
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String?

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
    }
}

private struct Swatch: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.primary, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
    }
}

private struct NoneSwatch: View {
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .strokeBorder(.secondary, lineWidth: 1)
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: "slash.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                )
                .overlay(Circle().strokeBorder(.primary, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .help("No color")
    }
}
