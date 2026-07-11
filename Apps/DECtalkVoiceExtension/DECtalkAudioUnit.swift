/*
 * DECtalkAudioUnit — an AVSpeechSynthesisProviderAudioUnit that registers the
 * DECtalk voices as a system-wide synthesizer for VoiceOver / Spoken Content.
 *
 * synthesizeSpeechRequest() renders the whole utterance synchronously (DECtalk
 * is very fast), converts 11025 Hz Int16 → 22050 Hz Float32, and hands it to the
 * real-time internalRenderBlock which drains it into the audio unit's output.
 *
 * Structure modeled on tgeczy/TGSpeechBox's TGSBAudioUnit.
 */
import AVFoundation
import Accelerate
import CoreMedia
import DECtalkKit

public final class DECtalkAudioUnit: AVSpeechSynthesisProviderAudioUnit {

    private let synth = DECtalkSynthesizer()

    // Rendered audio: written by synthesizeSpeechRequest, drained by the render
    // block. Guarded by `mutex`.
    private var output: [Float32] = []
    private var outputOffset = 0
    private var volume: Float32 = 1.0
    private let mutex = DispatchSemaphore(value: 1)

    // VoiceOver sends empty/break-only requests during normal use (spacers,
    // pauses between elements). Only the very first request is treated as a voice
    // preview and given a spoken sample; later empty requests stay silent.
    private var requestCount = 0

    // DECtalk emits 11025 Hz; 22050 avoids DAC aliasing (per TGSpeechBox notes).
    private let asbdRate: Double = 22050

    private let outputBus: AUAudioUnitBus
    private var _outputBusses: AUAudioUnitBusArray!
    private let outputFormat: AVAudioFormat

    private static let identifierPrefix = "com.dectalkapple.voice"

    // MARK: - Init

    @objc public override init(componentDescription: AudioComponentDescription,
                               options: AudioComponentInstantiationOptions = []) throws {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 22050,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)

        outputFormat = AVAudioFormat(
            cmAudioFormatDescription: try CMAudioFormatDescription(audioStreamBasicDescription: asbd))
        outputBus = try AUAudioUnitBus(format: outputFormat)

