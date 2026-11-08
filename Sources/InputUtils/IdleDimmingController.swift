// Owns idle dimming for the built-in display: the persisted switch, the checks that read idle time and brightness, and putting the starting level back when input returns, the screen turns off, or the app quits.

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
  /// System uptime when the screen last woke, 0 standing for boot.
  private var screenWokeAt: TimeInterval = 0
  private var observers = Set<AnyCancellable>()

  init() {
    UserDefaults.standard.register(defaults: [enabledKey: true])
    isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    isAvailable = brightness != nil
    observeScreenAndApp()
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
      stop()
    }
  }

  func brightnessLevel() -> Float? {
    brightness?.level()
  }

  /// The fade is for a lit screen, so nothing is checked while the screen is off.
  /// macOS still runs apps during its brief maintenance wakes with the lid closed, which would otherwise keep fading a screen nobody can see and light it up dim.
  private func observeScreenAndApp() {
    let workspace = NSWorkspace.shared.notificationCenter
    workspace.publisher(for: NSWorkspace.screensDidSleepNotification)
      .merge(
        with: workspace.publisher(for: NSWorkspace.willSleepNotification),
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
      )
      .sink { [weak self] _ in self?.stop() }
      .store(in: &observers)
    workspace.publisher(for: NSWorkspace.screensDidWakeNotification)
      .sink { [weak self] _ in self?.screenDidWake() }
      .store(in: &observers)
  }

  private func screenDidWake() {
    screenWokeAt = ProcessInfo.processInfo.systemUptime
    if isEnabled {
      start()
    }
  }

  private func start() {
    guard brightness != nil else {
      return
    }

    check()
  }

  /// Ends any fade first, so a screen going dark lights up again at the person's brightness.
  private func stop() {
    endDimming()
    timer?.invalidate()
    timer = nil
  }

  /// Checking once per step while idle also catches input the event monitor cannot see, such as the brightness keys.
  private func check() {
    let idle = secondsIdle()
    schedule(after: IdleDimming.nextCheck(afterIdle: idle))

    guard idle >= IdleDimming.delay else {
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

  private func schedule(after interval: TimeInterval) {
    timer?.invalidate()
    let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
      [weak self] _ in
      self?.check()
    }
    timer.tolerance = 3
    self.timer = timer
  }

  /// A built-in display that is offline, as with the lid closed on an external display, can be neither read nor set, so a fade it cuts short keeps its lowered level.
  private func endDimming() {
    if case .dimming(let baseline, let written) = phase, let brightness,
      let level = brightness.level(),
      let restored = IdleDimming.restoredLevel(
        baseline: baseline, written: written, current: level)
    {
      brightness.setLevel(restored)
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

  /// Counts from the screen waking as well as from the last input, because opening the lid lights the screen without registering as input.
  private func secondsIdle() -> TimeInterval {
    min(Self.secondsSinceInput(), ProcessInfo.processInfo.systemUptime - screenWokeAt)
  }

  /// Counts hardware keyboard, mouse, and trackpad events; raw value `~0` is CoreGraphics' any-input type, which Swift does not import by name.
  private static func secondsSinceInput() -> TimeInterval {
    CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
  }
}
