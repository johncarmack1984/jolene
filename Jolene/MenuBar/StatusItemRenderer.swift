import AppKit

/// What one menu bar item shows: an icon and, maybe, a badge.
struct StatusItemArtwork: Hashable {
    enum Icon: Hashable {
        /// The app's own icon, by bundle identifier.
        case app(String)
        /// The app's icon in grayscale, by bundle identifier.
        case monochromeApp(String)
        /// An SF Symbol, by name.
        case symbol(String)
    }

    var icon: Icon
    var badge: Badge?
    var style: MonitoredApp.BadgeStyle
    var dimmed: Bool

    init(icon: Icon, badge: Badge?, style: MonitoredApp.BadgeStyle, dimmed: Bool = false) {
        self.icon = icon
        self.badge = badge
        self.style = style
        self.dimmed = dimmed
    }

    init(app: MonitoredApp, badge: Badge?) {
        let icon: Icon = switch app.iconStyle {
        case .color: .app(app.bundleID)
        case .monochrome: .monochromeApp(app.bundleID)
        case .symbol: .symbol(app.symbolName)
        }
        self.init(icon: icon, badge: badge, style: app.badgeStyle, dimmed: app.dimWhenQuiet && badge == nil)
    }

    /// Artwork drawn only in the menu bar's text color becomes a template image, which macOS
    /// colors to match the menu bar exactly, in light, dark and tinted menu bars alike.
    var isTemplate: Bool {
        guard case .symbol = icon else { return false }
        guard badge != nil else { return true }
        return style == .number || style == .none
    }
}

/// Draws menu bar items. Every badge is measured with the font it's drawn in, so the item
/// grows to fit "12", "123" or "99+" instead of cutting them off.
enum StatusItemRenderer {
    static let height: CGFloat = 22
    static let appIconSide: CGFloat = 18
    static let symbolPointSize: CGFloat = 15
    static let badgeHeight: CGFloat = 13
    /// Small enough that one digit makes a circle, as on the Dock.
    static let badgePadding: CGFloat = 3
    /// How far a badge reaches back over the icon's right edge.
    static let badgeOverlap: CGFloat = 8
    static let badgeDotDiameter: CGFloat = 9
    static let dotDiameter: CGFloat = 7
    static let numberSpacing: CGFloat = 3
    static let dimmedAlpha: CGFloat = 0.4

    static var badgeFont: NSFont { .monospacedDigitSystemFont(ofSize: 10, weight: .bold) }
    static var numberFont: NSFont {
        .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    }

    struct Layout: Equatable {
        var size: NSSize
        var iconRect: NSRect
        /// The red badge, with `text` inside it.
        var badgeRect: NSRect?
        /// A red dot with no text.
        var dotRect: NSRect?
        /// Plain text beside the icon.
        var numberRect: NSRect?
        var text: String?
    }

    /// Where everything goes, in a flipped coordinate space with the origin at the top left.
    static func layout(for artwork: StatusItemArtwork, iconSize: NSSize) -> Layout {
        let iconRect = NSRect(
            x: 0,
            y: ((height - iconSize.height) / 2).rounded(),
            width: iconSize.width,
            height: iconSize.height
        )
        var layout = Layout(size: .zero, iconRect: iconRect)
        var width = iconRect.maxX

        if let badge = artwork.badge {
            switch artwork.style {
            case .badge where badge.kind == .dot:
                let rect = NSRect(x: iconRect.maxX - badgeDotDiameter + 3, y: 0.5, width: badgeDotDiameter, height: badgeDotDiameter)
                layout.dotRect = rect
                width = max(width, rect.maxX)
            case .badge:
                let text = badge.displayText
                let textWidth = measure(text, font: badgeFont).width
                let badgeWidth = max(badgeHeight, ceil(textWidth + badgePadding * 2))
                let rect = NSRect(x: iconRect.maxX - badgeOverlap, y: 0, width: badgeWidth, height: badgeHeight)
                layout.badgeRect = rect
                layout.text = text
                width = max(width, rect.maxX)
            case .dot:
                let rect = NSRect(x: iconRect.maxX - dotDiameter + 2, y: 1.5, width: dotDiameter, height: dotDiameter)
                layout.dotRect = rect
                width = max(width, rect.maxX)
            case .number:
                let text = badge.kind == .dot ? "•" : badge.displayText
                let size = measure(text, font: numberFont)
                let rect = NSRect(
                    x: iconRect.maxX + numberSpacing,
                    y: ((height - size.height) / 2).rounded(),
                    width: ceil(size.width),
                    height: ceil(size.height)
                )
                layout.numberRect = rect
                layout.text = text
                width = max(width, rect.maxX)
            case .none:
                break
            }
        }

        layout.size = NSSize(width: ceil(width), height: height)
        return layout
    }

