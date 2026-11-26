import AppKit
import Foundation

@main
struct GenerateIcon {
    static func main() throws {
        let fileManager = FileManager.default
        let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset")
        let icnsURL = URL(fileURLWithPath: "Resources/AppIcon.icns")

        try? fileManager.removeItem(at: iconsetURL)
        try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        let entries: [(name: String, size: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for entry in entries {
            guard let data = renderPNG(size: entry.size) else {
                throw IconError.renderFailed(entry.size)
            }
            try data.write(to: iconsetURL.appendingPathComponent(entry.name))
        }

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = [
            "-c", "icns",
            iconsetURL.path,
            "-o", icnsURL.path
        ]
        try iconutil.run()
        iconutil.waitUntilExit()

        guard iconutil.terminationStatus == 0 else {
            throw IconError.iconutilFailed(iconutil.terminationStatus)
        }

        print("Готово: \(icnsURL.path)")
    }

    private static func renderPNG(size: Int) -> Data? {
        let s = CGFloat(size)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        representation.size = NSSize(width: s, height: s)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setAllowsAntialiasing(true)
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        let inset = s * 0.055
        let bounds = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let background = NSBezierPath(
            roundedRect: bounds,
            xRadius: s * 0.225,
            yRadius: s * 0.225
        )

        let backgroundGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.82, alpha: 1),
            NSColor(calibratedRed: 0.30, green: 0.72, blue: 1.00, alpha: 1)
        ])
        backgroundGradient?.draw(in: background, angle: -50)

        let phoneWidth = s * 0.34
        let phoneHeight = s * 0.62
        let phoneRect = NSRect(
            x: (s - phoneWidth) / 2,
            y: (s - phoneHeight) / 2 - s * 0.005,
            width: phoneWidth,
            height: phoneHeight
        )
        let phone = NSBezierPath(
            roundedRect: phoneRect,
            xRadius: s * 0.075,
            yRadius: s * 0.075
        )
        NSColor.white.withAlphaComponent(0.96).setFill()
        phone.fill()

        let screenRect = phoneRect.insetBy(dx: s * 0.016, dy: s * 0.016)
        let screen = NSBezierPath(
            roundedRect: screenRect,
            xRadius: s * 0.06,
            yRadius: s * 0.06
        )
        let screenGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.04, green: 0.13, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.90, alpha: 1)
        ])
        screenGradient?.draw(in: screen, angle: -90)

        let notchWidth = phoneWidth * 0.34
        let notchHeight = max(phoneHeight * 0.032, s * 0.012)
        let notchRect = NSRect(
            x: phoneRect.midX - notchWidth / 2,
            y: phoneRect.maxY - notchHeight - s * 0.012,
            width: notchWidth,
            height: notchHeight
        )
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(
            roundedRect: notchRect,
            xRadius: notchHeight / 2,
            yRadius: notchHeight / 2
        ).fill()

        let homeWidth = phoneWidth * 0.26
        let homeHeight = max(phoneHeight * 0.011, s * 0.006)
        let homeRect = NSRect(
            x: phoneRect.midX - homeWidth / 2,
            y: phoneRect.minY + s * 0.022,
            width: homeWidth,
            height: homeHeight
        )
        NSColor.white.withAlphaComponent(0.78).setFill()
        NSBezierPath(
            roundedRect: homeRect,
            xRadius: homeHeight / 2,
            yRadius: homeHeight / 2
        ).fill()

        return representation.representation(using: .png, properties: [:])
    }
}

enum IconError: LocalizedError {
    case renderFailed(Int)
    case iconutilFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let size):
            return "Не удалось отрисовать иконку \(size)×\(size)"
        case .iconutilFailed(let code):
            return "iconutil завершился с кодом \(code)"
        }
    }
}
