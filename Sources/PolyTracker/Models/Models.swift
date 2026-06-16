import Foundation

/// A market the user has chosen to track. Persisted to UserDefaults.
struct TrackedMarket: Codable, Identifiable, Hashable, Sendable {
    let id: String              // Gamma market id (stable)
    var question: String
    var slug: String            // market slug
    var eventSlug: String?      // parent event slug, used for the web link
    var outcomes: [String]      // e.g. ["Yes", "No"]
    var clobTokenIds: [String]  // parallel to `outcomes`; needed for price history
    var outcomeIndex: Int       // which outcome's probability we track (default 0 = "Yes")

    // Optional, user-set personalization — never required.
    var pinned: Bool            // shown in the menu bar (you can pin as many as you like)
    var label: String?          // short tag shown before the % (e.g. "Fed")
    var colorName: String?      // MarketColor.rawValue, used for the dot/strip

    var trackedTokenId: String? {
        guard outcomeIndex >= 0, outcomeIndex < clobTokenIds.count else { return nil }
        return clobTokenIds[outcomeIndex]
    }

    var trackedOutcomeName: String {
        guard outcomeIndex >= 0, outcomeIndex < outcomes.count else { return "Yes" }
        return outcomes[outcomeIndex]
    }

    /// Best public URL for this market.
    var webURL: URL? {
        let s = (eventSlug?.isEmpty == false ? eventSlug! : slug)
        guard !s.isEmpty else { return URL(string: "https://polymarket.com") }
        return URL(string: "https://polymarket.com/event/\(s)")
    }

    enum CodingKeys: String, CodingKey {
        case id, question, slug, eventSlug, outcomes, clobTokenIds, outcomeIndex, pinned, label, colorName
    }

    init(id: String, question: String, slug: String, eventSlug: String?,
         outcomes: [String], clobTokenIds: [String], outcomeIndex: Int = 0,
         pinned: Bool = true, label: String? = nil, colorName: String? = nil) {
        self.id = id
        self.question = question
        self.slug = slug
        self.eventSlug = eventSlug
        self.outcomes = outcomes
        self.clobTokenIds = clobTokenIds
        self.outcomeIndex = outcomeIndex
        self.pinned = pinned
        self.label = label
        self.colorName = colorName
    }

    init(from gm: GammaMarket, eventSlug: String?, fallbackTitle: String = "") {
        self.init(
            id: gm.id,
            question: gm.question ?? fallbackTitle,
            slug: gm.slug ?? "",
            eventSlug: eventSlug,
            outcomes: gm.outcomes,
            clobTokenIds: gm.clobTokenIds
        )
    }

    // Custom decoding so older saved data (which lacked pin/label/color) migrates cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        question = try c.decode(String.self, forKey: .question)
        slug = try c.decode(String.self, forKey: .slug)
        eventSlug = try c.decodeIfPresent(String.self, forKey: .eventSlug)
        outcomes = try c.decode([String].self, forKey: .outcomes)
        clobTokenIds = try c.decode([String].self, forKey: .clobTokenIds)
        outcomeIndex = (try? c.decode(Int.self, forKey: .outcomeIndex)) ?? 0
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? true
        label = try? c.decodeIfPresent(String.self, forKey: .label)
        colorName = try? c.decodeIfPresent(String.self, forKey: .colorName)
    }
}

/// Live data fetched for a tracked market.
struct MarketSnapshot: Sendable, Equatable {
    var probability: Double      // 0...1 for the tracked outcome
    var volume: Double?          // total volume (USD)
    var volume24hr: Double?
    var liquidity: Double?
    var oneDayChange: Double?    // change in price (0..1) over the last 24h
    var endDate: Date?
    var updatedAt: Date
}

/// One point on the price-history chart.
struct PricePoint: Sendable, Identifiable, Equatable {
    let t: Date
    let p: Double                // 0...1
    var id: TimeInterval { t.timeIntervalSince1970 }
}

/// Time window for the detail chart. Raw value maps to the CLOB `interval` param.
enum ChartInterval: String, CaseIterable, Identifiable, Sendable {
    case oneHour = "1h"
    case sixHour = "6h"
    case oneDay  = "1d"
    case oneWeek = "1w"
    case oneMonth = "1m"
    case max = "max"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneHour: "1H"
        case .sixHour: "6H"
        case .oneDay:  "1D"
        case .oneWeek: "1W"
        case .oneMonth: "1M"
        case .max:     "MAX"
        }
    }

    /// `fidelity` (minutes between points) tuned per window to balance detail vs payload.
    var fidelity: Int {
        switch self {
        case .oneHour: 1
        case .sixHour: 5
        case .oneDay:  15
        case .oneWeek: 60
        case .oneMonth: 180
        case .max:     720
        }
    }
}
