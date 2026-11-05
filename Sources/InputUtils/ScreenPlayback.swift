// Decides whether something is actually playing on screen, which is the only thing allowed to hold off idle dimming.

import CoreAudio
import Foundation
import IOKit.pwr_mgt

enum ScreenPlayback {
  private static let displayAwakeTypes: Set<String> = [
    "PreventUserIdleDisplaySleep",
    "NoDisplaySleepAssertion",
  ]

  /// An app holding the display awake, such as a browser's video wake lock, counts as playing.
  /// coreaudiod holds the display awake for open audio sessions and can keep that up all night with nothing audible, so its holds count only while the default output device is running.
  static func isPlaying() -> Bool {
    let holders = displayAwakeHolders()
    return holders.contains { $0 != "coreaudiod" }
      || (holders.contains("coreaudiod") && isDefaultOutputRunning())
  }

  private static func displayAwakeHolders() -> Set<String> {
    var byProcess: Unmanaged<CFDictionary>?
    guard
      IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
      let assertionsByProcess = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
    else {
      return []
    }

    var holders = Set<String>()
    for assertion in assertionsByProcess.values.joined() {
      if let type = assertion["AssertType"] as? String, displayAwakeTypes.contains(type),
        let process = assertion["Process Name"] as? String
      {
        holders.insert(process)
      }
    }
    return holders
  }

  private static func isDefaultOutputRunning() -> Bool {
    var defaultOutputAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var device = AudioDeviceID()
    var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &defaultOutputAddress,
        0,
        nil,
        &deviceSize,
        &device
      ) == noErr
    else {
      return false
    }

    var isRunningAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var isRunning: UInt32 = 0
    var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(
      device,
      &isRunningAddress,
      0,
      nil,
      &isRunningSize,
      &isRunning
    ) == noErr && isRunning != 0
  }
}
