// Coordinates wheel-event edits, the event-tap lifecycle, and the highlight for the device currently scrolling.

import ApplicationServices
import Combine
import Foundation

enum ActiveScrollDevice {
  case none
  case trackpad
  case mouse
}

final class ScrollDirectionController: ObservableObject {
  @Published private(set) var isEnabled: Bool
  @Published private(set) var needsPermission = false
  @Published private(set) var activeDevice: ActiveScrollDevice = .none

  private let enabledKey = "ScrollDirectionController.isEnabled"
  private let activeDeviceRefreshInterval: TimeInterval = 0.45
  private let activeDeviceHoldInterval: TimeInterval = 0.9
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var activeDeviceTimer: Timer?
  private var lastActiveDeviceSignalTime: TimeInterval = 0

  init() {
    UserDefaults.standard.register(defaults: [enabledKey: true])
    isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    if isEnabled {
      start()
    }
  }

  deinit {
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
      needsPermission = true
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
    needsPermission = false
  }

  /// Removes the event tap without changing the global trackpad natural-scroll preference.
  private func stop() {
    stopEventTap()
    activeDeviceTimer?.invalidate()
    activeDeviceTimer = nil
    activeDevice = .none
    needsPermission = false
  }

  /// Re-enables a tap that macOS disabled after timeout or user input protection.
  fileprivate func handleTapDisabled() {
    guard let eventTap else {
      return
    }

    CGEvent.tapEnable(tap: eventTap, enable: true)
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
