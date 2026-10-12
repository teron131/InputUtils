// Owns the macOS global Natural Scrolling preference that trackpads should keep using.

import Foundation

enum NaturalScrollPreferenceError: Error {
  case writeFailed(Int32)
}

enum NaturalScrollPreference {
  private static let key = "com.apple.swipescrolldirection"

  /// Reads the current global Natural Scrolling value from the same domain System Settings uses.
  /// The read stays in-process so callers can poll it on the main thread; synchronizing first picks up changes made by System Settings or the `defaults` write below.
  static func isTrackpadNaturalScrollingEnabled() -> Bool {
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    return CFPreferencesGetAppBooleanValue(key as CFString, kCFPreferencesAnyApplication, nil)
  }

  /// Writes the same global preference changed by System Settings > Trackpad > Natural scrolling.
  static func setTrackpadNaturalScrollingEnabled(_ enabled: Bool) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = [
      "write",
      "-g",
      key,
      "-bool",
      enabled ? "true" : "false",
    ]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw NaturalScrollPreferenceError.writeFailed(process.terminationStatus)
    }
  }
}
