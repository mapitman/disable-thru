import CoreAudio
import Foundation

// Disable the "Thru" (hardware play-through) setting on the Yeti input device.
// macOS resets this to the driver default whenever the device enumerates, so a
// LaunchAgent re-applies it at login and on each replug.

let targetName = "Yeti Stereo Microphone"

func deviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
        return []
    }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
        return []
    }

    return ids
}

func name(of device: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
          let result = value?.takeRetainedValue() else {
        return ""
    }

    return result as String
}

// Input channel count. The Yeti appears twice: an input device and an output
// device sharing one name. Only the input device carries the Thru control.
func inputChannels(of device: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)

    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else {
        return 0
    }

    let buffer = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { buffer.deallocate() }

    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else {
        return 0
    }

    let list = UnsafeMutableAudioBufferListPointer(
        buffer.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func setPlayThru(_ device: AudioDeviceID, enabled: Bool) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyPlayThru,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    guard AudioObjectHasProperty(device, &address) else {
        return false
    }

    var value: UInt32 = enabled ? 1 : 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
}

var matched = false

for device in deviceIDs() where name(of: device).hasPrefix(targetName) {
    guard inputChannels(of: device) > 0 else {
        continue
    }

    matched = true
    let label = "\(name(of: device)) [id \(device)]"

    if setPlayThru(device, enabled: false) {
        print("Thru disabled: \(label)")
    } else {
        print("Failed to disable Thru: \(label)")
        exit(1)
    }
}

if !matched {
    print("No input device found matching '\(targetName)' — nothing to do.")
}
