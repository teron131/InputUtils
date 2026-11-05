// Owns the idle-dimming schedule as pure rules: how long input must stop, how fast the fade falls, where it stops, and when an outside brightness change ends it.

import Foundation

/// Steps are equal on the brightness slider's scale, which is perceptual, so each one looks equally large.
enum IdleDimming {
  static let delay: TimeInterval = 5 * 60
  static let stepInterval: TimeInterval = 15
  static let floor: Float = 0.10
  private static let step: Float = 0.01
  private static let outsideChangeTolerance: Float = 0.005

  enum Phase: Equatable {
    case watching
    case dimming(baseline: Float, written: Float)
    /// Something other than the fade set the brightness, so the fade waits for input before it can start again.
    case overridden
  }

  /// Takes one step of the fade once input has stopped for at least `delay`, returning the next phase and the level to write, if any.
  static func advance(_ phase: Phase, level: Float, isPlaying: Bool) -> (
    phase: Phase, write: Float?
  ) {
    switch phase {
    case .watching:
      guard !isPlaying, isAboveFloor(level) else {
        return (.watching, nil)
      }

      let next = max(floor, level - step)
      return (.dimming(baseline: level, written: next), next)

    case .dimming(let baseline, let written):
      guard abs(level - written) <= outsideChangeTolerance else {
        return (.overridden, nil)
      }

      guard !isPlaying, isAboveFloor(written) else {
        return (phase, nil)
      }

      let next = max(floor, written - step)
      return (.dimming(baseline: baseline, written: next), next)

    case .overridden:
      return (.overridden, nil)
    }
  }

  /// Seconds from the last input until a fade starting at `level` reaches the floor, or `delay` when there is nothing to fade.
  static func fadeEnd(from level: Float) -> TimeInterval {
    let steps = max(0, ((level - floor - step / 2) / step).rounded(.up))
    return delay + TimeInterval(steps) * stepInterval
  }

  /// Repeated Float subtraction leaves the fade a hair above the floor, so anything within half a step of it counts as there.
  private static func isAboveFloor(_ level: Float) -> Bool {
    level - floor > step / 2
  }
}
