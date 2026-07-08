// Coordinates the global natural-scroll preference, wheel-event edits, and event-tap lifecycle.

import ApplicationServices
import Combine
import Foundation

enum ScrollSwitchStatus: Equatable {
  case running
  case paused
  case permissionNeeded
  case preferenceUnavailable
  case tapUnavailable

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
    case .tapUnavailable:
      return "Event tap unavailable"
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
    case .tapUnavailable:
      return "Restart or re-enable access."
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
  private let activeDeviceRefreshInterval: TimeInterval = 0.45
  private let activeDeviceHoldInterval: TimeInterval = 0.9
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var reconcileTimer: Timer?
  private var activeDeviceTimer: Timer?
  private var lastActiveDeviceSignalTime: TimeInterval = 0
  private var pendingActiveDevice: ActiveScrollDevice = .none
  private var trackpadPreferenceReadInFlight = false
  private var trackpadPreferenceRevision = 0

  init() {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: enabledKey) == nil {
      defaults.set(true, forKey: enabledKey)
    }

    isEnabled = defaults.bool(forKey: enabledKey)
    isTrackpadNaturalScrollingEnabled = Self.readTrackpadPreference()

    if isEnabled {
      start()
    }

    startPreferenceReconciliation()
  }

  deinit {
    reconcileTimer?.invalidate()
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

    trackpadPreferenceRevision += 1
    isTrackpadNaturalScrollingEnabled = enabled
  }

  /// Installs a session event tap that edits only non-continuous wheel scroll events.
  func start() {
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

    if let runLoopSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    CGEvent.tapEnable(tap: tap, enable: true)
    status = .running
  }

  /// Removes the event tap without changing the global trackpad natural-scroll preference.
  func stop() {
    stopEventTap()
    activeDeviceTimer?.invalidate()
    activeDeviceTimer = nil
    activeDevice = .none
    pendingActiveDevice = .none
    status = .paused
  }

  /// Re-enables a tap that macOS disabled after timeout or user input protection.
  func handleTapDisabled() {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
      status = .running
    } else if isEnabled {
      start()
    }
  }

  /// Inverts mouse-wheel scroll deltas while leaving continuous trackpad-style events untouched.
  func handleScrollEvent(_ event: CGEvent) {
    guard ScrollEventClassifier.isWheelMouse(event) else {
      scheduleActiveDevice(.trackpad)
      return
    }

    ScrollEventInverter.invert(event)
    scheduleActiveDevice(.mouse)
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

  private func startPreferenceReconciliation() {
    reconcileTimer = Timer.scheduledTimer(
      withTimeInterval: 5,
      repeats: true
    ) { [weak self] _ in
      self?.reconcileRunningState()
    }
  }

  private func reconcileRunningState() {
    guard isEnabled else {
      return
    }

    guard status == .running else {
      return
    }

    refreshTrackpadPreferenceInBackground()
  }

  private func scheduleActiveDevice(_ device: ActiveScrollDevice) {
    let now = ProcessInfo.processInfo.systemUptime
    guard
      device != pendingActiveDevice
        || now - lastActiveDeviceSignalTime >= activeDeviceRefreshInterval
    else {
      return
    }

    pendingActiveDevice = device
    lastActiveDeviceSignalTime = now

    if Thread.isMainThread {
      markActiveDevice(device)
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.markActiveDevice(device)
      }
    }
  }

  private func markActiveDevice(_ device: ActiveScrollDevice) {
    activeDevice = device
    activeDeviceTimer?.invalidate()
    activeDeviceTimer = Timer.scheduledTimer(
      withTimeInterval: activeDeviceHoldInterval,
      repeats: false
    ) { [weak self] _ in
      self?.activeDevice = .none
      self?.pendingActiveDevice = .none
      self?.activeDeviceTimer = nil
    }
  }

  private func refreshTrackpadPreferenceInBackground() {
    guard !trackpadPreferenceReadInFlight else {
      return
    }

    trackpadPreferenceReadInFlight = true
    let revision = trackpadPreferenceRevision

    DispatchQueue.global(qos: .utility).async { [weak self] in
      let enabled = Self.readTrackpadPreference()

      DispatchQueue.main.async { [weak self] in
        guard let self else {
          return
        }

        trackpadPreferenceReadInFlight = false
        guard revision == trackpadPreferenceRevision else {
          return
        }

        if enabled != isTrackpadNaturalScrollingEnabled {
          isTrackpadNaturalScrollingEnabled = enabled
        }
      }
    }
  }

  private static func readTrackpadPreference() -> Bool {
    NaturalScrollPreference.isTrackpadNaturalScrollingEnabled()
  }

  private func requestAccessibilityTrustPrompt() {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ] as CFDictionary

    AXIsProcessTrustedWithOptions(options)
  }
}

enum ScrollEventClassifier {
  /// Treats only scroll events without continuous or gesture phase markers as physical wheel mouse input.
  static func isWheelMouse(_ event: CGEvent) -> Bool {
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    let hasGesturePhase = event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
    let hasMomentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0

    return !isContinuous && !hasGesturePhase && !hasMomentumPhase
  }
}

enum ScrollEventInverter {
  private static let axisDeltaFields: [CGEventField] = [
    .scrollWheelEventDeltaAxis1,
    .scrollWheelEventDeltaAxis2,
    .scrollWheelEventDeltaAxis3,
  ]

  /// Flips primary wheel-axis deltas and lets CoreGraphics keep derived point and fixed-point fields consistent.
  static func invert(_ event: CGEvent) {
    for field in axisDeltaFields {
      let value = event.getIntegerValueField(field)
      if value != 0 {
        event.setIntegerValueField(field, value: -value)
      }
    }
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