    /// The finished image, with colors resolved for the given appearance.
    static func image(for artwork: StatusItemArtwork, appearance: NSAppearance) -> NSImage {
        let icon = iconImage(for: artwork.icon)
        let layout = layout(for: artwork, iconSize: iconSize(for: artwork.icon, image: icon))
        let template = artwork.isTemplate
        let image = NSImage(size: layout.size, flipped: true) { _ in
            appearance.performAsCurrentDrawingAppearance {
                draw(artwork, layout: layout, icon: icon, template: template)
            }
            return true
        }
        image.isTemplate = template
        return image
    }

    static func iconImage(for icon: StatusItemArtwork.Icon) -> NSImage {
        switch icon {
        case .app(let bundleID): AppIcons.shared.icon(for: bundleID)
        case .monochromeApp(let bundleID): AppIcons.shared.monochromeIcon(for: bundleID)
        case .symbol(let name): symbolImage(named: name)
        }
    }

    static func symbolImage(named name: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
            ?? NSImage()
        return symbol.withSymbolConfiguration(configuration) ?? symbol
    }

    static func iconSize(for icon: StatusItemArtwork.Icon, image: NSImage) -> NSSize {
        switch icon {
        case .app, .monochromeApp:
            NSSize(width: appIconSide, height: appIconSide)
        case .symbol:
            NSSize(width: ceil(image.size.width), height: min(ceil(image.size.height), height))
        }
    }

    static func measure(_ text: String, font: NSFont) -> NSSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private static func draw(_ artwork: StatusItemArtwork, layout: Layout, icon: NSImage, template: Bool) {
        let alpha = artwork.dimmed ? dimmedAlpha : 1
        let foreground: NSColor = template ? .black : .labelColor

        if case .symbol = artwork.icon, !template {
            drawTinted(icon, in: layout.iconRect, color: foreground, alpha: alpha)
        } else {
            icon.draw(in: layout.iconRect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        }

        if let rect = layout.badgeRect {
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            if let text = layout.text {
                drawCentered(text, font: badgeFont, color: .white, in: rect)
            }
        }
        if let rect = layout.dotRect {
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
        if let rect = layout.numberRect, let text = layout.text {
            (text as NSString).draw(at: rect.origin, withAttributes: [.font: numberFont, .foregroundColor: foreground])
        }
    }

    /// Centers digits by their cap height, so they sit in the middle of the badge rather than high.
    private static func drawCentered(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        let baseline = rect.midY + font.capHeight / 2
        let origin = NSPoint(x: rect.midX - size.width / 2, y: baseline - font.ascender)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    /// Draws a template image in one color, keeping its shape.
    private static func drawTinted(_ image: NSImage, in rect: NSRect, color: NSColor, alpha: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        color.setFill()
        rect.fill(using: .sourceIn)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

/// The single combined item: icons of the apps with something new, then the total.
struct CombinedArtwork: Hashable {
    var icons: [StatusItemArtwork.Icon]
    var total: Badge?

    static let maximumIcons = 4
}

extension StatusItemRenderer {
    static let combinedIconSide: CGFloat = 16
    static let combinedIconSpacing: CGFloat = 3

    static func image(for artwork: CombinedArtwork, appearance: NSAppearance) -> NSImage {
        guard !artwork.icons.isEmpty else {
            let symbol = symbolImage(named: "app.badge")
            symbol.isTemplate = true
            return symbol
        }

        let icons = artwork.icons.prefix(CombinedArtwork.maximumIcons).map { ($0, iconImage(for: $0)) }
        var iconRects: [NSRect] = []
        var x: CGFloat = 0
        for _ in icons {
            iconRects.append(NSRect(x: x, y: ((height - combinedIconSide) / 2).rounded(), width: combinedIconSide, height: combinedIconSide))
            x += combinedIconSide + combinedIconSpacing
        }
        var badgeRect: NSRect?
        let text = artwork.total?.displayText ?? ""
        if artwork.total != nil {
            let badgeWidth = max(badgeHeight, ceil(measure(text, font: badgeFont).width + badgePadding * 2))
            badgeRect = NSRect(x: x, y: ((height - badgeHeight) / 2).rounded(), width: badgeWidth, height: badgeHeight)
            x += badgeWidth
        } else {
            x -= combinedIconSpacing
        }

        let image = NSImage(size: NSSize(width: ceil(x), height: height), flipped: true) { _ in
            appearance.performAsCurrentDrawingAppearance {
                for ((icon, iconImage), rect) in zip(icons, iconRects) {
                    if case .symbol = icon {
                        drawTinted(iconImage, in: rect, color: .labelColor, alpha: 1)
                    } else {
                        iconImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    }
                }
                if let badgeRect {
                    NSColor.systemRed.setFill()
                    NSBezierPath(roundedRect: badgeRect, xRadius: badgeRect.height / 2, yRadius: badgeRect.height / 2).fill()
                    if !text.isEmpty {
                        drawCentered(text, font: badgeFont, color: .white, in: badgeRect)
                    }
                }
            }
            return true
        }
        return image
    }
}
