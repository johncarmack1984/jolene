import AppKit
import Testing
@testable import Jolene

struct StatusItemRendererTests {
    private let iconSize = NSSize(width: StatusItemRenderer.appIconSide, height: StatusItemRenderer.appIconSide)

    private func layout(_ label: String?, style: MonitoredApp.BadgeStyle = .badge) -> StatusItemRenderer.Layout {
        let artwork = StatusItemArtwork(icon: .app("com.apple.finder"), badge: Badge(label: label), style: style)
        return StatusItemRenderer.layout(for: artwork, iconSize: iconSize)
    }

    @Test func iconAloneIsIconSized() {
        let layout = layout(nil)
        #expect(layout.size == NSSize(width: StatusItemRenderer.appIconSide, height: StatusItemRenderer.height))
        #expect(layout.badgeRect == nil)
    }

    /// The badge grows with its text instead of cutting it off, which is how Doll broke
    /// on two-digit counts.
    @Test(arguments: ["3", "12", "123", "99+", "1,204"])
    func badgeTextAlwaysFits(_ label: String) throws {
        let layout = layout(label)
        let rect = try #require(layout.badgeRect)
        let textWidth = StatusItemRenderer.measure(label, font: StatusItemRenderer.badgeFont).width
        #expect(rect.width >= textWidth + StatusItemRenderer.badgePadding * 2 - 0.5)
        #expect(rect.maxX <= layout.size.width)
        #expect(rect.height <= layout.size.height)
    }

    @Test func widerLabelsMakeWiderItems() {
        let widths = ["3", "12", "123"].map { layout($0).size.width }
        #expect(widths[0] < widths[1])
        #expect(widths[1] < widths[2])
    }

    @Test func singleDigitsGetARoundBadge() throws {
        let rect = try #require(layout("3").badgeRect)
        #expect(rect.width == rect.height)
    }

    @Test func numberStylePutsTextBesideTheIcon() throws {
        let layout = layout("12", style: .number)
        let rect = try #require(layout.numberRect)
        #expect(rect.minX >= layout.iconRect.maxX)
        #expect(rect.maxX <= layout.size.width)
        #expect(layout.text == "12")
    }

    @Test func dotsDrawWithoutText() {
        #expect(layout("•").dotRect != nil)
        #expect(layout("•").badgeRect == nil)
        #expect(layout("12", style: .dot).dotRect != nil)
        #expect(layout("12", style: .none).size.width == StatusItemRenderer.appIconSide)
    }

    @Test func symbolsBecomeTemplatesUnlessTheyCarryColor() {
        let badge = Badge(label: "3")
        #expect(StatusItemArtwork(icon: .symbol("envelope"), badge: nil, style: .badge).isTemplate)
        #expect(StatusItemArtwork(icon: .symbol("envelope"), badge: badge, style: .number).isTemplate)
        #expect(!StatusItemArtwork(icon: .symbol("envelope"), badge: badge, style: .badge).isTemplate)
        #expect(!StatusItemArtwork(icon: .app("com.apple.mail"), badge: nil, style: .badge).isTemplate)
    }

    @Test func dimmingOnlyWhenQuiet() {
        let app = MonitoredApp(bundleID: "com.apple.mail", name: "Mail", dimWhenQuiet: true)
        #expect(StatusItemArtwork(app: app, badge: nil).dimmed)
        #expect(!StatusItemArtwork(app: app, badge: Badge(label: "1")).dimmed)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func drawsARedBadge(_ appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        let artwork = StatusItemArtwork(icon: .app("com.apple.finder"), badge: Badge(label: "12"), style: .badge)
        let image = StatusItemRenderer.image(for: artwork, appearance: appearance)
        let layout = StatusItemRenderer.layout(for: artwork, iconSize: iconSize)
        #expect(image.size == layout.size)

        let bitmap = try #require(render(image, scale: 2))
        let badgeRect = try #require(layout.badgeRect)
        // Sample the badge's right end, past the icon, where only red is drawn.
        let color = try #require(bitmap.colorAt(x: Int((badgeRect.maxX - 2) * 2), y: Int(badgeRect.midY * 2)))
        #expect(color.redComponent > 0.8)
        #expect(color.greenComponent < 0.4)
    }

    @Test func everySuggestedSymbolExists() {
        for name in SymbolSuggestions.all {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "Missing SF Symbol \(name)")
        }
    }

    /// Symbols in the combined item keep their proportions instead of being squeezed square.
    @Test func combinedIconsKeepTheirProportions() {
        let side = StatusItemRenderer.combinedIconSide
        let rects = StatusItemRenderer.combinedIconRects(for: [NSSize(width: 18, height: 18), NSSize(width: 22, height: 16), NSSize(width: 25, height: 18)])
        #expect(rects.map(\.height) == [side, side, side])
        #expect(rects[0].width == side)
        #expect(rects[1].width == 22)
        #expect(rects[2].width == ceil(25 * side / 18))
        #expect(rects[1].minX == rects[0].maxX + StatusItemRenderer.combinedIconSpacing)
    }

    @Test func combinedItemFallsBackToTheJoleneSymbol() {
        let image = StatusItemRenderer.image(for: CombinedArtwork(icons: [], total: nil), appearance: NSAppearance(named: .aqua)!)
        #expect(image.isTemplate)
    }

    /// Draws an image into a bitmap with a top-left origin, matching the layout's coordinates.
    private func render(_ image: NSImage, scale: CGFloat) -> NSBitmapImageRep? {
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
