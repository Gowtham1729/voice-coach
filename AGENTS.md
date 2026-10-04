# AGENTS.md

Operating manual for coding agents. Prefer this file over guessing, and prefer `VoiceCoachSelfTest` when a prose doc and a contract disagree. Put one-off task detail in the chat, not here.

## What this repo is

Local-first **Ichido** (formerly Voice Coach): a **macOS 26+** SwiftUI speaking-practice studio (Swift 6.2). Record or import takes, run on-device acoustic analysis and optional transcription, and persist a private library. Not a web app. Recordings are never uploaded.

## Layout

| Area | Path | Notes |
| --- | --- | --- |
| DSP / reports / ASR | `Sources/VoiceCoachCore/` | No SwiftUI, AppKit, or session persistence. Linux-buildable when AVFoundation is absent |
| Session domain / persistence | `Sources/VoiceCoachSession/` | Foundation only. Depends on Core, not on the app |
| App UI / capture | `Sources/VoiceCoachApp/` | macOS only: `App/`, `Application/`, `Navigation/`, `Features/`, `Services/`, `DesignSystem/`, `Visualization/`, `Models/`, `PreviewSupport/` |
| Unit tests | `Tests/VoiceCoachCoreTests/`, `Tests/VoiceCoachSessionTests/` | Swift Testing |
| App coordination tests | `Tests/VoiceCoachAppTests/` | macOS-only save and rejection checks |
| Contract smoke | `Sources/VoiceCoachSelfTest/main.swift` | Acoustic and report invariants. Do not grow this for ordinary unit tests |
| Bundle resources | `Resources/` | Packaged by `scripts/build-app.sh` |
| Marketing site | `website/` | Static. Checks and publish notes: `docs/marketing-website.md` |
| Scripts | `scripts/`, `script/build_and_run.sh` | Use these. Do not invent build steps |

**Naming:** UI “recording”, the retry stack, and Mimic are a `CoachingSession`. A UI “take” is a Core `PracticeSession`. Do not rename those storage types. Visible copy uses **Practice**, **Reference practice**, and **Words**. Before changing user-facing strings, read `docs/brand/messaging.md`.

## Dependency rules

- Dependencies point inward: App → Session → Core. Core never imports App or Session.
- Persisted types live in Session. Acoustic and export types live in Core. Transient selection state lives in App.
- SwiftUI views call `AppModel` actions. They do not write files, launch transcription, or own AVFoundation objects.
- Platform services enter through `AppDependencies` protocols.
- A storage-format or report-JSON change needs a focused regression test in the same change.

## Commands

Run from the repo root. Scripts prefer the Xcode toolchain when it is present.

```sh
./scripts/test.sh --self-test     # DSP + report JSON, after Core/report/transcription changes
./scripts/test.sh                 # Core + Session unit tests
./scripts/test.sh --all           # Same tests CI runs before the app build
./script/build_and_run.sh         # Dev app. Flags: --debug --logs --telemetry --verify
./scripts/build-app.sh            # build/Ichido.app, ad-hoc codesign
./scripts/render-previews.sh      # SelfTest + DEBUG layout PNGs in build/previews
./scripts/setup-transcription.sh  # Optional local ASR (~714 MB). Not in CI or cloud unless asked
```

- Cloud and Linux agents (`.cursor/environment.json` runs `scripts/cloud-agent-install.sh`) build **only** `VoiceCoachSelfTest`. Do not build or run `VoiceCoachApp` there.
- AVFoundation builds need `--disable-sandbox` (already set in `build-app.sh` and `render-previews.sh`).
- ASR override: `VOICE_COACH_NEMO_SPEECH_PATH`.
- DEBUG layouts: `VoiceCoachApp --render-previews <dir>`.
- Optional SelfTest helpers, with `--self-test`: `--transcribe`, `--timeline`, `--inspect-pitch`, `--dump-sample-report`.
- If macOS blocks on an unaccepted Xcode license, the human runs `sudo xcodebuild -license`. Agents cannot accept it.

## Verification

