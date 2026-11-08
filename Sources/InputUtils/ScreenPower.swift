// Estimates how much power dimming saves, from figures measured through macOS's power log on a 15-inch MacBook Air (M5), the same ones the README's cost table shows; other models differ, so callers present the results as approximate.

enum ScreenPower {
  /// Watts at points along the slider; power follows the backlight, which stays off across the bottom 15% and grows faster than the perceptual slider above it.
  private static let measured: [(level: Float, watts: Double)] = [
    (0.15, 0), (0.25, 0.2), (0.50, 2), (0.75, 4), (1, 8),
  ]
  /// The rest of the Mac while idle, which is when the fade runs.
  private static let restOfMacWatts = 2.4

  /// The fraction of the whole idle Mac's power that dimming from one level to the other saves.
  static func savedShare(from start: Float, to end: Float) -> Double {
    (watts(at: start) - watts(at: end)) / (restOfMacWatts + watts(at: start))
  }

  /// Interpolates linearly between the measured points.
  private static func watts(at level: Float) -> Double {
    for (low, high) in zip(measured, measured.dropFirst()) where level <= high.level {
      let fraction = Double(max(0, level - low.level) / (high.level - low.level))
      return low.watts + (high.watts - low.watts) * fraction
    }
    return measured[measured.count - 1].watts
  }
}
