# Ichido messaging guide

## Core identity

- **Name:** Ichido
- **Pronunciation:** approximately ee-chee-doh
- **Descriptor:** Your private speaking room.
- **Website headline:** Speaking practice. At your own pace.
- **Website introduction:** Practice a language. Rehearse a talk. Hear yourself back and find something to try next.
- **Page title:** Ichido | Private speaking practice for Mac.

## Product description

Ichido is a native Mac app for private speaking practice. Record yourself, practice with a reference, and explore the words behind a phrase. Review measured delivery, replay a moment, and keep another take alongside it. Audio, transcripts, and analysis stay on your Mac.

## Short descriptions

- **One line:** Private speaking and language practice for Mac.
- **Short bio:** A phrase. A clip. Your own voice. Listen, explore the words, repeat, and compare with Ichido, your private speaking room for Mac.
- **Reference practice:** Bring a reference, listen closely, and record your version. Compare timing, pitch shape, and loudness, then try another take.
- **Words:** Optional, experimental language help beside your transcript. Explore meanings, grammar, synonyms, and translations on your Mac.

## Language and naming

Use **Ichido** in prose and **ichido.** in the website wordmark. Keep the period as visual punctuation, outside product names, file names, and sentences where it would confuse readers. Ichido means one time; the story is inspired by mō ichido, once more. Do not claim that Ichido alone translates to “again” or “once more.” It is a multilingual practice product, rather than a Japanese-only course.

Use **Practice** for the app sidebar, **Reference practice** for the feature, and **Words** for the language inspector. Reference-practice modes are **Listen & Repeat** and **Speak Along**. The website sequence is Listen → Understand → Repeat → Compare; Understand is the optional Words step. The app sequence is Listen → Repeat → Compare. A take is one recorded attempt. A reference is the audio someone chooses to practice with. Historical release files and internal Swift names may still contain Voice Coach or Mimic for compatibility.

### Shared product terms

Use this guide for the app, website, README, and release notes. Marketing may explain a feature, but must keep its product name and controls recognizable.

| Term | Meaning and use |
| --- | --- |
| Recording | Audio recorded or imported into the library. |
| Take | One recorded version in a session. Do not label it an attempt. |
| Reference | The clip chosen for reference practice. |
| Practice | The sidebar destination for reference practice sessions. |
| Reference practice | The feature for listening, repeating, and comparing with a reference. |
| Listen & Repeat | The reference plays first, then recording starts. |
| Speak Along | The reference plays while the microphone records. Recommend headphones. |
| Transcript | Recognized text from a recording or reference. |
| Words | Optional language help beside the transcript. Chat requires Apple Intelligence. |
| Practice next | Two measured practice targets when enough words match reliably. |
| Capture Mac audio | Capture what the Mac is playing as a reference. |
| Settings → Transcription | Choose the speech engine and spoken language. |
| Settings → Experiments | Enable Words. |

The optional Understand tab introduces **Words**; it is optional and does not name another app feature. Keep **Your private speaking room.** as the shared descriptor and **Speaking practice. At your own pace.** as the website headline.

## Interface writing

- Write for the task at hand. Give the next action before background detail.
- Use familiar words and short, complete sentences. Avoid promotional language, forced encouragement, and explanations of internal architecture.
- Keep one explanation per decision. Do not repeat instructions already clear from nearby labels or controls.
- Use sentence case for labels and actions. Keep the established **Listen & Repeat** and **Speak Along** mode names.
- Label recorded text **Transcript**; reserve **Words** for language help. Use **take** consistently for one attempt.
- Name actions by their result: **Play selection**, **Retry saving**, **Clear chat**. Use an ellipsis when the user must choose something before the action proceeds.
- Describe optional features precisely. Rephrasing exercises changes their wording, not the measured targets or selected coaching actions.
- State deletion scope, audio retention, privacy, and AI limitations plainly. Brevity must not hide consequences or imply abilities the app does not have.

## Website direction

Lead with what Ichido makes room for: a language someone is learning, a talk they are rehearsing, or their own words. Keep the warm paper, expressive typography, and cobalt sound ribbon as the opening identity. The ribbon is a silent, playful expression of voice, not an acoustic measurement or an app preview.

Use one product overview further down with a real capture beside each relevant story. Keep its numbered Listen → Understand → Repeat → Compare tabs, cobalt selected chapter, and subtle graph-paper panel. The overview keeps its stronger framing. Separate the main page sections with quiet hairlines and generous spacing, rather than repeating the boxed treatment. Keep Words in the optional Understand step, and privacy alongside the questions. Avoid repeating the same screenshot or claim across separate sections. Mobile omits the ribbon and brings the product explanation and next action forward. Do not turn the hero into a cropped app panel or a feature inventory. Keep input methods and setup details secondary to purpose, with precise instructions available where needed.

## Proof and limits

Show the actual app and describe what people can do. Mark synthetic recordings and illustrative chat responses as examples. The launch film is the current walkthrough. Do not present older Voice Coach footage as the current Ichido interface. Do not invent testimonials, social proof, or outcome claims. A later demo or campaign needs its own brief and evidence.

Reference practice offers two measured targets when enough words reliably match. Ordinary recordings show measurements. Neither pathway grades an accent, certifies fluency, nor supplies phoneme-level pronunciation correction.

Words is off by default and requires available Apple Intelligence. It uses text, cannot hear audio, and may answer incorrectly. Chats clear when the app quits, when the user clears the chat, when the recording is deleted, or when experiments are turned off. Translation and transcription language support vary; optional models may need downloads.

The privacy statement is **No account. No recording uploads. No analytics.** Recordings and processing stay on the Mac; updates and optional model downloads use the network. Do not shorten this to “never uses the internet.”

## Distribution copy

Free while in early access. macOS 26+. Apple Silicon recommended. The app is ad-hoc signed and not Apple-notarized yet. Use the current GitHub release and verified ZIP aliases. Do not promise seamless updates without an installed-build test.
