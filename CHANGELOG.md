# Changelog

## 0.2.2 — 2026-10-29

- **The call offer names the right app and can be declined.** The pill offered to record "an app" when Siri's speech daemon held the microphone; only real apps count now, and a browser's helper process is named after the browser. The offer has a "Not now" chip; a declined call is not offered again until that app lets go of the mic.
- **A steadier, narrower pill.** The same small frame for listening, thinking, the tick, the meeting clock and the notes job, so the pill keeps one height and one width across states; fewer bars while listening so it reaches out less. The meeting clock is just the time, the notes job just the percentage.

## 0.2.1 — 2026-10-28

- **Silence filter tuned.** 0.2.0 applied Whisper's confidence thresholds to every line and lost some real but badly heard speech. They now apply to short lines only, where hallucinations live; a looping decoder is still dropped at any length. Measured on a 29-minute call: 95% of the words kept over the real part, half the junk after it gone.
- **Cancel speaker echo** (Settings → Meetings → Transcript, off by default): Apple's voice processing on the meeting microphone, for a desk mic next to speakers. Leave it off with headphones.

## 0.2.0 — 2026-10-28

- **The recording stops itself when the call ends.** Speakhold remembers which app was on the call when you pressed record; once that app has let go of the microphone for ten seconds, the pill counts down 45 seconds and stops, with a *Keep going* chip if the call is only reconnecting. Recordings started with no call app running (a meeting in the room) are left alone.
- **No more "Thank you. Thank you." over silence.** Whisper's stock lines over quiet audio are dropped when the decoder was unsure of them or when they are nothing but the phrase repeated, and a short line decoded twice in a row is kept once. Eight minutes of an empty room produced a page of them on 28 Oct.
- **Meeting notes through Claude Code, no API key.** If Claude Code is installed on the Mac, the notes (and the follow-up email) go through it in print mode under your own Claude login and plan, nothing billed to an API. On by default when it is found; Settings → Meetings → Notes shows *Written by: Claude Code · sonnet*, with a switch and a model field. Order is Claude Code, then an API key, then Apple Intelligence on-device. A 29-minute call came back in 18 seconds.
- **Fixed: stopping a meeting could leave the microphone running and never write the notes.** The background job asked for notification permission first and waited for the answer; until the prompt was clicked the capture kept going and nothing was transcribed. The capture now stops the moment you press stop, and the permission request no longer holds the job. While the notes are being written the pill rests on amber dots with *Notes 41%* instead of going idle, so the work is visible without opening the menu. `--meeting-from-files` takes `--title`.
- **A short, glowing pill that never grows.** Hold the chord and the tab opens to one fixed-size pill of neon bars; the three dots while transcribing and the tick once pasted sit in the same frame, so nothing resizes while you work. The words-as-you-speak stream (which ran the pill across the screen) is gone from the pill and its setting removed. The bars now span from the quiet floor to the recent peak of your own microphone, so speech fills the meter whether the mic is hot or quiet (before, a quiet USB mic drew a flat half-height line). The pill is a few points tighter, and once the text is pasted it shows only the tick and Undo for a moment and goes back to the idle bars; the words are already in your app.
- **Notes are written in the background.** Stopping a recording hands the transcription to a background job: the pill goes back to normal within seconds, dictation keeps working (a hold-to-talk takes priority between regions), the menu bar shows *Writing notes: <title> — Transcribing 42%*, the meeting window shows a progress bar, and a system notification says when the file is ready (click it to open). A failed job keeps the recording in the temp folder and says where. Quitting mid-job asks first.
- **Settings say which engine writes the notes.** The Claude key and model have their own card under Cleanup, always visible (they were hidden unless Claude was the polish engine), and Settings → Meetings → Notes shows *Written by: Claude · model* or *Apple Intelligence, on-device* with what that means, the key field when there is none, where the files save, and that the job runs in the background.
- **Long meetings on-device.** Apple Intelligence holds only a few hundred words at a time, so a long transcript is summarised in parts and then written up from the parts, with a caveat line; before this it failed and the file said no notes engine was available. When notes fail the file now says why. `Speakhold --notes-from-transcript "<meeting>.md"` rewrites the Notes section of a saved meeting with the engine configured now (after setting a Claude key, say).
- **Meetings, the full set.** Your own notes during the call (a meeting window; the transcript expands them afterwards), **Mark this moment** (menu, window, or a single tap of the dictation chord), **Catch me up** (the last two minutes as text), title and invitees from the Calendar event happening now, the other voices told apart on-device (**Speaker 1, 2, 3**), an optional **follow-up email draft**, a **Save notes to** folder, **Parakeet** as a faster transcription engine for long meetings (optional, ~600 MB), and an **offer to record** when any app starts using the microphone. Audio streams to a temp file during the call, so length is no longer limited by memory, and is deleted once the notes are written. Settings → Meetings.
- **Record meeting** (menu bar, Dock menu, `Speakhold --meeting`): records both sides of a call on this Mac, the microphone and whatever the Mac is playing (Core Audio process tap, macOS 14.2+, no BlackHole), shows a red dot with the elapsed time in the pill, and on stop transcribes both streams on the Neural Engine, merges them by time as you / Them, writes notes (Claude if a key is set, otherwise Apple Intelligence) and saves one markdown file to `~/Documents/Speakhold Meetings/`, then opens it. Audio is discarded. First use asks for "System Audio Recording Only".
- **Polish on this Mac with Apple Intelligence** (macOS 26, Apple silicon): the default polish engine is now Apple's on-device model, so filler removal and punctuation need no API key and nothing leaves the machine. Claude stays as the opt-in engine under Settings → Cleanup → "Polish with". A length guard keeps the raw transcript if a model answers instead of editing.
- Spoken commands ("new paragraph", "new line", "full stop", "comma", "question mark", "exclamation mark") are applied deterministically before any model, so they work with polish off too.
- **Undo** on the pill for three seconds after a paste (sends ⌘Z to the app you dictated into). **Try again** on the error pill re-runs the last recording.
- **Hands-free lock:** while holding the chord, tap Space; let go and keep talking. Press the chord again to finish, Esc to cancel. The pill shows a lock while locked.
- **Text replacements** (Settings → Cleanup): one per line, `spoken -> written`, whole phrase, any case.
- **Remote control:** `Speakhold --toggle | --start | --stop | --cancel | --settings | --history` talks to the running copy, as does `open speakhold://toggle`. For SketchyBar, Raycast, Shortcuts and scripts.
- `--polish "text"` headless flag runs the polish pipeline on a string.
- Settings and History windows redrawn in the bar's ink/mint language: sidebar, hairline cards, mint toggles, the shortcut as a chip, a waveform level meter, and a live miniature of the pill that follows your position / idle-tab / live-words choices.
- App icon redrawn to match (ink squircle, mint waveform). `swift scripts/make-icon.swift` regenerates it.
- Speakhold now keeps an icon in the Dock by default: click it to open Settings, right-click for Start dictation / Settings / History. Turn it off under Settings → General → App → "Show in the Dock" for menu-bar only.
- A real main menu, so ⌘V works in the API-key field and ⌘, / ⌘W / ⌘Q work while a window is open.
- Headless `--render-settings dir` renders each settings tab to PNG for layout checks.

## 0.1.2 — 2026-10-21

- New look for the bar: navy-slate ink, hairline border, mint waveform and status colours (mint / amber / red); idle is a small vertical lozenge docked to the right screen edge just above centre (new default position).
- Live transcript in the pill while you hold the key (Willow-style): words appear as you speak, newest words stay visible. Toggle under Settings → General → "Show words in the pill while you speak".
- Idle state is a small tab that hugs the screen edge; the pill floats just above it while active.
- Fixed a crash when changing the pill position / idle-tab settings while the overlay was on screen (Swift exclusivity abort inside SwiftUI layout).

## 0.1.0 — 2026-10-20

First public release.

- Push-to-talk dictation with on-device WhisperKit (Large v3 Turbo default)
- Chord hotkeys with left/right-specific modifiers, optional F-key, hold or toggle
- Willow-style floating pill with live waveform, Esc to cancel
- Pastes into the frontmost app and restores your clipboard
- Optional Claude cleanup pass with personal dictionary and style notes
- History window, launch at login, menu-bar only
