# Voice Coach

A private voice practice studio for macOS. Record a take, review its measured delivery, and refine it on an interactive timeline without uploading audio to the cloud. Mimic adds practice targets measured against a reference.

Built natively with SwiftUI for macOS 26+.

## Demo

https://github.com/user-attachments/assets/32e156b7-0485-4435-9262-570c739e3e4e

## Installation

Download the latest pre-built application:
* **[Latest Voice Coach for macOS](https://github.com/Gowtham1729/voice-coach/releases/latest/download/Voice-Coach-macOS.zip)** (ZIP) · [Release notes](https://github.com/Gowtham1729/voice-coach/releases/latest)

### Setup Steps
1. Unzip the downloaded file and move `Voice Coach.app` to your `/Applications` folder.
2. Launch the app. Because releases are currently ad-hoc signed, macOS Gatekeeper may prompt you on first run. If blocked, right-click `Voice Coach.app` in Finder and select **Open**.

Version 3.3.4 introduced in-app update checks. If you already have 3.3.4 or newer installed, use **Voice Coach > Check for Updates…** or wait for an automatic update check to receive new releases. Older releases need one manual installation of an updater-enabled version.

**System Requirements:** macOS 26.0 or later (Apple Silicon recommended).

**Speech Transcription:**
Apple on-device speech transcription is enabled by default. Choose the spoken language in **Settings > Transcription**, then use **Download Language…** if its Apple model is missing. This does not change your Mac’s language. New sessions retain their speech language for subsequent takes. Existing transcripts can be regenerated using **Re-transcribe** on a take or **Transcript > Re-transcribe** on a Mimic reference.

Parakeet is an optional local model (~714 MB), installable from the same settings pane or via `./scripts/setup-transcription.sh`. The bundled v3 model automatically recognizes 25 European languages, including French, but does not support Japanese. Its language control shows **Automatic**; Apple’s saved language preference does not steer it. Known unsupported session languages are rejected before transcription. Voice Coach uses the selected engine and reports failures without silently switching models. Audio analysis and saving still work when transcription is unavailable.

## How It Works

Voice Coach focuses on deliberate practice through a rapid loop: capture a take, review the recording, and adjust on the next attempt. Mimic names differences from a reference.

### 1. Three Ways to Practice
* **Microphone**: Record rehearsed talks, pitches, presentations, or interview answers.
* **Mac System Audio**: Capture audio playing directly from your Mac (talks, podcasts, or browser clips) without complex virtual audio cables.
* **File Import**: Bring in existing audio or video files. Imported media is automatically normalized to 48 kHz mono WAV locally.

### 2. Review a Recording
A free recording shows measured pauses, pitch, loudness, and clarity on the timeline. It does not assign practice exercises. A clipped or noisy take includes a short note that those estimates may be unreliable.

### 3. Mimic Mode (Practice with a Reference)
Mimic mode lets you study how another speaker delivers a phrase:
1. **Listen**: Set an imported file or captured system audio as your reference model.
2. **Imitate**: Record your attempt right alongside it.
3. **Compare**: Inspect side-by-side pitch curves, rhythm alignments, and word-level emphasis. When the words line up, two practice targets name a difference from the reference.

### 4. Stacked Takes and Timeline Scrubbing
All attempts in a session stay grouped together (`Take 1`, `Take 2`, etc.). You can scrub the waveform, click any transcribed word to jump playback directly to that moment, and hear your improvement from one take to the next.

### 5. Optional AI Analysis (Clipboard Export)
If you want qualitative script feedback or presentation advice, use **File > Copy AI analysis prompt + JSON** (or press `⌥⌘C`). This formats your acoustic metrics into a structured prompt on your clipboard so you can paste it into ChatGPT, Gemini, Claude, or any LLM of your choice. Voice Coach never contacts external AI APIs on its own.

### 6. Experimental On-Device Chat
Enable **Settings > Experiments > Enable experimental features**, open a recording or Mimic, and choose **Ask** in the inspector. Explore meanings, grammar concepts, translations, synonyms, or word-by-word explanations. Suggested questions fill the composer so you can edit them before sending. Replies preserve lists and follow-ups, with Copy for the complete answer.

Choose **Reference** or **This take** from the compact context menu. Mimics start with the reference transcript. Chat uses the complete chosen transcript, without sentence selection or repeated transcript previews. **Translate…** opens a native sheet backed by Apple’s on-device `TranslationSession`, which can ask to download language models.

Chat uses Apple's on-device model and requires available Apple Intelligence. Each recording or selected Mimic attempt has a separate temporary conversation. Chats survive navigation while the app is open, but clear when you quit, clear the chat, delete the recording, or turn experiments off. Follow-ups use up to three recent exchanges. Only the complete chosen transcript and recent conversation are sent to the local model. Transcripts are not silently shortened; very long transcripts may exceed the local model’s context limit.

This chat is for language exploration. It does not evaluate takes or recommend performance improvements. Common coaching requests are rejected before inference, with model instructions and a conservative reply check as additional defenses. These checks are not a semantic guarantee. Transcription errors and incorrect language answers remain possible; the chat cannot hear audio, search the web, or verify facts. Original transcripts and measured practice targets are preserved.

## What It Measures

Voice Coach extracts objective acoustic properties to guide practice. It does not provide medical evaluations, diagnose speech conditions, or rate accents.

* **Pauses and Cadence**: Pause counts, average duration, speaking rate, and pause placement between clauses.
* **Pitch Dynamics**: Pitch range in semitones, fundamental frequency (F0) contours, and phrase-ending inflection.
* **Vocal Energy**: Loudness dynamics and phrase-ending energy drop-offs.
* **Recording Quality**: Harmonics-to-Noise Ratio (HNR), Signal-to-Noise Ratio (SNR), and clipping alerts.
* **Word Alignment**: Synchronized word timestamps when on-device transcription is available.

## Privacy by Design

Voice Coach runs entirely on your Mac. It requires no user account, collects no telemetry, and makes no network requests.

* **Local Storage**: All recordings, transcripts, and acoustic metrics live exclusively in:
  ```
  ~/Library/Application Support/VoiceCoach/
  ```
* **Explicit Permissions**: Microphone access is requested only when you click record. System audio capture access is requested only when capturing Mac output.
* **Clean Deletion**: Deleting a take or session permanently purges the underlying WAV and analysis files from disk.
* **Zero Network Traffic**: Audio analysis and speech transcription execute on-device using local machine learning and Core Audio DSP.

## Development

### Prerequisites
* macOS 26.0+
* Xcode 26.x (CI builds on Xcode 26.6)
* Swift 6.2

### Quick Start
To build, ad-hoc sign, and launch the app in development mode:
```sh
./script/build_and_run.sh
```

Supported runner flags: `--debug`, `--logs`, `--telemetry`, `--verify`.

### Testing and Building
```sh
# Run fast contract and acoustic verification suite
./scripts/test.sh --self-test

# Run unit tests (Core DSP and Session persistence)
./scripts/test.sh

# Run full test suite (same gate as CI)
./scripts/test.sh --all

# Optional real on-device chat smoke (synthetic text; Apple Intelligence must be ready)
VOICE_COACH_TEST_LOCAL_CHAT=1 ./scripts/test.sh --unit --filter liveDeviceModelSmoke

# Build release application bundle (outputs to build/Voice Coach.app)
./scripts/build-app.sh

# Render synthetic UI layout proofs
./scripts/render-previews.sh

# Download and configure offline Parakeet ASR model (Apple Silicon)
./scripts/setup-transcription.sh
```

If macOS indicates the Xcode license has not been accepted, run `sudo xcodebuild -license` in your terminal.

### Architecture

The project is structured into three primary packages:

| Target | Description |
| --- | --- |
| `VoiceCoachCore` | Signal processing, acoustic analysis, metric extraction, and transcription interfaces. |
| `VoiceCoachSession` | Session data structures, SQLite/JSON persistence layer, and schema migrations. |
| `VoiceCoachApp` | macOS SwiftUI interface, Core Audio capture engine, and interactive timeline components. |
| `VoiceCoachSelfTest` | Automated smoke and contract suite enforcing acoustic invariants and report schemas. |

For architectural boundaries and design principles, see [`docs/architecture/README.md`](docs/architecture/README.md).

## Releases

Tagged releases (`v*`) are built and verified automatically by GitHub Actions. For the release process and checklist, see [`docs/RELEASE.md`](docs/RELEASE.md).

## License

See release notes and repository terms for distribution details.
