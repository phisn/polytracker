import SwiftUI

struct MarketRowView: View {
    let market: TrackedMarket
    let snapshot: MarketSnapshot?
    let onTogglePin: () -> Void

    private var accent: Color? { market.colorName.flatMap(MarketColor.init)?.color }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Identity color strip on the leading edge. Reserves its width even when
            // no color is set, so every row stays aligned.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent ?? .clear)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(market.question)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let label = market.label, !label.isEmpty {
                        Text(label)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background((accent ?? .secondary).opacity(0.18), in: Capsule())
                            .foregroundStyle(accent ?? .secondary)
                    }
                    if let v = snapshot?.volume24hr ?? snapshot?.volume {
                        Text("Vol \(Fmt.usd(v))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if let c = snapshot?.oneDayChange {
                        ChangeBadge(change: c)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(snapshot.map { Fmt.percent($0.probability) } ?? "—")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Button(action: onTogglePin) {
                Image(systemName: market.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(market.pinned ? (accent ?? Color.accentColor)
                                                   : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .help(market.pinned ? "Shown in menu bar — click to unpin" : "Pin to menu bar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// Up/down 24h change indicator, e.g. "▲ 3.1".
struct ChangeBadge: View {
    let change: Double      // 0..1 price delta

    private var up: Bool { change >= 0 }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            Text(Fmt.changeValue(change))
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(up ? Color.green : Color.red)
    }
}
