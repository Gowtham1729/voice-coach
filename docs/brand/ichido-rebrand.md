# Ichido rebrand and product clarity plan

Status: delivered. App rebrand, early-access release, marketing assets, and existing public Site publication are complete. This document is the working brief and acceptance record for the October 2026 rebrand.

## Brand decision

The product is **Ichido**, pronounced approximately **ee-chee-doh**. The descriptor is **Your private speaking room**. Japanese *ichido* means one time; the practice story is inspired by *mō ichido*, once more. Do not claim that Ichido alone translates to again.

Ichido helps people practise spoken delivery and explore language through their own recordings and a reference they choose. It is a native Mac practice tool, with acoustic evidence and optional language help. It does not certify fluency, rate accents, diagnose voice conditions, or promise perfect pronunciation.

## Audience and jobs

- A language learner brings a short spoken phrase, listens, explores unfamiliar words, repeats it, and compares their delivery.
- A speaker rehearses an interview, presentation, or everyday conversation, listens back, and tries another take.
- A careful learner keeps reference audio, transcripts, and attempts together in a private local library.

## Product and claim boundaries

- Recordings show measured timing, pauses, pitch, loudness, and recording quality. Ordinary recordings do not assign exercises.
- Reference practice compares a retained attempt with its reference. Two practice targets require reliable word matching; comparable phrasing matters.
- The website explains **Listen → Understand → Repeat → Compare**. Understanding is optional. The default app loop remains Listen → Repeat → Compare.
- **Words** is the clearer visible name for the existing experimental Ask inspector. It explores meanings, grammar, synonyms, and translations from text. Apple Intelligence must be available. Chat cannot hear or grade audio; replies can be wrong and conversations clear when the app quits.
- Apple transcription and translation support vary by language and device. Optional Parakeet supports 25 European languages, with automatic recognition; it does not support Japanese.
- Audio, transcripts, analysis, and language chat run on the Mac. Update checks and optional model downloads use the network. No account, analytics, or recording uploads.

## Visual direction

Retain the recognisable cobalt ribbon and app icon. Warm ivory, cobalt, Space Grotesk, and DM Sans remain the website system. Use a compact lowercase **ichido.** wordmark, expressive editorial headings, current product screenshots, and one playful ribbon interaction. Avoid stock microphones, generic AI motifs, fake chat performance, and invented social proof.

## Delivery sequence

1. Verify current repository, hosted Site history, product contracts, and release state.
2. Rebrand the visible app, permission text, packaged bundle, build/release documentation, and website metadata. Keep internal Swift targets, bundle identifier, updater identity, preference keys, report formats, and `Application Support/VoiceCoach` intact.
3. Clarify Home and reference-practice entry points. Use **Practice** for the sidebar, **Reference practice** for the feature, and **Words** for experimental language exploration.
4. Rebuild the website story: concrete hero; four-step product tour; optional language explanation; three input sources; privacy; requirements and FAQ; consistent installation/download actions.
5. Use live screenshots from main and user-provided captures; inspect the rebuilt app in macOS. Keep fixtures for layout checks, and label the earlier Voice Coach tour accurately. Produce reusable wordmark/share assets and a concise messaging guide.
6. Run the repository's full contracts, app build, signed-bundle checks, app previews, website checks, keyboard/mobile/reduced-motion browser checks, and content audit.
7. Synchronise validated source and publish the existing public Site. Verify the exact source/version/deployment and destination download. Report app packaging, repository delivery, public app release, and Site publication separately.

## Acceptance record

- [x] App displays Ichido in bundle metadata, windows, settings, permissions, and user-facing errors.
- [x] Home explains the two practice entry points; reference practice and Words are discoverable and consistent.
- [x] Existing storage, recordings, updater identity, and report contracts are preserved.
- [x] Website describes both speaking delivery and language exploration, with experimental limitations visible.
- [x] Website uses current screenshots, accurate media labels, accessible interactions, and responsive layouts.
- [x] README, installation/release guidance, brand messaging, and social metadata agree with the delivered state.
- [x] Relevant automated and visual checks pass; hardware and real language accuracy are not claimed from fixtures.
- [x] Hosted source and published version match the verified artifact; the live page and download destination are checked.

