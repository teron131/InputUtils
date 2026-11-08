// Owns the idle-dimming schedule as pure rules: how long input must stop, how long the fade takes, where it stops, and when an outside brightness change ends it.

import Foundation

enum IdleDimming {
  /// A running fade steps this often, which also bounds how long a brightness-key press during a fade goes unnoticed.
  static let stepInterval: TimeInterval = 15
  /// Half a slider point: the slider moves in whole points, so a smaller difference between two levels is noise rather than a change.
  private static let tolerance: Float = 0.005

  enum Phase: Equatable {
    case watching
    case dimming(baseline: Float, written: Float)
    /// Something other than the fade set the brightness, so the fade waits for input before it can start again.
    case overridden
  }

  /// The person's choices: how long input must stop, how long the fade then takes, and the level it ends at.
  struct Schedule {
    var delay: TimeInterval
    var duration: TimeInterval
    var floor: Float

    static let standard = Schedule(delay: 5 * 60, duration: 10 * 60, floor: 0.10)

    /// Takes one step of the fade once input has stopped for at least `delay`, returning the next phase and the level to write, if any.
    func advance(_ phase: Phase, level: Float, isPlaying: Bool) -> (phase: Phase, write: Float?) {
      switch phase {
      case .watching:
        guard !isPlaying, fades(from: level) else {
          return (.watching, nil)
        }

        let next = stepDown(from: level, baseline: level)
        return (.dimming(baseline: level, written: next), next)

      case .dimming(let baseline, let written):
        guard abs(level - written) <= tolerance else {
          return (.overridden, nil)
        }

        guard !isPlaying, written > floor else {
          return (phase, nil)
        }

        let next = stepDown(from: written, baseline: baseline)
        return (.dimming(baseline: baseline, written: next), next)

      case .overridden:
        return (.overridden, nil)
      }
    }

    /// Waits until idle time could reach `delay`, then checks once per step.
    func nextCheck(afterIdle idle: TimeInterval) -> TimeInterval {
      idle < delay ? delay - idle : IdleDimming.stepInterval
    }

    func fades(from level: Float) -> Bool {
      level - floor > tolerance
    }

    /// Steps are equal on the slider's scale, which is perceptual, so each looks equally large; sizing them by the starting level makes every fade take `duration`.
    /// The last step lands exactly on the floor, since Float arithmetic leaves the running level a hair off it.
    private func stepDown(from written: Float, baseline: Float) -> Float {
      let step = (baseline - floor) * Float(IdleDimming.stepInterval / duration)
      let next = written - step
      return next - floor < step / 2 ? floor : next
    }
  }

  /// Returns the starting level, or nil when a change the person made during the fade should stay instead: dimming further, or raising it at least back to the starting level.
  /// Raising it only part of the way still gets the starting level, since they asked for brighter.
  static func restoredLevel(baseline: Float, written: Float, current: Float) -> Float? {
    let dimmedFurther = current < written - tolerance
    let reachedBaseline = current >= baseline - tolerance
    return dimmedFurther || reachedBaseline ? nil : baseline
  }
}
