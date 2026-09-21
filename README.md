# Voice Coach

Local-first **macOS 26+** voice practice studio. Record or import on this Mac, review acoustic metrics and on-device transcripts, practice against a Mimic reference, and keep a private library — nothing is uploaded.

## Download

Prebuilt app (ad-hoc signed, not notarized):

**[Voice Coach 3.2.0 for macOS](https://github.com/Gowtham1729/voice-coach/releases/tag/v3.2.0)**

1. Download `Voice-Coach-3.2.0-macOS.zip` and unzip.
2. Move **Voice Coach.app** to Applications.
3. If Gatekeeper blocks the first launch: right-click → **Open**.

Apple on-device transcription is the default. Optional NVIDIA Parakeet (~714 MB) can be installed later under **Settings → Transcription**.

> Tagged releases are built by GitHub Actions (`v*` tags). See [`docs/RELEASE.md`](docs/RELEASE.md).

## Demo

A short product tour will land here once QA hands it over. Until then, build from source or use the release zip above.

<!-- Demo video: attach when available (do not commit large binaries to git; prefer a release asset or external host link). -->

## Features

| Area | What you get |
| --- | --- |
| **Home** | One-tap **Record**, import audio/video (normalized to local WAV), Recents |
| **Takes** | Stacked retries (Take 1, Take 2, …), sticky timeline, transcript word seek |
| **Insights** | Plain-language observation when pauses or pitch stand out, plus quieter metrics underneath |
| **Mimic** | Reference from file or Mac audio → listen, imitate, compare, retry |
| **Library** | Flat catalog of recordings — no folder picking |
| **Export / coach notes** | Export audio + JSON; copy coach notes from the inspector **More** menu |

All analysis and transcription stay on-device under `~/Library/Application Support/VoiceCoach`.

## Studio layout

Fixed sidebar (**Home**, **Library**, **Mimics**, **Settings**, plus **Recents**), focused workspace, and a contextual inspector. Liquid Glass chrome on macOS 26+; Reduce Transparency / Reduce Motion respected.

On a take: scrub the waveform (Space play/pause), jump via transcript chips, switch Pitch / Loudness / Spectrum. Soft transcription failures still keep the recording and acoustic analysis.

## What it measures

Acoustic coaching signals — **not** medical measurements. They cannot prove diaphragm use or diagnose a voice condition.

- Duration, active speech, pause counts and timing (mean / median / longest)
- Noise floor, SNR, sample rate, clipping
- Pitch (median, range in semitones, variation / instability) and loudness (mean, dynamic range, phrase-end decay)
- Contours for pitch and loudness (UI), plus HNR / related voice-quality estimates
- On-device transcript with word timestamps and per-word pitch / loudness when available
- Waveform and spectrogram in the app only (not in exported JSON)

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

## Export

From a take’s inspector you can export the recording with `voice-report.json` (expanded report via `ReportFormatter.makeReport`), including transcription and per-word pitch / loudness when present. Dense acoustic frames, waveform, and spectrogram stay in the local library and are not part of the export.

## Releases

1. Bump both `Info.plist` version keys in a PR; wait for green CI `test`.
2. Merge, then push an annotated `vX.Y.Z` tag.
3. The **Release** workflow builds the zip and attaches it to the GitHub Release.

Details: [`docs/RELEASE.md`](docs/RELEASE.md).

## License

See repository license / release notes for distribution terms of prebuilt zips.
