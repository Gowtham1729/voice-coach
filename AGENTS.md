# AGENTS.md

Operating manual for coding agents. Prefer this over guessing; prefer `VoiceCoachSelfTest` over the README when contracts disagree. Keep this file short — put one-off task detail in the chat, not here.

## What this repo is

Local-first **macOS 26+** SwiftUI voice practice studio (Swift 6.2). Record/import takes, run on-device acoustic analysis + optional Parakeet transcription, persist a private recordings library. Not a web app; nothing uploads recordings.

## Layout (where to edit)

| Area | Path | Notes |
| --- | --- | --- |
| DSP / reports / ASR | `Sources/VoiceCoachCore/` | Platform-light library; Linux-buildable when AVFoundation is missing |
| Session domain / persistence | `Sources/VoiceCoachSession/` | Foundation-only library over `VoiceCoachCore` |
| App coordination / UI / capture | `Sources/VoiceCoachApp/` | macOS-only; organized by App, Application, Features, Services, and DesignSystem |
| Unit suites | `Tests/VoiceCoachCoreTests/`, `Tests/VoiceCoachSessionTests/` | Swift Testing coverage for pure contracts and persistence |
| Integration contract suite | `Sources/VoiceCoachSelfTest/main.swift` | Cross-platform acoustic/report smoke and live helpers |
| App bundle resources | `Resources/` | Packaged by `scripts/build-app.sh` |
| Dev/scripts | `scripts/`, `script/build_and_run.sh` | Prefer these over inventing new build steps |

**Naming trap:** UI “recording” / retry stack / Mimic map onto `CoachingSession` (`Sources/VoiceCoachSession/Models/CoachingSession.swift`). UI “take” = Core `PracticeSession` (`Sources/VoiceCoachCore/Models/PracticeSession.swift`). Do not rename these storage types casually.

## Commands

Run from repo root. Prefer the Xcode toolchain when present (scripts do this).

```sh
# Fast contract check (DSP + report JSON). Use after Core/report/transcription changes.
./scripts/test.sh --self-test

# Unit tests (Core + Session domain/persistence).
./scripts/test.sh

# Dev app (macOS only)
./script/build_and_run.sh

# Release .app → build/Voice Coach.app (ad-hoc codesign)
./scripts/build-app.sh

# SelfTest + DEBUG layout PNGs in build/previews (synthetic audio only)
./scripts/render-previews.sh

# One-time local ASR (~714 MB). Prefer Settings → Transcription in the app for end users.
./scripts/setup-transcription.sh
```

**Cloud / Linux agents:** `.cursor/environment.json` runs `./scripts/cloud-agent-install.sh`, which builds **only** `--product VoiceCoachSelfTest`. Do not try to build or run `VoiceCoachApp` there.

**Flags that matter:**
- App/script builds that touch AVFoundation often need `--disable-sandbox` (already in `build-app.sh` / `render-previews.sh`).
- Override ASR binary: `VOICE_COACH_NEMO_SPEECH_PATH=/path/to/nemo-speech`.
- DEBUG only: `VoiceCoachApp --render-previews <dir>` (wired in `RenderPreviews.swift`).
- App runner modes: `--debug`, `--logs`, `--telemetry`, `--verify`.
- SelfTest live helpers (optional): `./scripts/test.sh --self-test --transcribe`, `--timeline`, `--inspect-pitch`, `--dump-sample-report`.

If macOS refuses the toolchain with an Xcode license error, the human must run `sudo xcodebuild -license` — agents cannot accept it.

## Verification rules

| Change | Minimum check |
| --- | --- |
| `VoiceCoachCore` / report shape | `./scripts/test.sh --all` |
| `VoiceCoachSession` / persistence | `./scripts/test.sh`; add or update a focused persistence test |
| App UI / layout / charts / Home/Library/Take | `./scripts/render-previews.sh` when feasible (macOS); otherwise say UI was not visually verified |
| Persistence / SessionStore | Prefer preview path (it round-trips a fixture library) or exercise save/load carefully |
| Transcription setup scripts | Do not re-download the model in CI/cloud unless explicitly asked |

