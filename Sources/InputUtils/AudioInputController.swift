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
    refreshStatus()
    inputDevices.observeChanges { [weak self] in
      self?.refreshStatus()
    }
  }

  /// Persists whether the app should keep the built-in microphone as the default input.
  func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else {
      return
    }

    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: enabledKey)
    refreshStatus()
  }

  /// Restores the built-in microphone as the default input while pinning is enabled, then reports the outcome.
  /// Runs at launch, on every toggle, and whenever CoreAudio reports a default-input or device-list change.
  private func refreshStatus() {
    guard let builtInInputID = inputDevices.builtInInputDeviceID() else {
      status = "No built-in mic"
      return
    }

    guard isEnabled else {
      status = "Ready"
      return
    }

    let isPinned =
      inputDevices.currentInputDeviceID() == builtInInputID
      || inputDevices.setDefaultInputDevice(builtInInputID)
    status = isPinned ? "Always" : "Set failed"
  }
}
