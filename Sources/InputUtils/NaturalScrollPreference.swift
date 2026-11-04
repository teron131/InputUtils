// Owns the macOS global Natural Scrolling preference behind the trackpad row: its current value, outside changes, and writes.

import Combine
import Foundation

final class NaturalScrollPreference: ObservableObject {
  @Published private(set) var isEnabled: Bool
  @Published private(set) var writeFailed = false

  private static let key = "com.apple.swipescrolldirection" as CFString
  private let refreshInterval: TimeInterval = 5
  private var refreshTimer: Timer?

  init() {
    isEnabled = Self.read()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) {
      [weak self] _ in
      self?.refresh()
    }
  }

  deinit {
    refreshTimer?.invalidate()
  }

  /// Writes the same global preference changed by System Settings > Trackpad > Natural scrolling, storing what `defaults write -g` would.
  /// The write stays in-process because the caller runs on the main thread, which also services the scroll event tap.
  func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else {
      return
    }

    CFPreferencesSetValue(
      Self.key,
      enabled as CFBoolean,
      kCFPreferencesAnyApplication,
      kCFPreferencesCurrentUser,
      kCFPreferencesAnyHost
    )
    let written = CFPreferencesSynchronize(
      kCFPreferencesAnyApplication,
      kCFPreferencesCurrentUser,
      kCFPreferencesAnyHost
    )
    writeFailed = !written
    if written {
      isEnabled = enabled
    }
  }

  /// Keeps the toggle in step with Natural Scrolling changes made in System Settings.
  private func refresh() {
    let enabled = Self.read()
    if enabled != isEnabled {
      isEnabled = enabled
    }
  }

  /// Synchronizing first picks up changes other processes made since the last read.
  private static func read() -> Bool {
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    return CFPreferencesGetAppBooleanValue(key, kCFPreferencesAnyApplication, nil)
  }
}
