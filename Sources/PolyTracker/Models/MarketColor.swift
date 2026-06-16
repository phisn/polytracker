import SwiftUI
import AppKit

/// A small fixed palette for optionally color-coding markets. Chosen to stay
/// reasonably legible on both light and dark menu bars.
enum MarketColor: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }
}
