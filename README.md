# Voice Coach

A private voice practice studio for macOS. Record a take, see two measured practice targets, and refine your delivery on an interactive timeline without uploading audio to the cloud.

Built natively with SwiftUI for macOS 26+.

## Demo

https://github.com/user-attachments/assets/32e156b7-0485-4435-9262-570c739e3e4e

## Installation

Download the latest pre-built application:
* **[Voice Coach 3.3.2 for macOS](https://github.com/Gowtham1729/voice-coach/releases/tag/v3.3.2)** (Universal ZIP)

### Setup Steps
1. Unzip the downloaded file and move `Voice Coach.app` to your `/Applications` folder.
2. Launch the app. Because releases are currently ad-hoc signed, macOS Gatekeeper may prompt you on first run. If blocked, right-click `Voice Coach.app` in Finder and select **Open**.

**System Requirements:** macOS 26.0 or later (Apple Silicon recommended).

**Speech Transcription:**
Apple on-device speech transcription is enabled by default. If you prefer high-accuracy offline transcription with detailed word timings, an optional Parakeet model (~714 MB) can be installed inside the app under **Settings > Transcription**, or via `./scripts/setup-transcription.sh`.

## How It Works

Voice Coach focuses on deliberate practice through a rapid loop: capture a take, review two concrete signals, and adjust on the next attempt.

### 1. Three Ways to Practice
* **Microphone**: Record rehearsed talks, pitches, presentations, or interview answers.
* **Mac System Audio**: Capture audio playing directly from your Mac (talks, podcasts, or browser clips) without complex virtual audio cables.
* **File Import**: Bring in existing audio or video files. Imported media is automatically normalized to 48 kHz mono WAV locally.

### 2. Two Concrete Practice Targets
Instead of arbitrary scores, Voice Coach isolates two specific acoustic targets for your next attempt:
* **Pacing and Pauses**: Visualizes phrase duration, speaking cadence, and silence gaps, helping you place deliberate pauses between key ideas.
* **Pitch and Emphasis**: Highlights pitch contours across 24 checkpoints to help you sustain vocal energy or add intentional inflection to key words.

### 3. Mimic Mode (Practice with a Reference)
Mimic mode lets you study how another speaker delivers a phrase:
1. **Listen**: Set an imported file or captured system audio as your reference model.
2. **Imitate**: Record your attempt right alongside it.
3. **Compare**: Inspect side-by-side pitch curves, rhythm alignments, and word-level emphasis to hear where your delivery differs.

### 4. Stacked Takes and Timeline Scrubbing
All attempts in a session stay grouped together (`Take 1`, `Take 2`, etc.). You can scrub the waveform, click any transcribed word to jump playback directly to that moment, and hear your improvement from one take to the next.

### 5. Optional AI Analysis (Clipboard Export)
If you want qualitative script feedback or presentation advice, use **File > Copy AI analysis prompt + JSON** (or press `⌥⌘C`). This formats your acoustic metrics into a structured prompt on your clipboard so you can paste it into ChatGPT, Gemini, Claude, or any LLM of your choice. Voice Coach never contacts external AI APIs on its own.

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
