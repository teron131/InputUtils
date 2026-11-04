// Owns the mark behind the menu bar image and generated app icon: a mouse whose palm carries microphone grille lines, one glyph for the app's mouse and mic controls.

import AppKit

enum InputUtilsIcon {
  /// Provides a template image so macOS can tint the menu bar mark for light and dark appearances.
  static let menuBarImage: NSImage = {
    let image = NSImage(size: NSSize(width: gridSize, height: gridSize), flipped: false) { rect in
      NSColor.white.setFill()
      NSBezierPath(cgPath: scaled(gridMenuBarMark, into: rect)).fill()
      return true
    }
    image.isTemplate = true
    return image
  }()

  /// Returns the outline mark as one fillable path scaled into `rect`, which should be square.
  static func markPath(in rect: CGRect) -> CGPath {
    scaled(gridOutlineMark, into: rect)
  }

  // Geometry below sits on an 18-point design grid with its origin at the bottom left.
  private static let gridSize: CGFloat = 18
  private static let body = CGRect(x: 4.75, y: 1.75, width: 8.5, height: 14.5)
  private static let outlineWidth: CGFloat = 1.5

  /// The button seam, grille, and wheel: drawn in the outline mark and cut out of the menu bar mark's solid half.
  private static let details: CGPath = {
    let seam = CGMutablePath()
    seam.move(to: CGPoint(x: 9, y: 16.25))
    seam.addLine(to: CGPoint(x: 9, y: 14.2))

    let grille = CGMutablePath()
    for y: CGFloat in [4.6, 6.6, 8.6] {
      grille.move(to: CGPoint(x: 7.2, y: y))
      grille.addLine(to: CGPoint(x: 10.8, y: y))
    }

    let wheel = CGPath(
      roundedRect: CGRect(x: 8.15, y: 11, width: 1.7, height: 3.2),
      cornerWidth: 0.85,
      cornerHeight: 0.85,
      transform: nil
    )

    return
      seam
      .copy(strokingWithWidth: outlineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
      .union(grille.copy(strokingWithWidth: 1.1, lineCap: .round, lineJoin: .round, miterLimit: 10))
      .union(wheel)
  }()

  private static let gridOutlineMark: CGPath =
    capsule(body)
    .copy(strokingWithWidth: outlineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
    .union(details)

  /// Echoes the app icon's split in one color: the left half is solid with the details cut out, the right half is the outline mark.
  private static let gridMenuBarMark: CGPath = {
    let (left, right) = CGRect(x: 0, y: 0, width: gridSize, height: gridSize)
      .divided(atDistance: gridSize / 2, from: .minXEdge)
    return capsule(body.insetBy(dx: -outlineWidth / 2, dy: -outlineWidth / 2))
      .intersection(CGPath(rect: left, transform: nil))
      .subtracting(details)
      .union(gridOutlineMark.intersection(CGPath(rect: right, transform: nil)))
  }()

  private static func capsule(_ rect: CGRect) -> CGPath {
    CGPath(
      roundedRect: rect, cornerWidth: rect.width / 2, cornerHeight: rect.width / 2, transform: nil)
  }

  private static func scaled(_ path: CGPath, into rect: CGRect) -> CGPath {
    let scaledPath = CGMutablePath()
    scaledPath.addPath(
      path,
      transform: CGAffineTransform(translationX: rect.minX, y: rect.minY)
        .scaledBy(x: rect.width / gridSize, y: rect.height / gridSize)
    )
    return scaledPath
  }
}
