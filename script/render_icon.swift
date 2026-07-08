// Generates the Input Utils app icon from the same five-bar mark used in the menu bar.

import AppKit
import Foundation

@main
enum RenderIcon {
  static func main() throws {
    let outputPath = CommandLine.arguments.dropFirst().first
      ?? "dist/InputUtils.app/Contents/Resources/InputUtilsIcon.icns"
    let outputURL = URL(fileURLWithPath: outputPath)
    let resourcesURL = outputURL.deletingLastPathComponent()
    let iconsetURL = resourcesURL.appendingPathComponent("InputUtilsIcon.iconset")

    try FileManager.default.createDirectory(
      at: resourcesURL,
      withIntermediateDirectories: true
    )
    try? FileManager.default.removeItem(at: iconsetURL)
    try FileManager.default.createDirectory(
      at: iconsetURL,
      withIntermediateDirectories: true
    )

    let iconFiles: [(name: String, pixels: Int)] = [
      ("icon_16x16.png", 16),
      ("icon_16x16@2x.png", 32),
      ("icon_32x32.png", 32),
      ("icon_32x32@2x.png", 64),
      ("icon_128x128.png", 128),
      ("icon_128x128@2x.png", 256),
      ("icon_256x256.png", 256),
      ("icon_256x256@2x.png", 512),
      ("icon_512x512.png", 512),
      ("icon_512x512@2x.png", 1024),
    ]

    for iconFile in iconFiles {
      let url = iconsetURL.appendingPathComponent(iconFile.name)
      try renderIcon(pixels: iconFile.pixels).write(to: url)
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = [
      "--convert",
      "icns",
      iconsetURL.path,
      "--output",
      outputURL.path,
    ]

    try iconutil.run()
    iconutil.waitUntilExit()

    if iconutil.terminationStatus != 0 {
      throw NSError(
        domain: "InputUtilsIcon",
        code: Int(iconutil.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed"]
      )
    }

    try? FileManager.default.removeItem(at: iconsetURL)
  }
}

func renderIcon(pixels: Int) throws -> Data {
  guard
    let representation = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixels,
      pixelsHigh: pixels,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: representation)
  else {
    throw NSError(
      domain: "InputUtilsIcon",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Could not create icon bitmap"]
    )
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.cgContext.setShouldAntialias(true)
  context.cgContext.setAllowsAntialiasing(true)

  let size = CGFloat(pixels)
  NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
    xRadius: size * 0.22,
    yRadius: size * 0.22
  )
  .fill()

  NSColor.white.setFill()
  let glyphWidth = size * 0.52
  let glyphHeight = size * 0.64
  InputUtilsIcon.drawWaveformGlyph(
    in: CGRect(
      x: (size - glyphWidth) / 2,
      y: (size - glyphHeight) / 2,
      width: glyphWidth,
      height: glyphHeight
    )
  )

  NSGraphicsContext.restoreGraphicsState()

  guard let data = representation.representation(
    using: .png,
    properties: [:]
  ) else {
    throw NSError(
      domain: "InputUtilsIcon",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"]
    )
  }

  return data
}
