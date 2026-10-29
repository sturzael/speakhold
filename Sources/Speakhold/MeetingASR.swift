import FluidAudio
import Foundation

/// Parakeet (NVIDIA, CoreML via FluidAudio): much faster than Whisper on long recordings, English-first.
/// Models download on first use (~600 MB) into FluidAudio's cache. Speech regions are found the same way as
/// for Whisper, so segment times stay absolute and silence is never decoded.
actor ParakeetMeetingTranscriber: MeetingTranscriber {
    private var manager: UnifiedAsrManager?
    private(set) var status = "Not loaded"
    private var ctc: CtcModels?
    private var boostedTerms: [String] = []

    /// Personal dictionary inside the decoder (#9): FluidAudio's CTC keyword spotting rescored against the terms.
    /// The CTC models are a separate download, fetched the first time a non-empty dictionary is set, so this is
    /// called at model-load time, not from a dictation. Terms under three characters are skipped (false positives).
    func setVocabulary(_ terms: [String], progress: ((String) -> Void)? = nil) async {
        let clean = Array(Set(terms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 })).sorted()
        guard clean != boostedTerms, let manager else { return }
        do {
            if ctc == nil, !clean.isEmpty {
                status = "Downloading dictionary model…"; progress?(status)
                ctc = try await CtcModels.downloadAndLoad()
            }
            guard let ctc else { return }
            let context = CustomVocabularyContext(terms: clean.map { CustomVocabularyTerm(text: $0) })
            try await manager.configureVocabularyBoosting(vocabulary: context, ctcModels: ctc)
            boostedTerms = clean
            status = "Ready"; progress?(status)
        } catch {
            NSLog("Speakhold: Parakeet vocabulary boosting failed: %@", error.localizedDescription)
            status = "Ready"; progress?(status)
        }
    }

    func prepare(progress: ((String) -> Void)? = nil) async throws {
        if manager != nil { return }
        status = "Downloading Parakeet…"; progress?(status)
        let m = UnifiedAsrManager()
        try await m.loadModels()
        manager = m
        status = "Ready"; progress?(status)
    }

    /// One short clip (a dictation) to text. Parakeet wants at least a second; shorter clips are padded.
    func text(_ samples: [Float]) async throws -> String {
        try await prepare()
        guard let manager else { return "" }
        var audio = samples
        if audio.count < 16_000 { audio.append(contentsOf: [Float](repeating: 0, count: 16_000 - audio.count)) }
        return try await manager.transcribe(audio).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func segments(_ samples: [Float], language: String, promptTerms: [String], progress: (@Sendable (Double) -> Void)?) async throws -> [Transcriber.Segment] {
        try await prepare()
        await setVocabulary(promptTerms)
        guard let manager else { return [] }
        var out: [Transcriber.Segment] = []
        let regions = Transcriber.speechRegions(samples)
        let total = max(1, regions.reduce(0) { $0 + $1.count })
        var done = 0
        for region in regions {
            var audio = Array(samples[region])
            if audio.count < 16_000 { audio.append(contentsOf: [Float](repeating: 0, count: 16_000 - audio.count)) }
            let text = try await manager.transcribe(audio).trimmingCharacters(in: .whitespacesAndNewlines)
            done += region.count
            progress?(Double(done) / Double(total))
            guard !text.isEmpty else { continue }
            out.append(Transcriber.Segment(start: Double(region.lowerBound) / 16_000, end: Double(region.upperBound) / 16_000, text: text))
        }
        return out
    }
}

/// Offline speaker diarisation (pyannote community pipeline on CoreML, via FluidAudio). Models download on
/// first use. Returns turns with integer speaker ids.
actor FluidMeetingDiarizer: MeetingDiarizer {
    private var manager: OfflineDiarizerManager?

    func prepare() async throws {
        if manager != nil { return }
        let m = OfflineDiarizerManager(config: .default)
        try await m.prepareModels()
        manager = m
    }

    func turns(_ samples: [Float]) async throws -> [SpeakerTurn] {
        try await prepare()
        guard let manager, samples.count >= 16_000 * 2 else { return [] }
        let result = try await manager.process(audio: samples)
        var ids: [String: Int] = [:]
        return result.segments.map { seg in
            if ids[seg.speakerId] == nil { ids[seg.speakerId] = ids.count + 1 }
            return SpeakerTurn(speaker: ids[seg.speakerId]!, start: Double(seg.startTimeSeconds), end: Double(seg.endTimeSeconds))
        }
    }
}
