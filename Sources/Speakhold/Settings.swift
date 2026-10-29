import Foundation
import AppKit
import Combine

/// A single physical modifier key. Device-specific CGEventFlags bits let us tell left from right.
enum ModKey: String, CaseIterable, Codable, Identifiable {
    case lctrl, lopt, lshift, lcmd, rctrl, ropt, rshift, rcmd, fn
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lctrl: return "Left ⌃ Control"
        case .lopt: return "Left ⌥ Option"
        case .lshift: return "Left ⇧ Shift"
        case .lcmd: return "Left ⌘ Command"
        case .rctrl: return "Right ⌃ Control"
        case .ropt: return "Right ⌥ Option"
        case .rshift: return "Right ⇧ Shift"
        case .rcmd: return "Right ⌘ Command"
        case .fn: return "fn / 🌐"
        }
    }
    var short: String {
        switch self {
        case .lctrl: return "L⌃"; case .lopt: return "L⌥"; case .lshift: return "L⇧"; case .lcmd: return "L⌘"
        case .rctrl: return "R⌃"; case .ropt: return "R⌥"; case .rshift: return "R⇧"; case .rcmd: return "R⌘"
        case .fn: return "fn"
        }
    }
    /// NX_DEVICE* masks from IOKit/hidsystem/IOLLEvent.h, present in CGEventFlags.rawValue.
    var deviceMask: UInt64 {
        switch self {
        case .lctrl: return 0x0000_0001
        case .lshift: return 0x0000_0002
        case .rshift: return 0x0000_0004
        case .lcmd: return 0x0000_0008
        case .rcmd: return 0x0000_0010
        case .lopt: return 0x0000_0020
        case .ropt: return 0x0000_0040
        case .rctrl: return 0x0000_2000
        case .fn: return 0x0080_0000
        }
    }
}

/// Optional non-modifier key that completes the chord.
enum PlainKey: String, CaseIterable, Codable, Identifiable {
    case none, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    var id: String { rawValue }
    var label: String { self == .none ? "None (modifiers only)" : rawValue.uppercased() }
    static func from(keyCode: UInt16) -> PlainKey? { allCases.first { $0.keyCode == keyCode } }
    var keyCode: UInt16? {
        switch self {
        case .none: return nil
        case .f1: return 122; case .f2: return 120; case .f3: return 99; case .f4: return 118
        case .f5: return 96; case .f6: return 97; case .f7: return 98; case .f8: return 100
        case .f9: return 101; case .f10: return 109; case .f11: return 103; case .f12: return 111
        }
    }
}

struct HotkeyCombo: Codable, Equatable {
    var mods: Set<ModKey>
    var key: PlainKey
    static let standard = HotkeyCombo(mods: [.lctrl, .lopt], key: .none)
    var isValid: Bool { !mods.isEmpty || key != .none }
    var label: String {
        let parts = ModKey.allCases.filter { mods.contains($0) }.map(\.short) + (key == .none ? [] : [key.label])
        return parts.isEmpty ? "Not set" : parts.joined(separator: " + ")
    }
}

enum PillPosition: String, CaseIterable, Identifiable {
    case bottomCenter, bottomRight, rightEdge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottomCenter: return "Bottom centre"
        case .bottomRight: return "Bottom right, flush to the edge"
        case .rightEdge: return "Right edge, mid-height"
        }
    }
}

enum HotkeyMode: String, CaseIterable, Identifiable {
    case hold, toggle
    var id: String { rawValue }
    var label: String { self == .hold ? "Hold to talk" : "Press to start / stop" }
}

enum WhisperModel: String, CaseIterable, Identifiable {
    case turbo = "openai_whisper-large-v3-v20240930_turbo_632MB"
    case largeV3 = "openai_whisper-large-v3-v20240930_626MB"
    case distil = "distil-whisper_distil-large-v3_turbo_600MB"
    case base = "openai_whisper-base.en"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .turbo: return "Large v3 Turbo (recommended, ~630 MB)"
        case .largeV3: return "Large v3 (most accurate, slower)"
        case .distil: return "Distil Large v3 (fastest large)"
        case .base: return "Base English (tiny, quick test)"
        }
    }
}

enum MeetingEngine: String, CaseIterable, Identifiable {
    case whisper, parakeet
    var id: String { rawValue }
    var label: String { self == .whisper ? "Whisper (slower, any language)" : "Parakeet (fast, English only, ~600 MB)" }
}

