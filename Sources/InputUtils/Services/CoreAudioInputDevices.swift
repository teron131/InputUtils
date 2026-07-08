// Owns CoreAudio input-device discovery, default-device writes, and change listeners.

import CoreAudio
import Foundation

struct AudioInputDevice {
  let id: AudioDeviceID
  let name: String

  /// Matches device names through lowercased tokens because CoreAudio exposes localized display names.
  func nameContains(_ tokens: [String]) -> Bool {
    let normalizedName = name.lowercased()
    return tokens.allSatisfy { token in
      normalizedName.contains(token)
    }
  }
}

final class CoreAudioInputDevices {
  private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

  private var defaultInputAddress = CoreAudioInputDevices.audioAddress(
    kAudioHardwarePropertyDefaultInputDevice
  )
  private var devicesAddress = CoreAudioInputDevices.audioAddress(
    kAudioHardwarePropertyDevices
  )
  private var defaultInputListener: AudioObjectPropertyListenerBlock?
  private var devicesListener: AudioObjectPropertyListenerBlock?

  deinit {
    removeChangeListeners()
  }

  /// Installs CoreAudio listeners for both default-input and device-list changes.
  func observeChanges(_ handler: @escaping () -> Void) {
    removeChangeListeners()

    defaultInputListener = addSystemListener(
      address: &defaultInputAddress,
      handler: handler
    )
    devicesListener = addSystemListener(
      address: &devicesAddress,
      handler: handler
    )
  }

  /// Reads the current system default input device identifier.
  func currentInputDeviceID() -> AudioDeviceID? {
    var deviceID = AudioDeviceID()
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = Self.audioAddress(kAudioHardwarePropertyDefaultInputDevice)

    guard AudioObjectGetPropertyData(
      Self.systemObject,
      &address,
      0,
      nil,
      &size,
      &deviceID
    ) == noErr else {
      return nil
    }

    return deviceID
  }

  /// Chooses the built-in microphone from the current input-device list by stable name tokens.
  func findBuiltInInputDevice() -> AudioInputDevice? {
    let inputDevices = allInputDevices()
    let preferredNameTokens = [
      ["macbook", "microphone"],
      ["built", "microphone"],
      ["internal", "microphone"],
    ]

    for tokens in preferredNameTokens {
      if let device = inputDevices.first(where: { device in
        device.nameContains(tokens)
      }) {
        return device
      }
    }

    return nil
  }

  /// Makes the supplied device the macOS default input device.
  func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
    var mutableDeviceID = deviceID
    var address = Self.audioAddress(kAudioHardwarePropertyDefaultInputDevice)

    return AudioObjectSetPropertyData(
      Self.systemObject,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<AudioDeviceID>.size),
      &mutableDeviceID
    ) == noErr
  }

  private func addSystemListener(
    address: inout AudioObjectPropertyAddress,
    handler: @escaping () -> Void
  ) -> AudioObjectPropertyListenerBlock? {
    let listener: AudioObjectPropertyListenerBlock = { _, _ in
      handler()
    }

    guard AudioObjectAddPropertyListenerBlock(
      Self.systemObject,
      &address,
      DispatchQueue.main,
      listener
    ) == noErr else {
      return nil
    }

    return listener
  }

  private func removeChangeListeners() {
    removeSystemListener(defaultInputListener, address: &defaultInputAddress)
    defaultInputListener = nil

    removeSystemListener(devicesListener, address: &devicesAddress)
    devicesListener = nil
  }

  private func removeSystemListener(
    _ listener: AudioObjectPropertyListenerBlock?,
    address: inout AudioObjectPropertyAddress
  ) {
    guard let listener else {
      return
    }

    AudioObjectRemovePropertyListenerBlock(
      Self.systemObject,
      &address,
      DispatchQueue.main,
      listener
    )
  }

  private func allInputDevices() -> [AudioInputDevice] {
    var address = Self.audioAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0

    guard AudioObjectGetPropertyDataSize(
      Self.systemObject,
      &address,
      0,
      nil,
      &size
    ) == noErr else {
      return []
    }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

    guard AudioObjectGetPropertyData(
      Self.systemObject,
      &address,
      0,
      nil,
      &size,
      &deviceIDs
    ) == noErr else {
      return []
    }

    return deviceIDs.compactMap { deviceID in
      guard hasInputStreams(deviceID), let name = deviceName(deviceID) else {
        return nil
      }

      return AudioInputDevice(
        id: deviceID,
        name: name
      )
    }
  }

  private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
    var address = Self.audioAddress(
      kAudioDevicePropertyStreams,
      scope: kAudioDevicePropertyScopeInput
    )
    var size: UInt32 = 0

    guard AudioObjectGetPropertyDataSize(
      deviceID,
      &address,
      0,
      nil,
      &size
    ) == noErr else {
      return false
    }

    return size > 0
  }

  private func deviceName(_ deviceID: AudioDeviceID) -> String? {
    var address = Self.audioAddress(kAudioObjectPropertyName)
    let namePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
    namePointer.initialize(to: nil)
    defer {
      namePointer.deinitialize(count: 1)
      namePointer.deallocate()
    }

    var size = UInt32(MemoryLayout<CFString?>.size)

    guard AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      namePointer
    ) == noErr, let name = namePointer.pointee else {
      return nil
    }

    return name as String
  }

  private static func audioAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
  }
}
