# Ichido

**Your private speaking room.**

A Mac app for speaking practice. Record yourself, practice with a reference clip, and explore the words in your transcript. Audio, transcripts, and analysis stay on your Mac.

[Download for macOS](https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip) · [Website](https://ichido.app) · [Release notes](https://github.com/Gowtham1729/voice-coach/releases/latest)

https://github.com/user-attachments/assets/3efb9a61-5bff-4cef-8706-50102a6433b4

## Get started

Requires **macOS 26 or later**. Apple Silicon recommended. Free while in early access.

1. Download the ZIP, unzip it, and move **Ichido.app** to Applications.
2. Open Ichido. The app is not Apple-notarized yet. If macOS blocks it, follow [Apple’s opening guidance](https://support.apple.com/en-us/102445).
3. Choose **Record** for your own recording, or **Practice → New reference practice…** to practice with a clip.

Already using Voice Coach? Ichido is the same app with a new name. Your library and preferences carry over. Get updates from **Ichido → Check for Updates…**.

## What you can do

| Feature | Use it to |
| --- | --- |
| **Recording** | Record or import audio or video. Replay a moment, read the transcript, and review pauses, pitch, loudness, and recording quality. |
| **Reference practice** | Import a clip or capture Mac audio. Listen, record your version, compare, and try another take. |
| **Words** | Ask about meanings, grammar, synonyms, and translations beside your transcript. Optional and experimental. |

**Listen & Repeat** plays the reference before you record. **Speak Along** plays it while you record; use headphones. When enough words match reliably, **Practice next** gives two measured targets. Ichido does not grade accents or correct individual sounds.

Apple transcription is the default. Choose your spoken language in **Settings → Transcription**. Optional Parakeet detects 25 European languages automatically; use Apple for Japanese.

Enable Words in **Settings → Experiments**. Chat requires Apple Intelligence, works from text, and can make mistakes. Chats clear when you quit.

## Privacy

**No account. No recording uploads. No analytics.**

Recordings and processing stay on your Mac. Update checks and optional model downloads use the network. The library stays in `~/Library/Application Support/VoiceCoach/`.

## Build from source

Requires macOS 26+, Xcode 26.x, and Swift 6.2.

```sh
./script/build_and_run.sh
./scripts/test.sh --all
```

See [AGENTS.md](AGENTS.md) for build commands and the code layout, and the [release guide](docs/RELEASE.md) for publishing. The promo site source is [`website/`](website/); see [docs/marketing-website.md](docs/marketing-website.md). It is published at [ichido.app](https://ichido.app/).

## Help

[Report a bug or request a feature](https://github.com/Gowtham1729/voice-coach/issues). Maintained by [Gowtham](https://github.com/Gowtham1729).