/// Which model turns a dictation into text. Whisper takes the personal dictionary as a decoder prompt and knows
/// ~100 languages; Parakeet (NVIDIA's English 0.6B model, via FluidAudio) is several times faster and does not
/// invent "Thank you" over silence. English only; the dictionary is applied by the cleanup pass instead.
enum DictationEngine: String, CaseIterable, Identifiable {
    case whisper, parakeet
    var id: String { rawValue }
    var label: String { self == .whisper ? "Whisper (any language, dictionary in the decoder)" : "Parakeet (faster, English only)" }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var hotkey: HotkeyCombo {
        didSet { if let data = try? JSONEncoder().encode(hotkey) { d.set(data, forKey: "hotkeyCombo") } }
    }
    @Published var mode: HotkeyMode { didSet { d.set(mode.rawValue, forKey: "mode") } }
    @Published var model: WhisperModel { didSet { d.set(model.rawValue, forKey: "model") } }
    @Published var cleanupEngine: CleanupEngine { didSet { d.set(cleanupEngine.rawValue, forKey: "cleanupEngine") } }
    /// One per line: `spoken -> written`. Applied after the model pass.
    @Published var replacements: String { didSet { d.set(replacements, forKey: "replacements") } }
    @Published var cleanupModel: String { didSet { d.set(cleanupModel, forKey: "cleanupModel") } }
    /// Meeting notes through Claude Code on this Mac (the user's own login) when it is installed.
    @Published var notesViaClaudeCode: Bool { didSet { d.set(notesViaClaudeCode, forKey: "notesViaClaudeCode") } }
    @Published var claudeCodeModel: String { didSet { d.set(claudeCodeModel, forKey: "claudeCodeModel") } }
    @Published var anthropicKey: String { didSet { d.set(anthropicKey, forKey: "anthropicKey") } }
    @Published var dictionary: String { didSet { d.set(dictionary, forKey: "dictionary") } }
    @Published var styleNotes: String { didSet { d.set(styleNotes, forKey: "styleNotes") } }
    /// Apps where a dictation is sent as soon as it lands: Return is pressed after the paste. One per line, app name
    /// or bundle id, case-insensitive. Empty by default (#11).
    @Published var returnAfterPasteApps: String { didSet { d.set(returnAfterPasteApps, forKey: "returnAfterPasteApps") } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }
    @Published var language: String { didSet { d.set(language, forKey: "language") } }
    @Published var inputDeviceUID: String { didSet { d.set(inputDeviceUID, forKey: "inputDeviceUID") } }
    @Published var showIdlePill: Bool { didSet { d.set(showIdlePill, forKey: "showIdlePill") } }
    @Published var livePreview: Bool { didSet { d.set(livePreview, forKey: "livePreview") } }
    @Published var pillPosition: PillPosition { didSet { d.set(pillPosition.rawValue, forKey: "pillPosition") } }
    // Meetings
    /// Folder for meeting notes; empty = ~/Documents/Speakhold Meetings.
    @Published var meetingsFolder: String { didSet { d.set(meetingsFolder, forKey: "meetingsFolder") } }
    @Published var meetingAutoOffer: Bool { didSet { d.set(meetingAutoOffer, forKey: "meetingAutoOffer") } }
    @Published var meetingDiarise: Bool { didSet { d.set(meetingDiarise, forKey: "meetingDiarise") } }
    /// Apple voice processing on the meeting microphone: cancels what the speakers play back into a desk mic.
    @Published var meetingEchoCancel: Bool { didSet { d.set(meetingEchoCancel, forKey: "meetingEchoCancel") } }
    @Published var meetingCalendar: Bool { didSet { d.set(meetingCalendar, forKey: "meetingCalendar") } }
    @Published var meetingFollowUp: Bool { didSet { d.set(meetingFollowUp, forKey: "meetingFollowUp") } }
    @Published var meetingEngine: MeetingEngine { didSet { d.set(meetingEngine.rawValue, forKey: "meetingEngine") } }
    @Published var dictationEngine: DictationEngine { didSet { d.set(dictationEngine.rawValue, forKey: "dictationEngine") } }
    /// Parakeet is English only, so a language other than "en" (or auto) falls back to Whisper whatever the picker says.
    var effectiveDictationEngine: DictationEngine {
        let lang = language.trimmingCharacters(in: .whitespaces).lowercased()
        return dictationEngine == .parakeet && (lang.isEmpty || lang == "en") ? .parakeet : .whisper
    }
    /// Whisper is only loaded when dictation uses it, so a Parakeet dictation setup transcribes meetings with Parakeet too.
    var usesParakeetForMeetings: Bool { meetingEngine == .parakeet || effectiveDictationEngine == .parakeet }
    /// Keep an icon in the Dock (click it to open Settings; right-click for the menu). Off = menu-bar only.
    @Published var showInDock: Bool { didSet { d.set(showInDock, forKey: "showInDock") } }

