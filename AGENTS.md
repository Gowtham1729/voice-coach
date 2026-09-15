# AGENTS.md

Operating manual for coding agents. Prefer this over guessing; prefer `VoiceCoachSelfTest` over the README when contracts disagree. Keep this file short — put one-off task detail in the chat, not here.

## What this repo is

Local-first **macOS 26+** SwiftUI voice practice studio (Swift 6.2). Record/import takes, run on-device acoustic analysis + optional Parakeet transcription, persist a private session library. Not a web app; nothing uploads recordings.

## Layout (where to edit)

| Area | Path | Notes |
| --- | --- | --- |
| DSP / models / reports / ASR adapter | `Sources/VoiceCoachCore/` | Linux-buildable when AVFoundation is missing |
| App UI, recording, persistence | `Sources/VoiceCoachApp/` | macOS-only (SwiftUI/AppKit/Metal) |
| Contract suite | `Sources/VoiceCoachSelfTest/main.swift` | Real verification — `Tests/` is empty/unused |
| App bundle resources | `Resources/` | Packaged by `scripts/build-app.sh` |
| Dev/scripts | `scripts/` | Prefer these over inventing new build steps |

**Naming trap:** UI “session” = `CoachingSession` (`SessionLibrary.swift`). UI “take” = Core `PracticeSession` (`Models.swift`). Do not rename these casually.

## Commands

Run from repo root. Prefer the Xcode toolchain when present (scripts do this).

```sh
# Fast contract check (DSP + report JSON). Use after Core/report/transcription changes.
swift run VoiceCoachSelfTest

# Dev app (macOS only)
swift run VoiceCoachApp

# Release .app → build/Voice Coach.app (ad-hoc codesign)
./scripts/build-app.sh

# SelfTest + 8 DEBUG layout PNGs in build/previews (synthetic audio only)
./scripts/render-previews.sh

# One-time local ASR (~714 MB). Prefer Settings → Transcription in the app for end users.
./scripts/setup-transcription.sh
```

**Cloud / Linux agents:** `.cursor/environment.json` runs `./scripts/cloud-agent-install.sh`, which builds **only** `--product VoiceCoachSelfTest`. Do not try to build or run `VoiceCoachApp` there.

**Flags that matter:**
- App/script builds that touch AVFoundation often need `--disable-sandbox` (already in `build-app.sh` / `render-previews.sh`).
- Override ASR binary: `VOICE_COACH_NEMO_SPEECH_PATH=/path/to/nemo-speech`.
- DEBUG only: `VoiceCoachApp --render-previews <dir>` (wired in `RenderPreviews.swift`).
- SelfTest live helpers (optional): `--transcribe`, `--timeline`, `--inspect-pitch`, `--dump-sample-report`.

If macOS refuses the toolchain with an Xcode license error, the human must run `sudo xcodebuild -license` — agents cannot accept it.

## Verification rules

| Change | Minimum check |
| --- | --- |
| `VoiceCoachCore` / report shape / SelfTest | `swift run VoiceCoachSelfTest` |
| App UI / layout / charts / Take/Studio | `./scripts/render-previews.sh` when feasible (macOS); otherwise say UI was not visually verified |
| Persistence / SessionStore | Prefer preview path (it round-trips a fixture library) or exercise save/load carefully |
| Transcription setup scripts | Do not re-download the model in CI/cloud unless explicitly asked |

Do not add SPM `testTarget` wiring unless asked — the empty `Tests/VoiceCoachCoreTests/` folder is not the suite.

## Non-negotiable product constraints

- **Local-first / privacy:** No cloud upload paths. Mic copy and Settings must stay “on-device / local only.”
- **Not medical:** HNR/CPP and related metrics are acoustic coaching signals. UI/settings/coach copy must not diagnose or claim diaphragm proof. Report JSON must not contain subjective coaching language (`baseline`, `throat`, `please` — SelfTest enforces).
- **Platform:** `Package.swift` targets **macOS 26** for Liquid Glass APIs. Do not lower the SPM platform to match `Resources/Info.plist` `LSMinimumSystemVersion` (currently 14.0) without an explicit product decision.
- **Materials:** System chrome may use Liquid Glass (`.glass` / `.glassProminent` / `ControlGlass`). Content panels stay on standard materials (`.desktopPanel` / `.studioCard` → regularMaterial), not glass. Honor Reduce Transparency / Reduce Motion via existing `Studio` / `StudioMotion` helpers.
- **Analysis without ASR:** Transcription failure is soft — take still saves with notice; do not hard-fail the record/import pipeline when `nemo-speech` is missing.

## Report / analysis contracts (easy to get wrong)

- Exported / copied report in the app uses `ReportFormatter.makeReport` (expanded). `makeCompactReport` exists for V1 contract tests but is **not** wired to a UI control.
- Contours in JSON are **24** values (`contour_semitones` / `contour_relative_db`). README “12” is stale — trust SelfTest.
- `cppDB` is computed in analysis and **must stay out** of report JSON (`cpp_db` forbidden). `hnr_db` is the voice-quality export field.
- Dense `acousticFrames`, waveform, and spectrogram stay in the in-app `AnalysisResult` (and thus in `session-library.json`); they are not part of the exported report.
- Word metrics come from `AcousticFrameData` via `WordAcousticAnalyzer`, not from the downsampled UI contours.

## Persistence facts

Root: `~/Library/Application Support/VoiceCoach/`

- `session-library.json` — schemaVersion **1** only; atomic write; embeds full take analysis (can grow large).
- `Sessions/<sessionUUID>/take-<takeUUID>.wav` or `…-imported.wav`
- `keepsRecordings == false` → replace prior takes and delete old WAVs after successful save.
- Deleting a session removes its folder; deleting a take removes that take’s audio file after index save succeeds.
- Recording: 48 kHz mono PCM, auto-stop ~90s, discard/analyze gate ~0.6s.

## Where common work lands

| Task | Start here |
| --- | --- |
| Pitch / pauses / HNR / CPP / spectrogram | `AudioAnalyzer.swift` |
| Per-word pitch/loudness | `WordAcousticAnalyzer.swift` |
| JSON export shape | `ReportFormatter.swift` + SelfTest assertions |
| Parakeet / nemo-speech | `NemoSpeechTranscriber.swift`, `scripts/setup-transcription.sh` |
| Import normalize to WAV | `AudioImportService.swift` |
| Record / playback | `AudioRecorder.swift`, `AppModel.swift` |
| Session CRUD / navigation | `AppModel.swift`, `SessionLibrary.swift` |
| Shell / sidebar / inspectors | `ContentView.swift`, `DesktopShell.swift` |
| Take screen / charts / transcript | `TakeView.swift`, `Charts.swift`, `TranscriptBrowser.swift` |
| Palette / glass / motion | `StudioStyle.swift` |
| Fixture screenshots | `RenderPreviews.swift`, `scripts/render-previews.sh` |

## Boundaries

- Do not commit `.build/`, `build/`, or personal WAVs/recordings (see `.gitignore`).
- Do not treat `docs/screenshots/` as live UI truth without regenerating when layout changes.
- Ask before adding dependencies, lowering the macOS deployment target in SPM, or introducing network/cloud analysis.
- Prefer extending SelfTest contracts when changing report keys or acoustic invariants.

## Pointers

- Human-oriented product docs: `README.md`
- Cloud bootstrap: `scripts/cloud-agent-install.sh`
- Official AGENTS.md convention: https://agents.md/
