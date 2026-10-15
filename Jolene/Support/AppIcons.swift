import AppKit
import CoreImage
import UniformTypeIdentifiers

/// App icons by bundle identifier, kept for reuse.
final class AppIcons {
    static let shared = AppIcons()

    private var colorIcons: [String: NSImage] = [:]
    private var monochromeIcons: [String: NSImage] = [:]
    private let imageContext = CIContext()

    /// The app's icon, or the generic app icon when it isn't installed.
    func icon(for bundleID: String) -> NSImage {
        if let icon = colorIcons[bundleID] { return icon }
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        colorIcons[bundleID] = icon
        return icon
    }

    /// The app's icon in grayscale, for a quieter menu bar.
    func monochromeIcon(for bundleID: String) -> NSImage {
        if let icon = monochromeIcons[bundleID] { return icon }
        let color = icon(for: bundleID)
        let side: CGFloat = 64
        var rect = NSRect(x: 0, y: 0, width: side, height: side)
        guard let cgImage = color.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return color }
        let gray = CIImage(cgImage: cgImage).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        guard let output = imageContext.createCGImage(gray, from: gray.extent) else { return color }
        let icon = NSImage(cgImage: output, size: NSSize(width: side, height: side))
        monochromeIcons[bundleID] = icon
        return icon
    }

    /// Forgets an app's icons, so an update or a fresh install shows its current icon.
    func forget(_ bundleID: String) {
        colorIcons[bundleID] = nil
        monochromeIcons[bundleID] = nil
    }
}
