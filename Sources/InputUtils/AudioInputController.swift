// Owns the menu state and policy for pinning macOS input to the built-in microphone.

import Combine
import Foundation

final class AudioInputController: ObservableObject {
  @Published private(set) var isEnabled: Bool
  /// Nil while pinning works or is switched off.
  @Published private(set) var problem: String?

  private let enabledKey = "AudioInputController.pinBuiltInMic"
  private let inputDevices = CoreAudioInputDevices()

  init() {
    UserDefaults.standard.register(defaults: [enabledKey: true])
    isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    refresh()
    inputDevices.observeChanges { [weak self] in
      self?.refresh()
    }
  }

  /// Persists whether the app should keep the built-in microphone as the default input.
  func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else {
      return
    }

    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: enabledKey)
    refresh()
  }

  /// Restores the built-in microphone as the default input while pinning is enabled, then reports any problem.
  /// Runs at launch, on every toggle, and whenever CoreAudio reports a default-input or device-list change.
  private func refresh() {
    guard let builtInInputID = inputDevices.builtInInputDeviceID() else {
      problem = "No built-in mic"
      return
    }

    guard isEnabled else {
      problem = nil
      return
    }

    let isPinned =
      inputDevices.currentInputDeviceID() == builtInInputID
      || inputDevices.setDefaultInputDevice(builtInInputID)
    problem = isPinned ? nil : "Set failed"
  }
}
