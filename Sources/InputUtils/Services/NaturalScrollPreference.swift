// Owns the macOS global Natural Scrolling preference that trackpads should keep using.

import Foundation

enum NaturalScrollPreferenceError: Error {
  case writeFailed(Int32)
}

enum NaturalScrollPreference {
  private static let key = "com.apple.swipescrolldirection"

  /// Reads the current global Natural Scrolling value from the same domain System Settings uses.
  static func isTrackpadNaturalScrollingEnabled() -> Bool {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = [
      "read",
      "-g",
      key,
    ]
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return UserDefaults.standard.bool(forKey: key)
    }

    guard process.terminationStatus == 0 else {
      return UserDefaults.standard.bool(forKey: key)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let value = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return value == "1" || value == "true" || value == "TRUE"
  }

  /// Writes the same global preference changed by System Settings > Trackpad > Natural scrolling.
  static func setTrackpadNaturalScrollingEnabled(_ enabled: Bool) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = [
      "write",
      "-g",
      "com.apple.swipescrolldirection",
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
