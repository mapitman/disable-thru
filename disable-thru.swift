import CoreAudio
import Foundation

// Disable the "Thru" (hardware play-through) setting on an input device.
// macOS resets this to the driver default whenever the device enumerates, so a
// LaunchAgent re-applies it at login and on each replug.

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

/// The address of the Thru property. Play-through lives on the output scope
/// even though the control belongs to an input device.
func playThruAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyPlayThru,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
}

/// Whether the device exposes a Thru setting at all. Most input devices do not.
func hasPlayThru(_ device: AudioDeviceID) -> Bool {
    var address = playThruAddress()
    return AudioObjectHasProperty(device, &address)
}

func setPlayThru(_ device: AudioDeviceID, enabled: Bool) -> Bool {
    var address = playThruAddress()

    guard AudioObjectHasProperty(device, &address) else {
        return false
    }

    var value: UInt32 = enabled ? 1 : 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
}

let usage = """
Usage: disable-thru <device-name>
       disable-thru --list

Turns off the Thru setting on an audio input device, so the device stops routing
its input back to its own output. The device name is matched as a prefix.

Options:
  --list, -l    List input devices that expose a Thru setting, then exit.
  --help, -h    Show this message.

Example:
  disable-thru "Yeti Stereo Microphone"
"""

/// Input devices that carry a Thru control, in the order CoreAudio reports.
func thruCapableInputs() -> [AudioDeviceID] {
    deviceIDs().filter { inputChannels(of: $0) > 0 && hasPlayThru($0) }
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print(usage)
    exit(0)
}

if arguments.contains("--list") || arguments.contains("-l") {
    let devices = thruCapableInputs()
    if devices.isEmpty {
        print("No input devices with a Thru setting found.")
        exit(0)
    }

    for device in devices {
        print(name(of: device))
    }

    exit(0)
}

// Report an unrecognised flag, so a typo surfaces immediately.
if let flag = arguments.first(where: { $0.hasPrefix("-") }) {
    FileHandle.standardError.write("Unknown option: \(flag)\n\n".data(using: .utf8)!)
    print(usage)
    exit(2)
}

// Require a device name, so the program only ever acts on the device the caller
// asked for.
guard let targetName = arguments.first else {
    FileHandle.standardError.write("No device name given.\n\n".data(using: .utf8)!)
    print(usage)
    exit(2)
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
