import AVFoundation
import Foundation
#if canImport(Speech)
import Speech
#endif

/// Apple's on-device SpeechAnalyzer (macOS 26+): no model download, the OS manages the assets (#12). Used as a
/// third dictation engine. The personal dictionary is applied by the cleanup pass, as with Parakeet.
enum AppleSpeech {
    static var available: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

#if canImport(Speech)
@available(macOS 26.0, *)
actor AppleSpeechTranscriber {
    private var installedLocale: String?

    private static func locale(for language: String) -> Locale {
        let lang = language.trimmingCharacters(in: .whitespaces).lowercased()
        if lang.isEmpty || lang == "en" { return Locale(identifier: "en-US") }
        return Locale(identifier: lang)
    }

    /// Makes sure the OS has the speech assets for the language (downloads them through the system if not).
    func prepare(language: String) async throws {
        let loc = Self.locale(for: language)
        if installedLocale == loc.identifier { return }
        let transcriber = SpeechTranscriber(locale: loc, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        installedLocale = loc.identifier
    }

    /// 16 kHz mono float samples → text, one shot.
    func text(_ samples: [Float], language: String) async throws -> String {
        try await prepare(language: language)
        let transcriber = SpeechTranscriber(locale: Self.locale(for: language), preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw NSError(domain: "Speakhold", code: 30, userInfo: [NSLocalizedDescriptionKey: "Apple speech: no audio format."])
        }
        guard let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let src = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(max(samples.count, 1))) else {
            throw NSError(domain: "Speakhold", code: 31, userInfo: [NSLocalizedDescriptionKey: "Apple speech: buffer."])
        }
        src.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { p in src.floatChannelData![0].update(from: p.baseAddress!, count: samples.count) }
        let buffer: AVAudioPCMBuffer
        if format.sampleRate == srcFormat.sampleRate, format.channelCount == 1, format.commonFormat == .pcmFormatFloat32 {
            buffer = src
        } else {
            guard let converter = AVAudioConverter(from: srcFormat, to: format),
                  let dst = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(samples.count) * format.sampleRate / 16_000) + 4096) else {
                throw NSError(domain: "Speakhold", code: 32, userInfo: [NSLocalizedDescriptionKey: "Apple speech: converter."])
            }
            var fed = false
            var convError: NSError?
            converter.convert(to: dst, error: &convError) { _, status in
                if fed { status.pointee = .endOfStream; return nil }
                fed = true; status.pointee = .haveData; return src
            }
            if let convError { throw convError }
            buffer = dst
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()
        let collector = Task { () throws -> String in
            var out = ""
            for try await result in transcriber.results where result.isFinal {
                out += String(result.text.characters)
            }
            return out
        }
        try await analyzer.start(inputSequence: stream)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
