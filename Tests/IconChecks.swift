import AppKit

@MainActor
enum IconChecks {
    static func run(appURL: URL, iconURL: URL) throws {
        _ = NSApplication.shared
        guard let expected = NSImage(contentsOf: iconURL) else {
            throw CheckFailure.failed("System icon resource cannot be loaded.")
        }
        // A decodable ICNS and valid Info.plist do not guarantee that Icon Services
        // resolves the icon. Compare the image macOS actually supplies to callers.
        let resolved = NSWorkspace.shared.icon(forFile: appURL.path)
        let expectedPixels = try pixels(of: expected)
        let resolvedPixels = try pixels(of: resolved)
        let difference = zip(expectedPixels, resolvedPixels).reduce(0.0) {
            $0 + abs($1.0 - $1.1)
        } / Double(expectedPixels.count)
        try check(difference < 0.12,
                  "macOS returned a placeholder or incorrect app icon (image difference: \(difference)).")
        print("PASS: macOS resolves the bundled Clicky app icon.")
    }

    private static func pixels(of image: NSImage) throws -> [Double] {
        let size = 32
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CheckFailure.failed("Cannot render the system icon for verification.")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        var result: [Double] = []
        for y in 0..<size {
            for x in 0..<size {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    throw CheckFailure.failed("Cannot read the rendered icon colors.")
                }
                let alpha = Double(color.alphaComponent)
                result += [Double(color.redComponent) * alpha,
                           Double(color.greenComponent) * alpha,
                           Double(color.blueComponent) * alpha, alpha]
            }
        }
        return result
    }
}
