// Coordinates the global natural-scroll preference, wheel-event edits, and event-tap lifecycle.

import ApplicationServices
import Combine
import Foundation

enum ScrollSwitchStatus: Equatable {
  case running
  case paused
  case permissionNeeded
  case preferenceUnavailable

  var title: String {
    switch self {
    case .running:
      return "Input Utils"
    case .paused:
      return "Paused"
    case .permissionNeeded:
      return "Permission needed"
    case .preferenceUnavailable:
      return "Preference unavailable"
    }
  }

  var detail: String {
    switch self {
    case .running:
      return "Trackpad, mouse, mic."
    case .paused:
      return "Scroll events pass through."
    case .permissionNeeded:
      return "Allow Accessibility access."
    case .preferenceUnavailable:
      return "Natural Scrolling was not set."
    }
  }
}

enum ActiveScrollDevice {
  case none
  case trackpad
  case mouse
}

final class ScrollDirectionController: ObservableObject {
  @Published private(set) var isEnabled: Bool
  @Published private(set) var status: ScrollSwitchStatus = .paused
  @Published private(set) var activeDevice: ActiveScrollDevice = .none
  @Published private(set) var isTrackpadNaturalScrollingEnabled: Bool

  private let enabledKey = "ScrollDirectionController.isEnabled"
  private let trackpadPreferenceRefreshInterval: TimeInterval = 5
  private let activeDeviceRefreshInterval: TimeInterval = 0.45
  private let activeDeviceHoldInterval: TimeInterval = 0.9
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var trackpadPreferenceTimer: Timer?
  private var activeDeviceTimer: Timer?
  private var lastActiveDeviceSignalTime: TimeInterval = 0

  init() {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: enabledKey) == nil {
      defaults.set(true, forKey: enabledKey)
    }

    isEnabled = defaults.bool(forKey: enabledKey)
    isTrackpadNaturalScrollingEnabled = NaturalScrollPreference.isTrackpadNaturalScrollingEnabled()

    if isEnabled {
      start()
    }

    startTrackpadPreferenceRefresh()
  }

  deinit {
    trackpadPreferenceTimer?.invalidate()
    activeDeviceTimer?.invalidate()
  }

  /// Persists the utility state and starts or stops the event tap immediately.
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

  /// Retries tap installation and lets the event-tap result decide whether a permission prompt is needed.
  func requestPermissionAndRetry() {
    start()
  }

  /// Updates the macOS trackpad Natural Scrolling preference from the panel toggle.
  func setTrackpadNaturalScrollingEnabled(_ enabled: Bool) {
    guard enabled != isTrackpadNaturalScrollingEnabled else {
      return
    }

    do {
      try NaturalScrollPreference.setTrackpadNaturalScrollingEnabled(enabled)
    } catch {
      status = .preferenceUnavailable
      return
    }

    isTrackpadNaturalScrollingEnabled = enabled
  }

  /// Installs a session event tap that edits only non-continuous wheel scroll events.
  private func start() {
    stopEventTap()

    let eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: scrollEventTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      requestAccessibilityTrustPrompt()
      status = .permissionNeeded
      return
    }

    CGEvent.tapEnable(tap: tap, enable: false)
    eventTap = tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

    // The source runs on the main run loop, so the callback and the state it touches stay on the main thread.
    if let runLoopSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    CGEvent.tapEnable(tap: tap, enable: true)
    status = .running
  }

  /// Removes the event tap without changing the global trackpad natural-scroll preference.
  private func stop() {
    stopEventTap()
    activeDeviceTimer?.invalidate()
    activeDeviceTimer = nil
    activeDevice = .none
    status = .paused
  }

  /// Re-enables a tap that macOS disabled after timeout or user input protection.
  fileprivate func handleTapDisabled() {
    guard let eventTap else {
      return
    }

    CGEvent.tapEnable(tap: eventTap, enable: true)
    status = .running
  }

  /// Inverts mouse-wheel scroll deltas while leaving continuous trackpad-style events untouched.
  fileprivate func handleScrollEvent(_ event: CGEvent) {
    guard ScrollEventClassifier.isWheelMouse(event) else {
      markActiveDevice(.trackpad)
      return
    }

    ScrollEventInverter.invert(event)
    markActiveDevice(.mouse)
  }

  private func stopEventTap() {
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }

    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      self.eventTap = nil
    }
  }

  private func startTrackpadPreferenceRefresh() {
    trackpadPreferenceTimer = Timer.scheduledTimer(
      withTimeInterval: trackpadPreferenceRefreshInterval,
      repeats: true
    ) { [weak self] _ in
      self?.refreshTrackpadPreference()
    }
  }

  /// Keeps the panel toggle in step with Natural Scrolling changes made outside the app while switching is running.
  private func refreshTrackpadPreference() {
    guard status == .running else {
      return
    }

    let enabled = NaturalScrollPreference.isTrackpadNaturalScrollingEnabled()
    if enabled != isTrackpadNaturalScrollingEnabled {
      isTrackpadNaturalScrollingEnabled = enabled
    }
  }

  /// Highlights the device behind the latest scroll event until scrolling stays quiet for the hold interval.
  /// Repeated events from the same device re-arm the hold at most once per refresh interval, which keeps the per-event cost to a time comparison.
  private func markActiveDevice(_ device: ActiveScrollDevice) {
    let now = ProcessInfo.processInfo.systemUptime
    guard
      device != activeDevice
        || now - lastActiveDeviceSignalTime >= activeDeviceRefreshInterval
    else {
      return
    }

    lastActiveDeviceSignalTime = now
    if device != activeDevice {
      activeDevice = device
    }

    activeDeviceTimer?.invalidate()
    activeDeviceTimer = Timer.scheduledTimer(
      withTimeInterval: activeDeviceHoldInterval,
      repeats: false
    ) { [weak self] _ in
      self?.activeDevice = .none
      self?.activeDeviceTimer = nil
    }
  }

  private func requestAccessibilityTrustPrompt() {
    let options =
      [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
      ] as CFDictionary

    AXIsProcessTrustedWithOptions(options)
  }
}

private let scrollEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
  guard let userInfo else {
    return Unmanaged.passUnretained(event)
  }

  let controller = Unmanaged<ScrollDirectionController>
    .fromOpaque(userInfo)
    .takeUnretainedValue()

  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    controller.handleTapDisabled()
    return Unmanaged.passUnretained(event)
  }

  guard type == .scrollWheel else {
    return Unmanaged.passUnretained(event)
  }

  controller.handleScrollEvent(event)
  return Unmanaged.passUnretained(event)
}
