import Foundation
import WhisperKit

/// Wraps WhisperKit: downloads the model on first use, then transcribes 16 kHz float samples.
/// With the Parakeet engine selected it hands dictations to the same Parakeet instance the meeting pipeline uses.
actor Transcriber {
    enum State: Equatable { case idle, downloading(Double), loading, ready, failed(String) }

    /// Shared with meetings so the ~600 MB model is loaded once. A `let` on an actor is readable from outside.
    let parakeet = ParakeetMeetingTranscriber()
    private(set) var engine: DictationEngine = .whisper
    private var parakeetReady = false

    private var kit: WhisperKit?
    private var loadedModel: String?
    private(set) var state: State = .idle
    private var onState: (@Sendable (State) -> Void)?
    func setStateHandler(_ h: @escaping @Sendable (State) -> Void) { onState = h; h(state) }

    private func set(_ s: State) { state = s; onState?(s) }

    func prepare(model: String, engine: DictationEngine = .whisper) async {
        self.engine = engine
        if engine == .parakeet {
            if parakeetReady { set(.ready); return }
            set(.loading)
            do { try await parakeet.prepare(); parakeetReady = true; set(.ready) } catch { set(.failed(error.localizedDescription)) }
            return
        }
        if kit != nil, loadedModel == model { set(.ready); return }
        kit = nil
        set(.downloading(0))
        do {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Speakhold/models")
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let folder = try await WhisperKit.download(
                variant: model,
                downloadBase: base,
                useBackgroundSession: false,
                from: "argmaxinc/whisperkit-coreml",
                token: nil,
                progressCallback: { [weak self] p in
                    guard let self else { return }
                    Task { await self.set(.downloading(p.fractionCompleted)) }
                }
            )
            set(.loading)
            // Keep the tokenizer next to the model: WhisperKit's default is ~/Documents/huggingface, which
            // needs the Files & Folders permission for a bundled app and fails with "could not remove corrupted metadata".
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: base,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            kit = try await WhisperKit(config)
            loadedModel = model
            set(.ready)
        } catch {
            set(.failed(error.localizedDescription))
        }
    }

    /// `fast` is the live preview while recording: no temperature fallback, so a tick costs one decoder pass.
    /// Dictation calls in flight. A background meeting pass waits between regions while this is non-zero, so a
    /// hold-to-talk never queues behind a twenty-minute recording.
    private var dictating = 0

    func transcribe(_ samples: [Float], language: String, promptTerms: [String], fast: Bool = false) async throws -> String {
        dictating += 1
        defer { dictating -= 1 }
        if engine == .parakeet {
            guard parakeetReady else { throw NSError(domain: "Speakhold", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not loaded yet."]) }
            return Transcriber.tidy(try await parakeet.text(samples))
        }
        guard let kit else { throw NSError(domain: "Speakhold", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not loaded yet."]) }
        // Whisper needs at least ~1 s; pad very short clips with silence.
        var audio = samples
        if audio.count < 16_000 { audio.append(contentsOf: [Float](repeating: 0, count: 16_000 - audio.count)) }

        let env = ProcessInfo.processInfo.environment
        var options = DecodingOptions()
        options.language = language.isEmpty ? nil : language
        options.detectLanguage = language.isEmpty
        options.task = .transcribe
        options.skipSpecialTokens = true
        options.withoutTimestamps = true
        options.temperatureFallbackCount = fast ? 0 : 2
        options.chunkingStrategy = .vad
        // Bias the decoder toward names it would otherwise mangle.
        if env["DICTATE_NO_PROMPT"] == nil, !promptTerms.isEmpty, let tok = kit.tokenizer {
            let prompt = " " + promptTerms.joined(separator: ", ") + "."
            options.promptTokens = tok.encode(text: prompt).filter { $0 < tok.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }
        let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        if env["DICTATE_DEBUG"] != nil { NSLog("DEBUG samples=%d results=%d segs=%d text=%@", audio.count, results.count, results.first?.segments.count ?? 0, text) }
        return Transcriber.tidy(text)
    }

    struct Segment: Sendable { var start: Double; var end: Double; var text: String }

    /// Timestamped segments for long recordings (meetings). Speech regions are found first with an energy gate,
    /// each region is decoded on its own and its offset added back, so times stay absolute. Whisper reports a
    /// leading-silence segment as starting at 0 and VAD chunking resets times per chunk, so neither can be trusted alone.
    /// `progress` is the fraction of speech decoded so far (0–1), by samples, so long regions weigh what they cost.
    func transcribeSegments(_ samples: [Float], language: String, promptTerms: [String], progress: (@Sendable (Double) -> Void)? = nil) async throws -> [Segment] {
        guard let kit else { throw NSError(domain: "Speakhold", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not loaded yet."]) }
        var options = DecodingOptions()
        options.language = language.isEmpty ? nil : language
        options.detectLanguage = language.isEmpty
        options.task = .transcribe
        options.skipSpecialTokens = true
        options.withoutTimestamps = false
        options.temperatureFallbackCount = 2
        options.chunkingStrategy = .none
        if !promptTerms.isEmpty, let tok = kit.tokenizer {
            let prompt = " " + promptTerms.joined(separator: ", ") + "."
            options.promptTokens = tok.encode(text: prompt).filter { $0 < tok.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }
        var out: [Segment] = []
        let regions = Transcriber.speechRegions(samples)
        let total = max(1, regions.reduce(0) { $0 + $1.count })
        var done = 0
        for region in regions {
            while dictating > 0 { try await Task.sleep(nanoseconds: 50_000_000) }
            var audio = Array(samples[region])
            if audio.count < 16_000 { audio.append(contentsOf: [Float](repeating: 0, count: 16_000 - audio.count)) }
            let offset = Double(region.lowerBound) / 16_000
            let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)
            done += region.count
            progress?(Double(done) / Double(total))
            for r in results {
                for seg in r.segments {
                    let text = Transcriber.tidy(seg.text)
                    guard !text.isEmpty, seg.noSpeechProb < 0.8 else { continue }
                    guard !Transcriber.looksHallucinated(text, noSpeech: seg.noSpeechProb, logProb: seg.avgLogprob, compression: seg.compressionRatio) else { continue }
                    // The same short line twice in a row inside one region is the decoder looping, not the speaker.
                    if let last = out.last, last.text == text, text.split(separator: " ").count < 6, offset + Double(seg.start) - last.end < 2 { continue }
                    out.append(Segment(start: offset + Double(seg.start), end: offset + Double(seg.end), text: text))
                }
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Whisper's stock lines over quiet audio: "Thank you." (its favourite), "Thanks for watching.", a lone "you".
    /// Eight minutes of an empty room came back as "Thank you. Thankyou. Thank you." on 28 Oct 2026. A matching line
    /// is dropped when the decoder itself was unsure of it, or when it is nothing but the phrase repeated.
    static let stockLines: Set<String> = [
        "thank you", "thankyou", "thanks", "thank you very much", "thanks for watching", "thank you for watching",
        "thanks for listening", "thank you for listening", "see you next time", "see you in the next video",
        "subtitles by the amara org community", "the end", "you", "bye", "okay", "so", "oh", "yeah", "yes", "hmm", "mm",
    ]
    static func looksHallucinated(_ text: String, noSpeech: Float, logProb: Float, compression: Float = 1) -> Bool {
        // A looping decoder ("thank you thank you thank you") compresses too well whatever its length.
        if compression > 2.4 { return true }
        // Whisper's confidence thresholds, applied to short lines only: hallucinations over silence are short,
        // while a long line the decoder was unsure of is usually real speech badly heard, which the notes still need.
        let words = text.split(separator: " ").count
        if words < 8, logProb < -1.0 || (noSpeech > 0.6 && logProb < -0.5) { return true }
        // Sound-effect markers ("*sing*", "[Music]") and lines with no letters at all.
        let bare = text.replacingOccurrences(of: "\\*[^*]*\\*|\\[[^\\]]*\\]|\\([^)]*\\)", with: "", options: .regularExpression)
        let norm = bare.lowercased().unicodeScalars.map { CharacterSet.letters.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
        guard !norm.isEmpty else { return true }
        // Only the phrase, repeated: "thank you thankyou thank you".
        let stripped = norm.replacingOccurrences(of: "thank you", with: "").replacingOccurrences(of: "thankyou", with: "")
            .replacingOccurrences(of: "thanks", with: "").replacingOccurrences(of: "you", with: "")
            .trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty, norm.count > "thank you".count { return true }
        guard stockLines.contains(norm) else { return false }
        return noSpeech > 0.15 || logProb < -0.5
    }

    /// Energy gate: 20 ms frames, threshold a few times the quietest fifth of the recording, regions merged across
    /// gaps under 0.8 s and padded by 0.25 s. Cheap, and it also means silence is never sent to the decoder.
    static func speechRegions(_ samples: [Float]) -> [Range<Int>] {
        let frame = 320, rate = 16_000
        guard samples.count >= frame else { return samples.isEmpty ? [] : [0..<samples.count] }
        let n = samples.count / frame
        var rms = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var acc: Float = 0
            for j in 0..<frame { let v = samples[i * frame + j]; acc += v * v }
            rms[i] = (acc / Float(frame)).squareRoot()
        }
        let sorted = rms.sorted()
        let floor = sorted[sorted.count / 5]
        let threshold = max(floor * 4, 0.006)
        var regions: [Range<Int>] = []
        var start: Int? = nil
        var silent = 0
        let maxGap = Int(0.8 * Double(rate)) / frame, pad = Int(0.25 * Double(rate))
        for i in 0..<n {
            if rms[i] >= threshold {
                if start == nil { start = i }
                silent = 0
            } else if let s = start {
                silent += 1
                if silent > maxGap {
                    regions.append(max(0, s * frame - pad)..<min(samples.count, (i - silent) * frame + pad))
                    start = nil; silent = 0
                }
            }
        }
        if let s = start { regions.append(max(0, s * frame - pad)..<samples.count) }
        return regions.filter { $0.count >= rate / 2 }
    }

    /// Test hook: transcribe an audio file on disk (any format AVFoundation reads).
    func transcribeFile(_ path: String, language: String, promptTerms: [String]) async throws -> String {
        let buffer = try AudioProcessor.loadAudio(fromPath: path)
        let samples = AudioProcessor.convertBufferToArray(buffer: buffer)
        return try await transcribe(samples, language: language, promptTerms: promptTerms)
    }

    /// Whisper's raw output has doubled spaces and the occasional hallucinated tag; squash them.
    static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<\\|[^|>]*\\|>", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
