// Reads and writes the built-in display's brightness through the private DisplayServices framework, because no public macOS API sets backlight level.

import CoreGraphics
import Foundation

/// Levels use the Control Center slider's 0–1 scale.
struct BuiltInDisplayBrightness {
  private typealias Getter =
    @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
  private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

  private let getter: Getter
  private let setter: Setter

  /// Fails when DisplayServices or its brightness functions are missing, which a future macOS release could cause.
  init?() {
    guard
      let framework = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
      ),
      let get = dlsym(framework, "DisplayServicesGetBrightness"),
      let set = dlsym(framework, "DisplayServicesSetBrightness")
    else {
      return nil
    }

    getter = unsafeBitCast(get, to: Getter.self)
    setter = unsafeBitCast(set, to: Setter.self)
  }

  /// Nil while no built-in display is online, such as with the lid closed on an external display.
  func level() -> Float? {
    guard let display = Self.builtInDisplay() else {
      return nil
    }

    var level: Float = 0
    return getter(display, &level) == 0 ? level : nil
  }

  func setLevel(_ level: Float) {
    guard let display = Self.builtInDisplay() else {
      return
    }

    _ = setter(display, level)
  }

  private static func builtInDisplay() -> CGDirectDisplayID? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
      return nil
    }

    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
      return nil
    }

    return displays.first { CGDisplayIsBuiltin($0) != 0 }
  }
}
