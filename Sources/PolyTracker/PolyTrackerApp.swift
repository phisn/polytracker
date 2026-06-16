import SwiftUI
import AppKit
import Combine

@main
struct PolyTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No real window — the UI lives in the status item popover. The Settings
        // scene is never opened (an accessory app has no menu to open it).
        Settings { EmptyView() }
    }
}

/// Owns the menu bar status item and the popover. Using a manual NSStatusItem
/// (instead of SwiftUI's MenuBarExtra) lets us render a colored, multi-segment
/// title — one segment per pinned market — which MenuBarExtra can't do reliably.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TrackedMarketsStore()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        // Re-render when the user toggles light/dark so plain text stays legible.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(themeChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        let host = NSHostingController(rootView: PopoverView().environmentObject(store))
        host.sizingOptions = [.preferredContentSize]   // popover resizes to content
        popover.behavior = .transient                  // closes when you click away
        popover.animates = false
        popover.contentViewController = host

        // Rebuild the menu bar title whenever markets, pins, colors, labels, or
        // snapshots change. Delivering on the main queue also defers past the
        // objectWillChange tick, so the @Published values are already updated.
        cancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.updateStatusTitle() }
            }
        updateStatusTitle()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Draws the menu bar content as an image: one rounded pill per pinned market,
    /// filled with its color, with the label + percentage inside in a contrasting
    /// color. Markets without a color render as plain, appearance-adapting text.
    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")

        let pinned = store.pinnedMarkets
        guard !pinned.isEmpty else {
            let glyph = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis",
                                accessibilityDescription: "PolyTracker")
            glyph?.isTemplate = true
            button.image = glyph
            return
        }

        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let snaps = pinned.map { store.snapshot(for: $0.id) }
        let image = Self.renderTitle(markets: pinned, snapshots: snaps,
                                     dark: dark, height: NSStatusBar.system.thickness)
        image.isTemplate = false
        button.image = image
    }

    @objc private func themeChanged() { updateStatusTitle() }

    private static func renderTitle(markets: [TrackedMarket], snapshots: [MarketSnapshot?],
                                    dark: Bool, height: CGFloat) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let pillH: CGFloat = 17
        let hPad: CGFloat = 7       // padding inside a colored pill
        let gap: CGFloat = 9        // space between predictions (≈ inter-widget gap)
        let plain: NSColor = dark ? .white : .black

        struct Seg {
            let text: NSString
            let attrs: [NSAttributedString.Key: Any]
            let size: NSSize
            let fill: NSColor?
        }

        var segs: [Seg] = []
        for (i, m) in markets.enumerated() {
            var s = ""
            if let l = m.label, !l.isEmpty { s += l + " " }
            s += snapshots[i].map { Fmt.percent($0.probability) } ?? "—"
            let fill = m.colorName.flatMap(MarketColor.init)?.nsColor
            let textColor = fill.map(Self.contrastingText(on:)) ?? plain
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let text = s as NSString
            segs.append(Seg(text: text, attrs: attrs,
                            size: text.size(withAttributes: attrs), fill: fill))
        }

        var width: CGFloat = 2
        for (i, seg) in segs.enumerated() {
            if i > 0 { width += gap }
            width += seg.fill != nil ? seg.size.width + hPad * 2 : seg.size.width
        }

        return NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 1
            for (i, seg) in segs.enumerated() {
                if i > 0 { x += gap }
                let ty = (height - seg.size.height) / 2
                if let fill = seg.fill {
                    let pillW = seg.size.width + hPad * 2
                    let rect = NSRect(x: x, y: (height - pillH) / 2, width: pillW, height: pillH)
                    fill.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: pillH / 2, yRadius: pillH / 2).fill()
                    seg.text.draw(at: NSPoint(x: x + hPad, y: ty), withAttributes: seg.attrs)
                    x += pillW
                } else {
                    seg.text.draw(at: NSPoint(x: x, y: ty), withAttributes: seg.attrs)
                    x += seg.size.width
                }
            }
            return true
        }
    }

    /// Black or white text, whichever reads better on the given fill color.
    private static func contrastingText(on color: NSColor) -> NSColor {
        let c = color.usingColorSpace(.sRGB) ?? color
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return lum > 0.6 ? .black : .white
    }
}
