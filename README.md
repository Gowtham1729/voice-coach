# Voice Coach

Practice your voice on this Mac — record, Mimic a reference, and get a clear next step. Local-first for **macOS 26+**. Nothing is uploaded.

## Download

**[Voice Coach 3.2.0 for macOS](https://github.com/Gowtham1729/voice-coach/releases/tag/v3.2.0)** — zip, move to Applications. If Gatekeeper blocks: right-click → **Open**.

Apple on-device transcription is default. Optional Parakeet (~714 MB) under **Settings → Transcription**.

> Tagged releases are built by GitHub Actions (`v*` tags). See [`docs/RELEASE.md`](docs/RELEASE.md).

## Demo

[~1 min tour](https://github.com/Gowtham1729/voice-coach/releases/download/demo-readme/voice-coach-tour.mp4) — Home → Take → Mimic → Library.

<video src="https://github.com/Gowtham1729/voice-coach/releases/download/demo-readme/voice-coach-tour.mp4" controls width="720"></video>

## Features

| Area | What you get |
| --- | --- |
| **Home** | One-tap **Record**, import audio/video (normalized to local WAV), Recents |
| **Takes** | Stacked retries (Take 1, Take 2, …), sticky timeline, transcript word seek |
| **Insights** | One plain next-step when pauses or pitch stand out — metrics stay quieter underneath |
| **Mimic** | Reference from file or Mac audio → listen, imitate, compare, retry |
| **Library** | Flat catalog of recordings — no folder picking |
| **Export / coach notes** | Export audio + JSON; coach notes live under inspector **More** |

All analysis and transcription stay on-device under `~/Library/Application Support/VoiceCoach`.

## What it measures

Acoustic coaching signals — **not** medical measurements.

- Pauses, pitch range, loudness, and phrase-end energy
- Noise / SNR / clipping (recording hygiene)
- On-device transcript with word timing when available

## Privacy

- Microphone access is requested only when you record
- Analysis and optional Parakeet transcription run locally
- The library index is written atomically
- Deleting a recording removes its audio and analysis; deleting a Mimic removes its reference and attempts

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
