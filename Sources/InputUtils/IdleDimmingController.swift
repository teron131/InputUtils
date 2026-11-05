// Owns idle dimming for the built-in display: the persisted switch, the tick that reads idle time and brightness, and restoring the starting level the moment input returns.

import AppKit
import Combine
import CoreGraphics

final class IdleDimmingController: ObservableObject {
  @Published private(set) var isEnabled: Bool
  let isAvailable: Bool

  private static let inputEvents: NSEvent.EventTypeMask = [
    .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown,
    .flagsChanged, .gesture,
  ]
  private let enabledKey = "IdleDimmingController.isEnabled"
  private let brightness = BuiltInDisplayBrightness()
  private var phase = IdleDimming.Phase.watching
  private var timer: Timer?
  private var inputMonitor: Any?

  init() {
    UserDefaults.standard.register(defaults: [enabledKey: true])
    isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    isAvailable = brightness != nil
    if isEnabled {
      start()
    }
  }

  deinit {
    timer?.invalidate()
  }

  func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else {
      return
    }

    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: enabledKey)

    if enabled {
      start()
    } else {
      endDimming()
      timer?.invalidate()
      timer = nil
    }
  }

  func brightnessLevel() -> Float? {
    brightness?.level()
  }

  private func start() {
    guard brightness != nil, timer == nil else {
      return
    }

    let timer = Timer.scheduledTimer(withTimeInterval: IdleDimming.stepInterval, repeats: true) {
      [weak self] _ in
      self?.tick()
    }
    timer.tolerance = 3
    self.timer = timer
  }

  /// The tick also catches input the event monitor cannot see, such as the brightness keys, within one step interval.
  private func tick() {
    guard Self.secondsSinceInput() >= IdleDimming.delay else {
      endDimming()
      return
    }

    guard let brightness, let level = brightness.level() else {
      return
    }

    let (next, write) = IdleDimming.advance(
      phase,
      level: level,
      isPlaying: ScreenPlayback.isPlaying()
    )
    phase = next
    if let write {
      brightness.setLevel(write)
    }
    syncInputMonitor()
  }

  private func endDimming() {
    if case .dimming(let baseline, _) = phase {
      brightness?.setLevel(baseline)
    }
    phase = .watching
    syncInputMonitor()
  }

  /// Listens for input only while dimmed, so restoring is instant without watching every event the rest of the time.
  /// Key presses reach the monitor only with the Accessibility permission the scroll tap already needs.
  private func syncInputMonitor() {
    let isDimming = if case .dimming = phase { true } else { false }

    if isDimming, inputMonitor == nil {
      inputMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.inputEvents) {
        [weak self] _ in
        self?.endDimming()
      }
    } else if !isDimming, let inputMonitor {
      NSEvent.removeMonitor(inputMonitor)
      self.inputMonitor = nil
    }
  }

  /// Counts hardware keyboard, mouse, and trackpad events; raw value `~0` is CoreGraphics' any-input type, which Swift does not import by name.
  private static func secondsSinceInput() -> TimeInterval {
    CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
  }
}
