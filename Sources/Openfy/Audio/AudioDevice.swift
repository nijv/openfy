import AudioToolbox
import CoreAudio
import Foundation

/// Thin wrapper over the CoreAudio HAL for the default output device.
enum AudioDevice {
    static func defaultOutput() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    static func name(_ device: AudioDeviceID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr, let name else {
            return "Output"
        }
        return name.takeRetainedValue() as String
    }

    static func nominalSampleRate(_ device: AudioDeviceID) -> Double? {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        return rate
    }

    static func availableSampleRates(_ device: AudioDeviceID) -> [AudioValueRange] {
        var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &ranges) == noErr else { return [] }
        return ranges
    }

    static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyTransportType)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    @discardableResult
    static func setNominalSampleRate(_ device: AudioDeviceID, _ rate: Double) -> Bool {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var value = Float64(rate)
        let status = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
        return status == noErr
    }

    /// The device switches rate asynchronously; wait (briefly) until it reports the new rate.
    static func waitForRate(_ device: AudioDeviceID, _ rate: Double, timeout: TimeInterval = 1.5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let r = nominalSampleRate(device), abs(r - rate) < 0.5 { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        // Give the hardware a moment to settle after the switch to avoid a click.
        Thread.sleep(forTimeInterval: 0.05)
    }

    static func supports(_ device: AudioDeviceID, rate: Double) -> Bool {
        availableSampleRates(device).contains { rate >= $0.mMinimum - 0.5 && rate <= $0.mMaximum + 0.5 }
    }

    /// The device rate to use for a source rate: the exact rate if the hardware supports it
    /// (bit-perfect), otherwise the closest sensible rate (macOS then resamples in high quality).
    static func bestRate(for source: Double, device: AudioDeviceID) -> Double {
        if supports(device, rate: source) { return source }
        let discrete = availableSampleRates(device).flatMap { r -> [Double] in
            r.mMinimum == r.mMaximum ? [r.mMinimum] : [r.mMinimum, r.mMaximum]
        }.sorted()
        guard !discrete.isEmpty else { return source }
        // Prefer an integer multiple (44.1 → 88.2), then the lowest rate above the source, then the highest.
        if let multiple = discrete.first(where: { $0 > source && $0.truncatingRemainder(dividingBy: source) < 0.5 }) {
            return multiple
        }
        return discrete.first(where: { $0 >= source }) ?? discrete.last!
    }

    // MARK: Output volume (the Mac's own volume, which keeps playback bit-perfect)

    /// The device's volume 0...1 (0 when muted), or nil if it has no volume control (e.g. HDMI, some DACs).
    static func volume(_ device: AudioDeviceID) -> Float? {
        var addr = outputAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return isMuted(device) ? 0 : value
    }

    /// Sets the device's volume (unmuting it when raised). Returns false if the device can't do it.
    @discardableResult
    static func setVolume(_ device: AudioDeviceID, _ volume: Float) -> Bool {
        var addr = outputAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard isSettable(device, &addr) else { return false }
        var value = Float32(min(max(volume, 0), 1))
        guard AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
        else { return false }
        if value > 0, isMuted(device) {
            var muteAddr = outputAddress(kAudioDevicePropertyMute)
            var off = UInt32(0)
            if isSettable(device, &muteAddr) {
                AudioObjectSetPropertyData(device, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
            }
        }
        return true
    }

    private static func isMuted(_ device: AudioDeviceID) -> Bool {
        var addr = outputAddress(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr && muted != 0
    }

    private static func isSettable(_ device: AudioDeviceID, _ addr: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
