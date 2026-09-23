# Voice Coach

Practice your voice on this Mac — record, Mimic a reference, and get a clear next step. Local-first for **macOS 26+**. Nothing is uploaded.

For speakers who practice on their Mac — talks, pitches, interviews — and want one clear next step without uploading audio.

## Demo

https://github.com/user-attachments/assets/32e156b7-0485-4435-9262-570c739e3e4e

[Download the ~1 min tour](https://github.com/Gowtham1729/voice-coach/releases/download/demo-readme/voice-coach-tour.mp4) — Home → Take → Mimic → Library.

## Download

**[Voice Coach 3.3.2 for macOS](https://github.com/Gowtham1729/voice-coach/releases/tag/v3.3.2)** — zip, move to Applications. If Gatekeeper blocks: right-click → **Open**.

Try the tour above, then install — same local-first app, no signup.

Apple on-device transcription is default. Optional Parakeet (~714 MB) under **Settings → Transcription**.

> Tagged releases are built by GitHub Actions (`v*` tags). See [`docs/RELEASE.md`](docs/RELEASE.md).

## Features

The loop: Take → two practice targets → retry and compare.

| Area | What you get |
| --- | --- |
| **Home** | One-tap **Record**, import audio/video (normalized to local WAV), Recents |
| **Takes** | Stacked retries (Take 1, Take 2, …), sticky timeline, transcript word seek |
| **Practice next** | Two measured practice targets after the metrics; Mimic uses reliable reference timing, pitch, and word emphasis |
| **Mimic** | Reference from file or Mac audio → listen, imitate, compare, retry |
| **Library** | Flat catalog of recordings — no folder picking |
| **Export / AI analysis** | Export audio + JSON; **Copy AI analysis prompt + JSON** under inspector **More** or **File** (⌥⌘C) copies instructions and the selected take's JSON to paste into ChatGPT, Gemini, or another AI chat |

All analysis and transcription stay on-device under `~/Library/Application Support/VoiceCoach`.

Recordings, analysis, and transcripts stay on this Mac — no account, no upload, no cloud processing.
The optional AI analysis action copies text to the clipboard; you choose whether to paste it into another service.

## How Practice next works

Each take shows two observations with an action to try next. Ordinary recordings use measured pacing, pitch, and recording quality without treating normal variation as a defect. Mimic first checks phrase duration and word spacing, then repeated pitch or emphasis differences across reliable matched words. A broad pattern uses a specific word as a replay checkpoint; when no repeated pattern is supported, a single word can be the target. These thresholds prioritize practice and do not rate a voice against a universal ideal. When alignment or quality is poor, the app says so and uses take-only targets. Change since a comparable earlier take is computed from retained takes, so deleting a take updates the comparison. Apple Intelligence may rephrase the two exercises locally; measured facts and target selection do not depend on it.

## Privacy

- Microphone access is requested only when you record
- Analysis and optional Parakeet transcription run locally
- The library index is written atomically
- Deleting a recording removes its audio and analysis; deleting a Mimic removes its reference and attempts

## What it measures

Acoustic coaching signals — **not** medical measurements.

- Pauses, pitch range, loudness, and phrase-end energy
- Noise / SNR / clipping (recording hygiene)
- On-device transcript with word timing when available

## Develop from source

Requires macOS 26+ and Xcode 26.x (CI pins **Xcode 26.6**).

```sh
./script/build_and_run.sh
```

Builds, ad-hoc signs, and launches the app. Useful flags: `--debug`, `--logs`, `--telemetry`, `--verify`.

```sh
./scripts/build-app.sh          # app bundle only → build/Voice Coach.app
./scripts/test.sh               # unit tests
./scripts/test.sh --all         # units + self-test (same soft gate as CI)
./scripts/render-previews.sh    # synthetic layout proofs (local; not CI)
```

Optional Parakeet setup (Apple Silicon):

```sh
./scripts/setup-transcription.sh
```

Or download from **Settings → Transcription** in the app. Override the binary with `VOICE_COACH_NEMO_SPEECH_PATH` if needed.

If macOS reports the Xcode license is not accepted, run `sudo xcodebuild -license` once and accept it.

### Package layout

| Target | Role |
| --- | --- |
| `VoiceCoachCore` | Analysis, transcription, metrics, coach observation |
| `VoiceCoachSession` | Session domain and persistence |
| `VoiceCoachApp` | macOS UI and platform services |

See [`docs/architecture/README.md`](docs/architecture/README.md) before adding a cross-cutting feature.

## Releases

1. Bump both `Info.plist` version keys in a PR; wait for green CI `test`.
2. Merge, then push an annotated `vX.Y.Z` tag.
3. The **Release** workflow builds the zip and attaches it to the GitHub Release.

Details: [`docs/RELEASE.md`](docs/RELEASE.md).

## License

See repository license / release notes for distribution terms of prebuilt zips.
