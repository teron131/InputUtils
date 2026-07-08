// Owns the menu state and policy for pinning macOS input to the built-in microphone.

import Combine
import Foundation

final class AudioInputController: ObservableObject {
  @Published private(set) var isEnabled: Bool
  @Published private(set) var status = "Waiting"

  private let enabledKey = "AudioInputController.pinBuiltInMic"
  private let inputDevices = CoreAudioInputDevices()

  init() {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: enabledKey) == nil {
      defaults.set(true, forKey: enabledKey)
    }

    isEnabled = defaults.bool(forKey: enabledKey)
    refreshStatus(enforce: isEnabled)
    inputDevices.observeChanges { [weak self] in
      guard let self else {
        return
      }

      refreshStatus(enforce: isEnabled)
    }
  }

  /// Persists whether the app should keep the built-in microphone as the default input.
  func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else {
      return
    }

    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: enabledKey)
    refreshStatus(enforce: enabled)
  }

  /// Refreshes device names and optionally restores the default input to the built-in microphone.
  func refreshStatus(enforce: Bool) {
    guard let builtInInput = inputDevices.findBuiltInInputDevice() else {
      status = "No built-in mic"
      return
    }

    let activeInputID = inputDevices.currentInputDeviceID()

    if enforce && activeInputID != builtInInput.id {
      if inputDevices.setDefaultInputDevice(builtInInput.id) {
        status = "Always"
      } else {
        status = "Set failed"
      }
      return
    }

    status = isEnabled ? "Always" : "Ready"
  }
}
