# Voice Coach

A small, local-first macOS voice practice app. Record a short sample, receive acoustic measurements immediately, and copy clean structured data for an AI model.

## What it measures

- duration, active speech, and pause ratio
- recording noise floor, SNR, sample rate, and clipping percentage
- median pitch, pitch range, pitch variation, and frame-to-frame pitch instability
- pitch range/deviation in semitones and a 12-value normalized pitch contour
- mean loudness, dynamic range, deviation, and phrase-ending loudness decay
- pause count plus mean, median, and longest pause durations
- HNR and cepstral peak prominence estimates
- a 12-value relative loudness contour
- waveform, pitch/loudness graphs, and spectrogram in the app UI only
- local NVIDIA Parakeet transcription with word start/end timestamps
- timestamp-aligned pitch and loudness measurements for each recognized word

These are acoustic coaching signals, not medical measurements. They cannot prove diaphragm use or diagnose a voice condition.

## Run during development

Install the native local transcription runtime and download Parakeet once:

```sh
./scripts/setup-transcription.sh
```

This uses NVIDIA's official NeMo-Speech.cpp Metal runtime on Apple Silicon and
downloads `nvidia/parakeet-tdt-0.6b-v3` to the NeMo Speech model cache. The
one-time setup needs an internet connection; transcription itself is local and
does not send recordings to a cloud service. The model is roughly 714 MB in its
Q8 GGUF form. Voice Coach also honors `VOICE_COACH_NEMO_SPEECH_PATH` when the
runtime is installed in a custom location.

Then run the app:

```sh
swift run VoiceCoachApp
```

## Build a double-clickable Mac app

```sh
./scripts/build-app.sh
open "build/Voice Coach.app"
```

The exported session contains `recording.wav` and `voice-report.json`. In the app you can copy either the original compact six-section V1 JSON or the expanded report, which preserves those six sections and adds `transcription` and `words`. Each word contains its timestamps plus aligned pitch/loudness summaries. Dense acoustic frames, waveform data, and spectrogram data are not exported. The first recording asks for microphone access. Recordings are stored in the app's Application Support folder and are never uploaded automatically.

If macOS reports that the Xcode license has not been accepted, open Terminal once and run `sudo xcodebuild -license`, review it, and accept it yourself.

## Analysis self-test

```sh
swift run VoiceCoachSelfTest
```

## Version 2 studio

The interface uses an ink-and-mint palette, a voice-reactive line sculpture, a focused recording stage, and a compact analysis workspace. Record with Space, listen back with the Listen/Stop control, switch between pitch, loudness and spectrum, and expand or copy the structured report. The transcript includes word timestamps; selecting a word highlights its time region across the pitch, loudness, spectrum, and waveform views. The waveform remains visible with every chart. The previous successful take stays available if a subsequent recording fails.

On macOS 26 and later, controls use SwiftUI's real `glassEffect` material. macOS 14–15 use a material fallback. Reduce Transparency replaces glass with an opaque surface; Reduce Motion freezes the sculpture and removes the recording transition. The sculpture is decorative, reacts to microphone level only while recording, and does not imply a voice-quality score. A matching app icon is included.

The content/control separation follows [Apple's Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) and [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/).

### Visual checks

```sh
./scripts/render-previews.sh
```

This runs the acoustic/report self-test, checks busy-state recording guards, and generates eleven layout proofs in `build/previews` using synthetic audio only. Preview mode is debug-only and never opens the microphone or reads personal recordings. The offscreen renderer flattens native scrolling and glass into opaque layout representations; these images verify content, spacing and chart states, not live glass refraction, window scrolling or microphone/playback behavior. The shipped app uses native scrolling and Liquid Glass.

For an interactive check, open `build/Voice Coach.app`, record a 10–30 second sample, stop and listen back, switch all three chart views, copy/expand JSON, and export the WAV/report pair. Verify keyboard focus, resizing and the macOS accessibility appearance settings. A live microphone/playback and glass-compositing check remains necessary on the running app.
