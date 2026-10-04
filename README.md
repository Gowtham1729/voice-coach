# Ichido

**Your private speaking room.** Record yourself, practise with a reference, and explore the words behind a phrase. Audio, transcripts, and analysis stay on your Mac.

Ichido is the new name for Voice Coach. The app identifier, preferences, and existing local library are preserved. Japanese *ichido* means one time; its practice story is inspired by *mō ichido*, once more.

Built natively with SwiftUI for macOS 26+.

## Installation

Download the latest pre-built application:
* **[Latest Ichido for macOS](https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip)** (ZIP) · [Release notes](https://github.com/Gowtham1729/voice-coach/releases/latest)

### Setup Steps
1. Unzip the downloaded file and move `Ichido.app` to your `/Applications` folder. Replace the earlier Voice Coach app if installed; the local library is retained.
2. Launch the app. Because releases are currently ad-hoc signed, macOS Gatekeeper may prompt you on first run. If blocked, follow [Apple’s opening guidance](https://support.apple.com/en-us/102445) and review the approval in **System Settings > Privacy & Security**.

Build numbers stay monotonic so an existing updater-enabled Voice Coach installation can receive Ichido updates from the same feed. Use **Ichido > Check for Updates…**, or install once by hand if that menu is absent.

**System Requirements:** macOS 26.0 or later (Apple Silicon recommended).

**Speech Transcription:**
Apple on-device speech transcription is enabled by default. Choose the spoken language in **Settings > Transcription**, then use **Download Language…** if its Apple model is missing. This does not change your Mac’s language. New sessions retain their speech language for subsequent takes. Existing transcripts can be regenerated using **Re-transcribe** on a take or **Transcript > Re-transcribe** on a reference.

Parakeet is an optional local model (~714 MB), installable from the same settings pane or via `./scripts/setup-transcription.sh`. The bundled v3 model automatically recognizes 25 European languages, including French, but does not support Japanese. Its language control shows **Automatic**; Apple’s saved language preference does not steer it. Known unsupported session languages are rejected before transcription. Ichido uses the selected engine and reports failures without silently switching models. Audio analysis and saving still work when transcription is unavailable.

## How It Works

Ichido focuses on deliberate practice through a rapid loop: capture a take, review the recording, and adjust on the next attempt. Reference practice names differences from a reference.

### 1. Three Ways to Practice
* **Microphone**: Record rehearsed talks, pitches, presentations, or interview answers.
* **Mac System Audio**: Capture audio playing directly from your Mac (talks, podcasts, or browser clips) without complex virtual audio cables.
* **File Import**: Bring in existing audio or video files. Imported media is automatically normalized to 48 kHz mono WAV locally.

### 2. Review a Recording
An ordinary recording shows measured pauses, pitch, loudness, and clarity on the timeline. It does not assign practice exercises. A clipped or noisy take includes a short note that those estimates may be unreliable.

### 3. Reference practice
Reference practice lets you study how another speaker delivers a phrase:
1. **Listen**: Set an imported file or captured system audio as your reference model.
2. **Repeat**: Record your attempt right alongside it.
3. **Compare**: Inspect side-by-side pitch curves, rhythm alignments, and word-level emphasis. When the words line up, two practice targets name a difference from the reference.

The two practice styles are **Listen & Repeat** (the reference plays, then you record) and **Speak Along** (you follow the reference; use headphones so speaker playback does not leak into the mic). The marketing page adds an Understand step for Words. The app’s own loop stays Listen, Repeat, Compare.

### 4. Stacked Takes and Timeline Scrubbing
All attempts in a session stay grouped together (`Take 1`, `Take 2`, etc.). You can scrub the waveform, click any transcribed word to jump playback directly to that moment, and hear how your delivery changes from one take to the next.

### 5. Optional AI Analysis (Clipboard Export)
If you want qualitative script feedback or presentation advice, use **File > Copy AI analysis prompt + JSON** (or press `⌥⌘C`). This formats your acoustic metrics into a structured prompt on your clipboard so you can paste it into ChatGPT, Gemini, Claude, or any LLM of your choice. Ichido never contacts external AI APIs on its own.

### 6. Words: experimental on-device language exploration
Enable **Settings > Experiments > Enable experimental features**, open a recording or reference practice, and choose **Words** in the inspector. Explore meanings, grammar concepts, translations, synonyms, or word-by-word explanations. Suggested questions fill the composer so you can edit them before sending. Replies preserve lists and follow-ups, with Copy for the complete answer.

Choose **Reference** or **This take** from the compact context menu. Reference sessions start with the reference transcript. Chat uses the complete chosen transcript, without sentence selection or repeated transcript previews. **Translate…** opens a native sheet backed by Apple’s on-device `TranslationSession`, which can ask to download language models.

Chat uses Apple's on-device model and requires available Apple Intelligence. Each recording or selected reference practice attempt has a separate temporary conversation. Chats survive navigation while the app is open, but clear when you quit, clear the chat, delete the recording, or turn experiments off. Follow-ups use up to three recent exchanges. Only the complete chosen transcript and recent conversation are sent to the local model. Transcripts are not silently shortened; very long transcripts may exceed the local model’s context limit.

This chat is for language exploration. It does not evaluate takes or recommend performance improvements. Common coaching requests are rejected before inference, with model instructions and a conservative reply check as additional defenses. These checks are not a semantic guarantee. Transcription errors and incorrect language answers remain possible; the chat cannot hear audio, search the web, or verify facts. Original transcripts and measured practice targets are preserved.

## What It Measures

Ichido extracts objective acoustic properties to guide practice. It does not provide medical evaluations, diagnose speech conditions, or rate accents.

* **Pauses and Cadence**: Pause counts, average duration, speaking rate, and pause placement between clauses.
* **Pitch Dynamics**: Pitch range in semitones, fundamental frequency (F0) contours, and phrase-ending inflection.
* **Vocal Energy**: Loudness dynamics and phrase-ending energy drop-offs.
* **Recording Quality**: Harmonics-to-Noise Ratio (HNR), Signal-to-Noise Ratio (SNR), and clipping alerts.
* **Word Alignment**: Synchronized word timestamps when on-device transcription is available.

## Privacy by Design

Ichido processes recordings entirely on your Mac. It requires no user account and collects no telemetry. Update checks and optional language/model downloads use the network; recordings are never uploaded.

* **Local Storage**: All recordings, transcripts, and acoustic metrics live exclusively in:
  ```
  ~/Library/Application Support/VoiceCoach/
  ```
* **Explicit Permissions**: Microphone access is requested only when you click record. System audio capture access is requested only when capturing Mac output.
* **Clean Deletion**: Deleting a take or session permanently purges the underlying WAV and analysis files from disk.
* **On-Device Processing**: Audio analysis, speech transcription, and experimental chat execute on-device. Network access is used for update checks and optional model downloads.

## Development

### Prerequisites
* macOS 26.0+
* Xcode 26.x (CI builds on Xcode 26.6)
* Swift 6.2

### Quick start

```sh
./script/build_and_run.sh
./scripts/test.sh --all
```

If macOS says the Xcode license has not been accepted, run `sudo xcodebuild -license`.

Build, test, and verification commands, plus the package boundaries, are in [`AGENTS.md`](AGENTS.md). The packages are `VoiceCoachCore` (acoustics and reports), `VoiceCoachSession` (persistence), `VoiceCoachApp` (macOS UI and capture), and `VoiceCoachSelfTest` (contract smoke). Dependencies point inward: App → Session → Core.

## Releases

Tagged releases (`v*`) are built and verified automatically by GitHub Actions. For the release process and checklist, see [`docs/RELEASE.md`](docs/RELEASE.md).

## License

Distribution terms are in the GitHub release notes for each version.
