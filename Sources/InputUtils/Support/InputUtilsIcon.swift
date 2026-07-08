// Owns the shared waveform mark used by the menu bar and generated app icon.

import AppKit

enum InputUtilsIcon {
  /// Provides a template image so macOS can tint the menu bar mark for light and dark appearances.
  static let menuBarImage: NSImage = {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    NSColor.white.setFill()
    drawWaveformGlyph(in: CGRect(x: 2.5, y: 1.5, width: 13, height: 15))
    image.unlockFocus()
    image.isTemplate = true
    return image
  }()

  /// Draws the five-bar input mark inside the supplied rect.
  static func drawWaveformGlyph(in rect: CGRect) {
    let barWidth = rect.width * 0.13
    let gap = rect.width * 0.16
    let totalWidth = (barWidth * 5) + (gap * 4)
    let startX = rect.midX - (totalWidth / 2)
    let heightScales: [CGFloat] = [
      0.28,
      0.62,
      1.0,
      0.62,
      0.28,
    ]

    for index in 0..<5 {
      let barHeight = rect.height * heightScales[index]
      let x = startX + (CGFloat(index) * (barWidth + gap))
      let barRect = CGRect(
        x: x,
        y: rect.midY - (barHeight / 2),
        width: barWidth,
        height: barHeight
      )

      NSBezierPath(
        roundedRect: barRect,
        xRadius: barWidth / 2,
        yRadius: barWidth / 2
      )
      .fill()
    }
  }
}