    private init() {
        if let data = d.data(forKey: "hotkeyCombo"), let c = try? JSONDecoder().decode(HotkeyCombo.self, from: data), c.isValid {
            hotkey = c
        } else {
            hotkey = .standard
        }
        mode = HotkeyMode(rawValue: d.string(forKey: "mode") ?? "") ?? .hold
        model = WhisperModel(rawValue: d.string(forKey: "model") ?? "") ?? .turbo
        if let e = CleanupEngine(rawValue: d.string(forKey: "cleanupEngine") ?? "") {
            cleanupEngine = e
        } else if d.object(forKey: "cleanupEnabled") as? Bool == false {
            cleanupEngine = .off                     // pre-0.2 setting carried over
        } else {
            cleanupEngine = Polish.appleAvailable ? .apple : .claude   // Claude only does anything once a key is set
        }
        replacements = d.string(forKey: "replacements") ?? ""
        cleanupModel = d.string(forKey: "cleanupModel") ?? "claude-haiku-5-5"
        notesViaClaudeCode = d.object(forKey: "notesViaClaudeCode") as? Bool ?? true
        claudeCodeModel = d.string(forKey: "claudeCodeModel") ?? "sonnet"
        anthropicKey = d.string(forKey: "anthropicKey") ?? Settings.keyFromEnvironment()
        dictionary = d.string(forKey: "dictionary") ?? ""
        styleNotes = d.string(forKey: "styleNotes") ?? ""
        returnAfterPasteApps = d.string(forKey: "returnAfterPasteApps") ?? ""
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        language = d.string(forKey: "language") ?? "en"
        inputDeviceUID = d.string(forKey: "inputDeviceUID") ?? ""
        showIdlePill = d.object(forKey: "showIdlePill") as? Bool ?? true
        livePreview = d.object(forKey: "livePreview") as? Bool ?? false   // off: the pill stays a short glowing bar
        pillPosition = PillPosition(rawValue: d.string(forKey: "pillPosition") ?? "") ?? .rightEdge
        showInDock = d.object(forKey: "showInDock") as? Bool ?? true
        meetingsFolder = d.string(forKey: "meetingsFolder") ?? ""
        meetingAutoOffer = d.object(forKey: "meetingAutoOffer") as? Bool ?? true
        meetingDiarise = d.object(forKey: "meetingDiarise") as? Bool ?? true
        meetingEchoCancel = d.object(forKey: "meetingEchoCancel") as? Bool ?? false
        meetingCalendar = d.object(forKey: "meetingCalendar") as? Bool ?? true
        meetingFollowUp = d.object(forKey: "meetingFollowUp") as? Bool ?? false
        meetingEngine = MeetingEngine(rawValue: d.string(forKey: "meetingEngine") ?? "") ?? .parakeet
        dictationEngine = DictationEngine(rawValue: d.string(forKey: "dictationEngine") ?? "") ?? .parakeet
    }

    /// Picks up ANTHROPIC_API_KEY from the environment on first launch so there is nothing to paste.
    static func keyFromEnvironment() -> String {
        let v = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        return v.hasPrefix("sk-ant-api") ? v : ""
    }

    /// True when the frontmost app (by localised name or bundle id) is on the Return-after-paste list.
    func pressesReturn(appName: String?, bundleID: String?) -> Bool {
        let wanted = returnAfterPasteApps.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return false }
        let name = appName?.lowercased() ?? "", bundle = bundleID?.lowercased() ?? ""
        return wanted.contains { !$0.isEmpty && ($0 == name || $0 == bundle || (!bundle.isEmpty && bundle.hasSuffix("." + $0))) }
    }

    var dictionaryTerms: [String] {
        dictionary.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
