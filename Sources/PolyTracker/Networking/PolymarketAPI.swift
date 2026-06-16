import Foundation

// MARK: - Wire models

/// A market as returned by the Gamma API. Several fields arrive as JSON-encoded
/// *strings* (`outcomes`, `outcomePrices`, `clobTokenIds`) and numbers sometimes
/// arrive as strings, so decoding is deliberately tolerant.
struct GammaMarket: Decodable, Sendable {
    let id: String
    let question: String?
    let slug: String?
    let conditionId: String?
    let outcomes: [String]
    let clobTokenIds: [String]
    let outcomePrices: [Double]
    let volume: Double?
    let volume24hr: Double?
    let liquidity: Double?
    let oneDayPriceChange: Double?
    let lastTradePrice: Double?
    let endDate: Date?
    let active: Bool?
    let closed: Bool?

    enum CodingKeys: String, CodingKey {
        case id, question, slug, conditionId, outcomes, clobTokenIds, outcomePrices
        case volume, volume24hr, liquidity, oneDayPriceChange, lastTradePrice, endDate, active, closed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleString(.id) ?? ""
        question = try? c.decode(String.self, forKey: .question)
        slug = try? c.decode(String.self, forKey: .slug)
        conditionId = try? c.decode(String.self, forKey: .conditionId)
        outcomes = c.stringList(.outcomes)
        clobTokenIds = c.stringList(.clobTokenIds)
        outcomePrices = c.stringList(.outcomePrices).compactMap(Double.init)
        volume = c.flexibleDouble(.volume)
        volume24hr = c.flexibleDouble(.volume24hr)
        liquidity = c.flexibleDouble(.liquidity)
        oneDayPriceChange = c.flexibleDouble(.oneDayPriceChange)
        lastTradePrice = c.flexibleDouble(.lastTradePrice)
        active = try? c.decode(Bool.self, forKey: .active)
        closed = try? c.decode(Bool.self, forKey: .closed)
        endDate = DateParse.parse(try? c.decode(String.self, forKey: .endDate))
    }

    /// Probability (0...1) for a given outcome, falling back to the last trade price.
    func probability(forOutcome i: Int) -> Double? {
        if i >= 0, i < outcomePrices.count { return outcomePrices[i] }
        return lastTradePrice
    }

    var isTradeable: Bool { active != false && closed != true }
}

private struct SearchResponse: Decodable { let events: [SearchEvent]? }

struct SearchEvent: Decodable, Sendable {
    let title: String?
    let slug: String?
    let markets: [GammaMarket]?
}

/// A flattened search hit shown in the "add market" list.
struct SearchResultItem: Identifiable, Sendable {
    let eventTitle: String
    let eventSlug: String?
    let market: GammaMarket
    var id: String { market.id.isEmpty ? (market.slug ?? eventTitle) : market.id }
}

private struct PriceHistoryResponse: Decodable {
    let history: [Point]
    struct Point: Decodable { let t: Double; let p: Double }
}

// MARK: - API

enum APIError: LocalizedError {
    case http(Int)
    case notFound

    var errorDescription: String? {
        switch self {
        case .http(let code): "Request failed (HTTP \(code))"
        case .notFound: "Market not found"
        }
    }
}

enum PolymarketAPI {
    static let gamma = URL(string: "https://gamma-api.polymarket.com")!
    static let clob = URL(string: "https://clob.polymarket.com")!

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    private static func get<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Discovery

    /// Search by keyword, or resolve a pasted Polymarket URL.
    static func search(_ raw: String) async throws -> [SearchResultItem] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }

        if let slug = polymarketSlug(from: q) {
            if let ms = try? await markets(slug: slug), !ms.isEmpty {
                return ms.filter(\.isTradeable)
                    .map { SearchResultItem(eventTitle: $0.question ?? slug, eventSlug: slug, market: $0) }
            }
            if let evs = try? await events(slug: slug) {
                let items = evs.flatMap { e in
                    (e.markets ?? []).filter(\.isTradeable)
                        .map { SearchResultItem(eventTitle: e.title ?? "", eventSlug: e.slug, market: $0) }
                }
                if !items.isEmpty { return items }
            }
            // Fall through to keyword search using the slug words.
            return try await publicSearch(slug.replacingOccurrences(of: "-", with: " "))
        }

        return try await publicSearch(q)
    }

    private static func publicSearch(_ q: String) async throws -> [SearchResultItem] {
        var c = URLComponents(url: gamma.appendingPathComponent("public-search"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "limit_per_type", value: "15"),
            URLQueryItem(name: "events_status", value: "active"),
        ]
        let resp = try await get(c.url!, as: SearchResponse.self)
        return (resp.events ?? []).flatMap { e in
            (e.markets ?? []).filter(\.isTradeable)
                .map { SearchResultItem(eventTitle: e.title ?? ($0.question ?? ""), eventSlug: e.slug, market: $0) }
        }
    }

    // MARK: Market metadata

    static func market(id: String) async throws -> GammaMarket {
        let url = gamma.appendingPathComponent("markets").appendingPathComponent(id)
        if let one = try? await get(url, as: GammaMarket.self) { return one }
        let arr = try await get(url, as: [GammaMarket].self)
        guard let first = arr.first else { throw APIError.notFound }
        return first
    }

    static func markets(slug: String) async throws -> [GammaMarket] {
        var c = URLComponents(url: gamma.appendingPathComponent("markets"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "slug", value: slug)]
        return try await get(c.url!, as: [GammaMarket].self)
    }

    static func events(slug: String) async throws -> [SearchEvent] {
        var c = URLComponents(url: gamma.appendingPathComponent("events"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "slug", value: slug)]
        return try await get(c.url!, as: [SearchEvent].self)
    }

    // MARK: Price history

    static func priceHistory(tokenId: String, interval: ChartInterval) async throws -> [PricePoint] {
        var c = URLComponents(url: clob.appendingPathComponent("prices-history"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "market", value: tokenId),
            URLQueryItem(name: "interval", value: interval.rawValue),
            URLQueryItem(name: "fidelity", value: String(interval.fidelity)),
        ]
        let resp = try await get(c.url!, as: PriceHistoryResponse.self)
        return resp.history.map { PricePoint(t: Date(timeIntervalSince1970: $0.t), p: $0.p) }
    }

    // MARK: Helpers

    /// Extract a slug from a pasted Polymarket URL, else nil.
    private static func polymarketSlug(from text: String) -> String? {
        guard text.lowercased().contains("polymarket.com") else { return nil }
        var s = text
        if !s.lowercased().hasPrefix("http") { s = "https://\(s)" }
        guard let comps = URLComponents(string: s) else { return nil }
        let parts = comps.path.split(separator: "/").map(String.init)
        return parts.last
    }
}

// MARK: - Tolerant decoding helpers

private extension KeyedDecodingContainer {
    func flexibleDouble(_ key: Key) -> Double? {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key) { return Double(s) }
        return nil
    }

    func flexibleString(_ key: Key) -> String? {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        if let d = try? decode(Double.self, forKey: key) { return String(Int(d)) }
        return nil
    }

    /// Gamma returns these as a JSON-encoded string; tolerate a real array too.
    func stringList(_ key: Key) -> [String] {
        if let arr = try? decode([String].self, forKey: key) { return arr }
        if let s = try? decode(String.self, forKey: key),
           let data = s.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            return arr
        }
        return []
    }
}

enum DateParse {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return withFractional.date(from: s) ?? plain.date(from: s)
    }
}