        try super.init(componentDescription: componentDescription, options: options)

        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    // MARK: - Voices

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            DECtalkSynthesizer.Speaker.allCases.map { speaker in
                let voice = AVSpeechSynthesisProviderVoice(
                    name: "DECtalk \(speaker.displayName)",
                    identifier: "\(Self.identifierPrefix).\(speaker.rawValue)",
                    primaryLanguages: ["en-US"],
                    supportedLanguages: ["en-US"])
                voice.gender = Self.gender(for: speaker)
                return voice
            }
        }
        set { }
    }

    private static func gender(for speaker: DECtalkSynthesizer.Speaker) -> AVSpeechSynthesisVoiceGender {
        switch speaker {
        case .betty, .ursula, .rita, .wendy, .kit: return .female
        default: return .male
        }
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    // MARK: - Synthesis

    public override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
        guard let synth else {
            store([0]); return
        }

        // Select the speaker from the trailing index in the voice identifier.
        let speaker = request.voice.identifier.split(separator: ".").last
            .flatMap { Int($0) }
            .flatMap { DECtalkSynthesizer.Speaker(rawValue: $0) } ?? .paul

        let ssml = request.ssmlRepresentation

        // Honor the user's shared settings (SPF, pauses, volume, per-voice
        // parameters), but let VoiceOver's own rate control win via the SSML.
        var settings = DECtalkSettingsStore.load()
        settings.rate = Self.wpm(from: ssml)

        // Split at <break> boundaries so we can render each spoken segment and
        // join them with REAL silence PCM — DECtalk produces no usable pause for
        // a trailing period, so we insert the silence ourselves.
        requestCount += 1
        var segments = Self.segments(from: ssml, honorPauses: settings.honorVoiceOverPauses)
        if segments.allSatisfy({ $0.text.isEmpty }) && requestCount == 1 {
            // Only the first empty request is a voice preview — speak a sample.
            // Later empty requests (spacers/breaks) must NOT insert spoken text.
            segments = [(text: "This is DECtalk.", silenceMs: 0)]
        }

        func silence(_ ms: Int) -> [Int16] {
            [Int16](repeating: 0, count: Int(Double(ms) / 1000.0 * synth.sampleRate))
        }

        var int16: [Int16] = []
        for seg in segments {
            if !seg.text.isEmpty {
                int16 += synth.render(seg.text, applying: settings, speaker: speaker)
            }
            if seg.silenceMs > 0 {
                int16 += silence(seg.silenceMs)   // insert the pause exactly where the break is
            }
        }
        // A truly empty utterance still needs a frame so the render block can
        // complete and VoiceOver advances to the next item.
        if int16.isEmpty { int16 = silence(10) }

        var floats = [Float32](repeating: 0, count: int16.count)
        int16.withUnsafeBufferPointer { src in
            floats.withUnsafeMutableBufferPointer { dst in
                vDSP_vflt16(src.baseAddress!, 1, dst.baseAddress!, 1, vDSP_Length(int16.count))
                var scale: Float32 = 1.0 / 32768.0
                vDSP_vsmul(dst.baseAddress!, 1, &scale, dst.baseAddress!, 1, vDSP_Length(int16.count))
            }
        }

        let srcRate = synth.sampleRate
        if srcRate != asbdRate && !floats.isEmpty {
            floats = resample(floats, from: srcRate, to: asbdRate)
        }
        store(floats)
    }

    public override func cancelSpeechRequest() {
        store([])
    }

    private func store(_ samples: [Float32]) {
        mutex.wait()
        output = samples
        outputOffset = 0
        mutex.signal()
    }

    // MARK: - Render

    public override var internalRenderBlock: AUInternalRenderBlock {
        return { actionFlags, _, frameCount, _, outputAudioBufferList, _, _ in
            let abl = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
            guard let raw = abl[0].mData else { return noErr }
            let out = raw.assumingMemoryBound(to: Float32.self)
            let frames = Int(frameCount)
            out.update(repeating: 0, count: frames)

            self.mutex.wait()
            let count = min(self.output.count - self.outputOffset, frames)
            if count > 0 {
                var vol = self.volume
                self.output.withUnsafeBufferPointer { buf in
                    vDSP_vsmul(buf.baseAddress! + self.outputOffset, 1, &vol, out, 1, vDSP_Length(count))
                }
                self.outputOffset += count
            }
            abl[0].mDataByteSize = UInt32(count * MemoryLayout<Float32>.size)

            if self.outputOffset >= self.output.count {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
                self.output.removeAll(keepingCapacity: true)
                self.outputOffset = 0
            }
            self.mutex.signal()
            return noErr
        }
    }

    // MARK: - SSML helpers

    /// Splits SSML into spoken segments separated by silence. Each segment is the
    /// cleaned text before a `<break>`, and `silenceMs` is how much real silence
    /// to insert after it (0 when not honoring pauses).
    private static func segments(from ssml: String, honorPauses: Bool) -> [(text: String, silenceMs: Int)] {
        let ns = ssml as NSString
        guard let re = try? NSRegularExpression(pattern: #"<break\b([^>]*?)/?\s*>"#, options: [.caseInsensitive]) else {
            return [(clean(ssml), 0)]
        }
        var result: [(text: String, silenceMs: Int)] = []
        var last = 0
        for m in re.matches(in: ssml, range: NSRange(location: 0, length: ns.length)) {
            let chunk = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let attrs = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ""
            let ms = honorPauses ? silenceMilliseconds(fromBreakAttributes: attrs) : 0
            result.append((clean(chunk), ms))
            last = m.range.location + m.range.length
        }
        let tail = clean(ns.substring(from: last))
        if !tail.isEmpty { result.append((tail, 0)) }
        return result.isEmpty ? [(clean(ssml), 0)] : result
    }

    /// Strips SSML tags, decodes entities, and removes DECtalk command brackets
    /// that would otherwise be parsed as commands and read aloud.
    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&apos;": "'", "&quot;": "\"", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&#39;": "'"]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        t = t.replacingOccurrences(of: "[", with: " ").replacingOccurrences(of: "]", with: " ")
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses a `<break>`'s attributes into milliseconds of silence (capped).
    private static func silenceMilliseconds(fromBreakAttributes attrs: String) -> Int {
        func value(_ name: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: "\(name)\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive]),
                  let m = re.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
                  let r = Range(m.range(at: 1), in: attrs) else { return nil }
            return String(attrs[r])
        }
        func cap(_ ms: Int) -> Int { max(0, min(ms, 2000)) }
        if let time = value("time")?.lowercased().trimmingCharacters(in: .whitespaces) {
            if time.hasSuffix("ms"), let n = Double(time.dropLast(2)) { return cap(Int(n)) }
            if time.hasSuffix("s"),  let n = Double(time.dropLast(1)) { return cap(Int(n * 1000)) }
            if let n = Double(time) { return cap(Int(n)) }
        }
        switch value("strength")?.lowercased() {
        case "none":     return 0
        case "x-weak":   return 100
        case "weak":     return 200
        case "medium":   return 350
        case "strong":   return 500
        case "x-strong": return 800
        default:         return 300
        }
    }

    /// Map an SSML prosody rate multiplier to DECtalk words-per-minute.
    private static func wpm(from ssml: String) -> Int {
        var mult = 1.0
        if let m = ssml.range(of: #"rate="([^"]+)""#, options: .regularExpression) {
            let val = ssml[m].replacingOccurrences(of: "rate=\"", with: "").replacingOccurrences(of: "\"", with: "")
            switch val {
            case "x-slow": mult = 0.4
            case "slow":   mult = 0.7
            case "medium": mult = 1.0
            case "fast":   mult = 1.6
            case "x-fast": mult = 2.2
            default:
                if val.hasSuffix("%"), let p = Double(val.dropLast()) { mult = p / 100 }
                else if let n = Double(val) { mult = n }
            }
        }
        return min(600, max(75, Int(200 * mult)))
    }

    // MARK: - Resampling

    private func resample(_ input: [Float32], from srcRate: Double, to dstRate: Double) -> [Float32] {
        guard let srcFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: srcRate, channels: 1, interleaved: false),
              let dstFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: dstRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: srcFmt, to: dstFmt),
              let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: AVAudioFrameCount(input.count))
        else { return input }

        srcBuf.frameLength = AVAudioFrameCount(input.count)
        memcpy(srcBuf.floatChannelData![0], input, input.count * MemoryLayout<Float32>.size)

        let outCap = AVAudioFrameCount(ceil(Double(input.count) * dstRate / srcRate)) + 256
        guard let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: outCap) else { return input }

        var consumed = false
        var error: NSError?
        converter.convert(to: dstBuf, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true; status.pointee = .haveData; return srcBuf
        }
        if error != nil { return input }
        return Array(UnsafeBufferPointer(start: dstBuf.floatChannelData![0], count: Int(dstBuf.frameLength)))
    }
}
