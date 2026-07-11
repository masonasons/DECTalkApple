/*
 * AudioUnitFactory — the extension's principal class. The system instantiates
 * it (via NSExtensionPrincipalClass) and calls createAudioUnit(with:) to obtain
 * the DECtalk AVSpeechSynthesisProviderAudioUnit.
 */
import AVFoundation

public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {

    public func beginRequest(with context: NSExtensionContext) {}

    @objc public func createAudioUnit(
        with componentDescription: AudioComponentDescription
    ) throws -> AUAudioUnit {
        try DECtalkAudioUnit(componentDescription: componentDescription, options: [])
    }
}