Keep `VoiceCoachSelfTest` as the integration/contract smoke. Put deterministic unit and persistence coverage in the Swift Testing targets instead of growing `main.swift` further.

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
- Dense `acousticFrames`, waveform, and spectrogram stay in the in-app `AnalysisResult` (and thus in per-take analysis files); they are not part of the exported report.
- Word metrics come from `AcousticFrameData` via `WordAcousticAnalyzer`, not from the downsampled UI contours.

## Persistence facts

Root: `~/Library/Application Support/VoiceCoach/`

- `session-library.json` — schemaVersion **3** thin index (session metadata + take stubs only). Versions 1–2 (fat, embedded analysis) migrate on load; a one-time `session-library-v1-backup.json` / `session-library-v2-backup.json` is kept.
- `Sessions/<sessionUUID>/take-<takeUUID>.analysis.json` — full `AnalysisResult` + transcript/words for that take (and Mimic reference).
- `Sessions/<sessionUUID>/take-<takeUUID>.wav` or `…-imported.wav`; Mimic reference audio is `reference.wav`.
- Metadata edits (rename, Mimic style) rewrite the thin index only; new/changed takes also write their analysis blob.
- `keepsRecordings == false` → replace prior takes and delete old WAVs/analysis after successful save. New recordings always keep every valid take; legacy replace-only folders prompt before the next save.
- Deleting a Mimic removes its folder; deleting a recording removes that take’s audio + analysis after index save succeeds. Empty leftover folders are cleaned from Settings.
- Recording: 48 kHz mono PCM, auto-stop ~90s, discard/analyze gate ~0.6s.
- Mimic reference Mac audio capture (Core Audio process tap): system output only (not mic); used only when creating a Mimic reference; same ~90s / 0.6s gates; requires `NSAudioCaptureUsageDescription`.

## Where common work lands

| Task | Start here |
| --- | --- |
| Pitch / pauses / HNR / CPP / spectrogram | `Sources/VoiceCoachCore/Analysis/` |
| Per-word pitch/loudness | `Sources/VoiceCoachCore/Analysis/WordAcousticAnalyzer.swift` |
| JSON export shape | `Sources/VoiceCoachCore/Reports/ReportFormatter.swift` + report tests + SelfTest |
| Apple / Parakeet transcription | `Sources/VoiceCoachCore/Transcription/`, `scripts/setup-transcription.sh` |
| Import normalize to WAV | `Sources/VoiceCoachCore/Audio/AudioImportService.swift` |
| Session models / library projection | `Sources/VoiceCoachSession/Models/` |
| Session persistence / migrations | `Sources/VoiceCoachSession/Persistence/SessionStore.swift` |
| App-wide state and actions | `Sources/VoiceCoachApp/Application/AppModel*.swift` |
| Record / playback platform service | `Sources/VoiceCoachApp/Services/AudioRecorder.swift` |
| Mimic reference Mac audio | `Sources/VoiceCoachApp/Services/SystemAudioCapture.swift`, `Features/Mimic/` |
| Home / Library / Mimics / Take / Settings | `Sources/VoiceCoachApp/Features/` |
| Shell / sidebar / inspectors | `Sources/VoiceCoachApp/Navigation/`, feature inspector files |
| Charts and timelines | `Sources/VoiceCoachApp/Visualization/` |
| Palette / glass / reusable chrome | `Sources/VoiceCoachApp/DesignSystem/` |
| Fixture screenshots | `Sources/VoiceCoachApp/PreviewSupport/RenderPreviews.swift`, `scripts/render-previews.sh` |

## Boundaries

- Do not commit `.build/`, `build/`, or personal WAVs/recordings (see `.gitignore`).
- Do not treat `docs/screenshots/` as live UI truth without regenerating when layout changes.
- Ask before adding dependencies, lowering the macOS deployment target in SPM, or introducing network/cloud analysis.
- Prefer extending SelfTest contracts when changing report keys or acoustic invariants.

## Pointers

- Human-oriented product docs: `README.md`
- Architecture and dependency rules: `docs/architecture/README.md`
- Peekaboo macOS UI QA & automation guide: `docs/PEEKABOO.md`
- Cloud bootstrap: `scripts/cloud-agent-install.sh`
- Official AGENTS.md convention: https://agents.md/
