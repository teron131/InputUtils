// Generates the Input Utils app icon: the outline mouse mark on a squircle split into silver and graphite halves, each half drawing the mark in the other's color.

import AppKit
import Foundation

@main
enum RenderIcon {
  static func main() throws {
    let outputPath =
      CommandLine.arguments.dropFirst().first
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
  let cg = context.cgContext
  cg.setShouldAntialias(true)
  cg.setAllowsAntialiasing(true)

  let silver = CGColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1)
  let graphite = CGColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)

  // macOS icon grid: an 824-point body with 185-point corners and a drop shadow, centered on a 1024 canvas.
  let unit = CGFloat(pixels) / 1024
  let body = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
  let shape = CGPath(
    roundedRect: body,
    cornerWidth: 185 * unit,
    cornerHeight: 185 * unit,
    transform: nil
  )

  cg.saveGState()
  cg.setShadow(
    offset: CGSize(width: 0, height: -10 * unit),
    blur: 20 * unit,
    color: CGColor(gray: 0, alpha: 0.3)
  )
  cg.addPath(shape)
  cg.setFillColor(graphite)
  cg.fillPath()
  cg.restoreGState()

  cg.addPath(shape)
  cg.clip()

  let mark = InputUtilsIcon.markPath(
    in: body.insetBy(dx: body.width * 0.15, dy: body.height * 0.15))
  let (left, right) = body.divided(atDistance: body.width / 2, from: .minXEdge)
  for (half, background, ink) in [(left, silver, graphite), (right, graphite, silver)] {
    cg.saveGState()
    cg.clip(to: half)
    cg.setFillColor(background)
    cg.fill(half)
    cg.addPath(mark)
    cg.setFillColor(ink)
    cg.fillPath()
    cg.restoreGState()
  }

  // Light on dark reads bolder than dark on light, so a graphite edge reaching 3.5 points either side of the outline thickens the left mark and thins the right one until the halves look equal.
  cg.addPath(mark)
  cg.setStrokeColor(graphite)
  cg.setLineWidth(7 * unit)
  cg.setLineJoin(.round)
  cg.strokePath()

  let sheen = CGGradient(
    colorsSpace: nil,
    colors: [
      CGColor(gray: 1, alpha: 0.14),
      CGColor(gray: 1, alpha: 0),
      CGColor(gray: 0, alpha: 0.1),
    ] as CFArray,
    locations: [0, 0.55, 1]
  )!
  cg.drawLinearGradient(
    sheen,
    start: CGPoint(x: body.midX, y: body.maxY),
    end: CGPoint(x: body.midX, y: body.minY),
    options: []
  )

  NSGraphicsContext.restoreGraphicsState()

  guard
    let data = representation.representation(
      using: .png,
      properties: [:]
    )
  else {
    throw NSError(
      domain: "InputUtilsIcon",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"]
    )
  }

  return data
}
