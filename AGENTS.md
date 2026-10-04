# AGENTS.md

Operating manual for coding agents. Prefer this file over guessing, and prefer `VoiceCoachSelfTest` when a prose doc and a contract disagree. Put one-off task detail in the chat, not here.

## What this repo is

Local-first **Ichido** (formerly Voice Coach): a **macOS 26+** SwiftUI speaking-practice studio (Swift 6.2). Record or import takes, run on-device acoustic analysis and optional transcription, and persist a private library. Not a web app. Recordings are never uploaded.

## Layout

| Area | Path | Notes |
| --- | --- | --- |
| DSP / reports / ASR | `Sources/VoiceCoachCore/` | No SwiftUI, AppKit, or session persistence. Linux-buildable when AVFoundation is absent |
| Session domain / persistence | `Sources/VoiceCoachSession/` | Foundation only. Depends on Core, not on the app |
| App UI / capture | `Sources/VoiceCoachApp/` | macOS only: `App/`, `Application/`, `Navigation/`, `Features/`, `Services/`, `Support/`, `DesignSystem/`, `Visualization/`, `Models/`, `PreviewSupport/` |
| Unit tests | `Tests/VoiceCoachCoreTests/`, `Tests/VoiceCoachSessionTests/` | Swift Testing |
| App coordination tests | `Tests/VoiceCoachAppTests/` | macOS-only save and rejection checks |
| Contract smoke | `Sources/VoiceCoachSelfTest/main.swift` | Acoustic and report invariants. Do not grow this for ordinary unit tests |
| Bundle resources | `Resources/` | Packaged by `scripts/build-app.sh` |
| Marketing site | `website/` | Static. Change a required sentence in `website/index.html` and `scripts/check-website.mjs` together. See `docs/marketing-website.md` |
| Scripts | `scripts/`, `script/build_and_run.sh` | Use these. Do not invent build steps |

**Naming:** UI “recording”, the retry stack, and Mimic are a `CoachingSession`. A UI “take” is a Core `PracticeSession`. Do not rename those storage types. Visible copy uses **Practice**, **Reference practice**, and **Words**. Reference-practice modes stay **Listen & Repeat** and **Speak Along**. Before changing user-facing strings, read `docs/brand/messaging.md`.

## Dependency rules

- Dependencies point inward: App → Session → Core. Core never imports App or Session.
- Persisted types live in Session. Acoustic and export types live in Core. Transient selection state lives in App.
- SwiftUI views call `AppModel` actions. They do not write files, launch transcription, or own AVFoundation objects.
- Platform services enter through `AppDependencies` protocols.
- A storage-format or report-JSON change needs a focused regression test in the same change. When a report key or acoustic invariant changes, extend SelfTest in that same change.

## Commands

Run from the repo root. Scripts prefer the Xcode toolchain when it is present.

```sh
./scripts/test.sh --self-test     # DSP + report JSON, after Core/report/transcription changes
./scripts/test.sh                 # Core + Session unit tests
./scripts/test.sh --all           # What CI job `test` runs before `build-app.sh`
./script/build_and_run.sh         # Dev app. Flags: --debug --logs --telemetry --verify
./scripts/build-app.sh            # build/Ichido.app, ad-hoc codesign
./scripts/render-previews.sh      # SelfTest + DEBUG layout PNGs in build/previews
./scripts/setup-transcription.sh  # Optional local ASR (~714 MB). Not in CI or cloud unless asked
```

- Cloud and Linux agents (`.cursor/environment.json` runs `scripts/cloud-agent-install.sh`) build **only** `VoiceCoachSelfTest`. Do not build or run `VoiceCoachApp` there.
- AVFoundation builds need `--disable-sandbox` (already set in `build-app.sh` and `render-previews.sh`).
- ASR override: `VOICE_COACH_NEMO_SPEECH_PATH`.
- If macOS blocks on an unaccepted Xcode license, the human runs `sudo xcodebuild -license`. Agents cannot accept it.
- Optional Words chat smoke, only when asked and Apple Intelligence is ready. Not part of CI: `VOICE_COACH_TEST_LOCAL_CHAT=1 ./scripts/test.sh --unit --filter liveDeviceModelSmoke`.

## Verification

| Change | Check |
| --- | --- |
| Core or report shape | `./scripts/test.sh --all` |
| Insight selection or progress | `./scripts/test.sh --all`, then Take and Mimic Compare previews |
| Session or persistence | `./scripts/test.sh` plus a focused persistence test |
| App UI or layout | `./scripts/render-previews.sh` on macOS. If you cannot run it, say the UI was not visually verified |
| Live Mac UI | `docs/PEEKABOO.md` after a local build. Not a CI job |
| Website | `node scripts/check-website.mjs`. Not part of CI job `test`. See `docs/marketing-website.md` |
| Release | `docs/RELEASE.md` |

Synthetic tests do not prove microphone, headphone, system-audio, or route behavior. Smoke-test those on a Mac when audio routing changes.

## Product constraints

- **Local-first:** No recording-upload path. Update checks and optional model downloads may use the network. The privacy line is “No account. No recording uploads. No analytics.” followed by that network sentence. Do not shorten it to “never uses the internet.”
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
- A Mimic session always keeps `reference.wav` and every attempt. The replace path must not run when `mode == .mimic`. Deleting an attempt deletes that take only, not the reference.
- Deleting a Mimic removes its folder. Deleting a recording removes that take’s audio and analysis after the index save succeeds. Settings cleans empty leftover folders.
- Captures are 48 kHz mono PCM, auto-stop around 90s, with a discard/analyze gate around 0.6s.
- Mimic reference sources are import, Mac system-audio capture, and **Practise with this clip**. Reference capture is system output only (Core Audio process tap), uses the same gates, and requires `NSAudioCaptureUsageDescription`. In-app reference capture is shipping.
- **Listen & Repeat** plays the reference, then records. **Speak Along** plays the reference while the microphone records. `beginRecording` must not stop that reference playback.

## Visual reference

`docs/screenshots/` is the committed layout reference. Open the matching PNG before asking what a screen looks like. These are real captures of Ichido 0.0.3. Historical filenames containing `mimic` are kept so existing links work. If a label disagrees with the code or `docs/brand/messaging.md`, follow those. Refresh a capture when that screen’s layout or labels change. `build/previews` is synthetic and stays gitignored.

| File | Screen |
| --- | --- |
| `01-home.png` | Home |
| `02-library.png` | Library |
| `03-mimics.png` | Practice list |
| `04-mimic-practice.png` | Reference practice |
| `05-mimic-compare.png` | Compare |
| `06-mimic-analysis.png` | Analysis |
| `07-take.png` | Take |
| `08-settings.png` | Settings |
| `08b-settings-transcription.png` | Settings → Transcription |
| `08c-settings-experiments.png` | Settings → Experiments |
| `08d-settings-library.png` | Settings → Library |
| `09-new-mimic.png` | New reference practice |
| `10-recording.png` | Recording |
| `11-words.png` | Words |

## Boundaries

- Do not commit `.build/`, `build/`, or personal recordings. Keep `docs/screenshots/`.
- Ask before adding a dependency, lowering the deployment target, or adding network or cloud analysis.