The launch campaign, new demo video, and motion-design production are explicitly the next phase.

## Verification evidence

- `./scripts/test.sh --all`: Core, Session, app coordination, and SelfTest passed. Optional live model smoke tests remain opt-in; a real French transcript question was also exercised in the local app.
- `./scripts/build-app.sh` and `./script/build_and_run.sh --verify`: release bundle builds, verifies its nested ad-hoc signatures, and launches as Ichido.
- `./scripts/render-previews.sh`: layout and fixture-library migration checks passed. These synthetic captures are not website product media.
- Live native Home, reference practice, Words, language settings, Light, and Dark were inspected. Original system Dark appearance was restored. The native appearance mismatch discovered during review was fixed by reading AppKit effective appearance after clearing overrides.
- Website checks, ribbon tests, static build, and `git diff --check` pass. Browser review covers widths 320, 390, 768, and 1440 with no horizontal overflow, tab keyboard navigation, dialog focus restoration, mobile menu dismissal, exclusive FAQ expansion, video chapter seeking and close/pause, and ribbon click/keyboard/pause/resume. Automated ribbon checks cover reduced motion and mobile fallback. Browser console has no warnings or errors.
- Acoustic accuracy, microphone/system-audio hardware capture, broad translation quality, and a complete older-app Sparkle install/relaunch are not established by these checks. The app remains ad-hoc signed and not Apple-notarized.

## Published delivery — 4 October 2026

- [Rebrand PR #69](https://github.com/Gowtham1729/voice-coach/pull/69) merged as `fb2a90922f8ec504c7edbfd792492056451ecfb4`. The final PR [CI gate](https://github.com/Gowtham1729/voice-coach/actions/runs/37203697619) passed.
- [Ichido 0.0.2](https://github.com/Gowtham1729/voice-coach/releases/tag/v0.0.2), build 14, is public. The [release workflow](https://github.com/Gowtham1729/voice-coach/actions/runs/37203982271) passed tests, app build, ZIP packaging, signed Sparkle feed generation/verification, and release creation.
- `Ichido-0.0.2-macOS.zip`, `Ichido-macOS.zip`, and the legacy `Voice-Coach-macOS.zip` share SHA-256 `aba09ccf6a59ea7deb1e96964be47763a855249a4bba3b13e49f8dba3db1a9ff`. The public versioned archive was downloaded, unpacked, and its nested ad-hoc signatures verified. Bundle metadata is Ichido, version 0.0.2/build 14, macOS 26.0, with `com.gowtham.voicecoach` and `VoiceCoachApp` retained.
- The appcast advertises build 14/macOS 26.0 and references the versioned Ichido archive with matching length and an EdDSA signature. Stable Ichido/legacy download aliases and `appcast.xml` resolve publicly. This does not establish an older-app updater install/relaunch.
- Existing public Site: [Ichido](https://voice-coach-studio.gowtham.chatgpt.site/). Saved version **17**, source `d12e132c1f9608a86e03c30ea42b8d7762d9e392`, deployment `appgdep_6ac24ebb59e08191b7976e808729b1b7`, status **succeeded**. Existing audience and address are preserved; display title is Ichido.
- The live headline, four practice tabs, version, and download destination were checked. Production scripts/styles, five main product captures, and the share image returned HTTP 200 and matched local SHA-256 hashes. The live desktop page had no overflow or browser console warnings/errors.
- Creative Production board `bc0cae48-ac7c-48ce-98b6-5ff01b36f2a4` contains the website desktop/mobile captures, native Home capture, and share card. All four items completed; final board revision is 6.

This delivery record updates documentation only. The deployed website files remain identical to the verified version 17 artifact.