| Change | Check |
| --- | --- |
| Core or report shape | `./scripts/test.sh --all` |
| Insight selection or progress | `./scripts/test.sh --all`, then Take and Mimic Compare previews |
| Session or persistence | `./scripts/test.sh` plus a focused persistence test |
| App UI or layout | `./scripts/render-previews.sh` on macOS. If you cannot run it, say the UI was not visually verified |
| Live Mac UI | `docs/PEEKABOO.md` after a local build. Not a CI job |
| Website | `docs/marketing-website.md` |
| Release | `docs/RELEASE.md` |

Synthetic tests do not prove microphone, headphone, system-audio, or route behavior.

## Product constraints

- **Local-first:** No recording-upload path. Update checks and optional model downloads may use the network. Do not shorten privacy copy to “never uses the internet.”
- **Not medical:** HNR and CPP are acoustic coaching signals. Do not diagnose, claim diaphragm proof, grade accents, or certify fluency. Report JSON must not contain `baseline`, `throat`, or `please`.
- **Platform:** `Package.swift` and `Resources/Info.plist` target **macOS 26**. Do not lower that without an explicit product decision.
- **Materials:** System chrome may use Liquid Glass (`.glass`, `.glassProminent`, `ControlGlass`). Content panels stay on `.desktopPanel` / `.studioCard` (regularMaterial). Honor Reduce Transparency and Reduce Motion through `Studio` / `StudioMotion`.
- **Save gate:** Missing, empty, or near-silent audio fails before save, as does successful transcription with no recognized text or words. Rejected captures leave no library entry and no temporary audio. A missing `nemo-speech` binary is soft: valid audio still saves, with a notice.
- **Identity:** The visible name is Ichido. Keep bundle id `com.gowtham.voicecoach`, `Application Support/VoiceCoach`, preference keys, and the Swift target names.

## Report contracts

- The in-app export uses `ReportFormatter.makeReport`. `makeCompactReport` exists for older contract tests and is not a UI control.
- JSON contours are 24 values: `contour_semitones` and `contour_relative_db`.
- `cppDB` is computed and must stay out of report JSON. `cpp_db` is forbidden. Voice quality exports as `hnr_db`.
- Dense `acousticFrames`, waveform, and spectrogram stay in the per-take analysis file, not the exported report.
- Word metrics come from `AcousticFrameData` via `WordAcousticAnalyzer`, not from the downsampled contours.

## Persistence

Root: `~/Library/Application Support/VoiceCoach/`

- `session-library.json` is schemaVersion **3**, a thin index of session metadata and take stubs. Versions 1–2 migrate on load. One backup file is kept per old version.
- `Sessions/<sessionUUID>/take-<takeUUID>.analysis.json` holds the `AnalysisResult` plus transcript and words, including a Mimic reference.
- Audio is `take-<takeUUID>.wav` or `…-imported.wav`. Mimic reference audio is `reference.wav`.
- Renames and Mimic style edits rewrite the thin index only. A new or changed take also writes its analysis file.
- `keepsRecordings == false` replaces prior takes and deletes their WAV and analysis files after a successful save. New recordings keep every valid take. A legacy replace-only folder prompts before the next save.
- Deleting a Mimic removes its folder. Deleting a recording removes that take’s audio and analysis after the index save succeeds. Settings cleans empty leftover folders.
- Captures are 48 kHz mono PCM, auto-stop around 90s, with a discard/analyze gate around 0.6s.
- Mimic reference capture is system output only (Core Audio process tap), uses the same gates, and requires `NSAudioCaptureUsageDescription`.

## Visual reference

`docs/screenshots/` is the committed picture of the app: home, library, practice, mimic practice, compare, analysis, take, settings, new mimic, and recording. Read those images before asking the user to describe a screen or launching the app. Refresh a capture when that screen’s layout changes. `build/previews` is synthetic layout output and stays gitignored.

## Boundaries

- Do not commit `.build/`, `build/`, or personal recordings. Keep `docs/screenshots/` as the visual reference.
- Ask before adding a dependency, lowering the deployment target, or adding network or cloud analysis.
- When a report key or acoustic invariant changes, extend SelfTest in the same change.
