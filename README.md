# Voice Coach

A local-first macOS voice practice studio for **macOS 26+**. Create sessions, record or import takes, inspect acoustic measurements and on-device transcripts, and keep a private practice library on your Mac.

## Download

Prebuilt app (ad-hoc signed):

**[Voice Coach 3.2.0 for macOS](https://github.com/Gowtham1729/voice-coach/releases/tag/v3.2.0)**

Download `Voice-Coach-3.2.0-macOS.zip`, unzip, and move **Voice Coach.app** to Applications. If Gatekeeper blocks the first launch, right-click the app → **Open**. For word-level transcripts, open **Settings → Transcription** once and download the on-device Parakeet model (~714 MB).

## What you can do

- Create named sessions for general practice, reading a prompt, or free speaking — or jump in with **Quick Record**
- Record takes (Space) or import audio/video; imports are normalized to a local WAV before analysis
- Keep every take in a session, or only the newest one
- Open a take to review word-level transcript chips, pitch / loudness / spectrum plots, and a sticky playback timeline
- Search the full session library, resume from Recents, and scan aggregate trends in Insights
- Copy transcript text, copy an analysis PNG, copy a coach prompt, or export audio + JSON — all on-device

Nothing is uploaded. Recordings, analysis, and transcripts stay under `~/Library/Application Support/VoiceCoach`.

## Screenshots

Fixture layouts of the current studio shell (synthetic audio only — no personal recordings). Offscreen proofs flatten Liquid Glass into opaque materials; the running app on macOS 26+ uses native glass for chrome and controls.

| Studio | Create a session |
| --- | --- |
| ![Studio](docs/screenshots/studio.png) | ![Create a session](docs/screenshots/create-session.png) |

| Session | Take |
| --- | --- |
| ![Session workspace](docs/screenshots/practice.png) | ![Take review](docs/screenshots/take.png) |

| Sessions | Insights |
| --- | --- |
| ![Sessions library](docs/screenshots/sessions.png) | ![Insights](docs/screenshots/insights.png) |

| Settings | Recording |
| --- | --- |
| ![Settings](docs/screenshots/settings.png) | ![Recording](docs/screenshots/recording.png) |

## Studio shell

The app uses a fixed sidebar (**Studio**, **All Sessions**, **Insights**, **Settings**, plus **Recents**), a focused workspace, and a contextual inspector. Primary chrome adopts Liquid Glass on macOS 26+; content panels stay on standard materials. Reduce Transparency falls back to opaque surfaces; Reduce Motion softens page and graph transitions.

On a take: tap a transcript word to seek, scrub the sticky waveform timeline (Space to play/pause), and switch Pitch / Loudness / Spectrum. Soft transcription failures still keep the take and acoustic analysis.

## What it measures

Acoustic coaching signals (not medical measurements — they cannot prove diaphragm use or diagnose a voice condition):

- duration, active speech, and pause ratio
- noise floor, SNR, sample rate, and clipping
- median pitch, pitch range / variation / instability (semitones), and a **24**-value pitch contour
- mean loudness, dynamic range, deviation, phrase-ending decay, and a **24**-value loudness contour
- pause count plus mean, median, and longest pause
- HNR (and related voice-quality estimates used in the UI)
- local NVIDIA Parakeet transcription with word timestamps and per-word pitch / loudness
- waveform and spectrogram in the app UI only (not in exported JSON)

## Run from source

Optional on-device transcription (Apple Silicon): in the app open **Settings → Transcription → Download transcription (~714 MB)**. That installs the NVIDIA NeMo-Speech runtime under Voice Coach’s Application Support folder and pulls Parakeet locally. Acoustic analysis works without it.

Developer alternate (same runtime/model):

```sh
./scripts/setup-transcription.sh
```

Honor a custom binary with `VOICE_COACH_NEMO_SPEECH_PATH` if needed.

```sh
swift run VoiceCoachApp
```

Double-clickable app bundle:

```sh
./scripts/build-app.sh
open "build/Voice Coach.app"
```

Analysis contract suite:

```sh
swift run VoiceCoachSelfTest
```

Layout proofs (eight screens + persistence round-trip, synthetic audio only):

```sh
./scripts/render-previews.sh
```

If macOS reports that the Xcode license is not accepted, run `sudo xcodebuild -license` once in Terminal and accept it yourself.

## Export

From a take’s inspector you can export the recording with `voice-report.json` (expanded report via `ReportFormatter.makeReport`), including transcription and per-word pitch / loudness. Dense acoustic frames, waveform, and spectrogram stay in the app library and are not part of the export. Copied coach prompts and raw JSON use the same on-device analysis.

## Privacy

Microphone access is requested only when you record. Analysis and optional Parakeet transcription run locally. The session index is written atomically; deleting a session removes its recording folder.
