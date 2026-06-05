import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// Adjusts system default output volume via CoreAudio (macOS).
final class SystemVolumeController: @unchecked Sendable {
    private var defaultOutputDeviceID: AudioDeviceID = kAudioObjectUnknown

    init() {
        refreshDefaultOutputDevice()
    }

    func refreshDefaultOutputDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        if status == noErr {
            defaultOutputDeviceID = deviceID
        }
    }

    func readVolumeScalar() -> Float32? {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(defaultOutputDeviceID, &address) == false {
            address.mElement = 1
        }
        let status = AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    func setVolumeScalar(_ value: Float32) {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return }
        var clamped = max(AppConstants.outputVolumeMin, min(AppConstants.outputVolumeMax, value))
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(defaultOutputDeviceID, &address) == false {
            address.mElement = 1
        }
        _ = AudioObjectSetPropertyData(defaultOutputDeviceID, &address, 0, nil, size, &clamped)
    }
}
