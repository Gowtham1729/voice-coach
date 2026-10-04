# Product evidence and claims

Verified against local source and the live site on 4 October 2026. Keep this file beside the script when writing or critiquing the film.

| Claim or feature | Evidence | Use in film |
| --- | --- | --- |
| Ichido, your private speaking room for Mac | `docs/brand/messaging.md`, README, live website | Primary descriptor |
| Native macOS 26+ app | README, AGENTS.md | Closing requirement; no web-app implication |
| Record with microphone; import audio/video; capture Mac audio | README, `MimicReferencePicker.swift`, Home and reference-picker captures | Input controls / brief ordinary-recording aside; no browser-recording implication |
| Ordinary recordings show measured pauses, pitch and loudness | README; Take captures | Five-second ordinary-recording aside |
| Click a transcribed word to replay that moment | README; `TranscriptBrowser.swift` | Explain the action; demonstrate only with authentic states/capture |
| Listen & Repeat plays first, then records | Messaging guide, README | Default reference practice path |
| Speak Along plays while the mic records | Messaging guide, README | Reserve evidence; separate Speak Along demonstration omitted |
| Compare timing, pitch and loudness | README; `MimicComparisonView.swift`, chart/timing sources and actual Compare screenshot | Main feature proof |
| Two measured practice targets when enough words reliably match | Messaging guide; `CoachingPlan.swift` selects at most two candidates; Compare capture shows two | Conditional claim, never a guaranteed result for every clip |
| Takes stay together in reference practice | README; captured take selector | Another take, not a guaranteed improvement |
| Words: meanings, grammar, synonyms, translations | README, messaging guide, user's 2026-10-05 Words recording | Understand beat (S03b), using the approved Words line |
| Words off by default; chat requires available Apple Intelligence | README, messaging guide, live website | On screen throughout S03b |
| Words cannot hear or evaluate the recording and can be wrong | Messaging guide, live website | Do not portray chat as an audio coach |
| Audio, transcripts and analysis stay on the Mac | README, messaging guide, live website | Privacy chapter |
| No account. No recording uploads. No analytics. | Messaging guide, live website | Use the complete statement |
| Update checks and optional model downloads use the network | Messaging guide, live website | Immediately follow the privacy statement |
| Free while in early access | Messaging guide and live site | Draft CTA support; recheck at final publication |

## Boundaries the film must preserve

No accent scores, phoneme-level pronunciation correction, fluency certification, diagnosis, diaphragm claims, or invented outcome statistics. Comparison targets describe differences from a reference; an ordinary recording has measurements rather than those targets. Never turn the sample take count or a metric value into a customer-success claim.

Use Ichido in prose and the existing `ichido.` wordmark for the brand lockup. Ichido means one time; the practice story is inspired by mō ichido. Do not claim Ichido itself means again. Visible feature names: Practice, Reference practice, Words, Listen & Repeat, Speak Along, Practice next, Capture Mac audio.

The app loop is Listen → Repeat → Compare. The website inserts optional Understand for Words. Do not invent an Understand control in the app. The film follows the website: Understand is typography over the real Words inspector, and Words remains a separate optional feature.

Apple is the default local transcription engine. Optional Parakeet supports 25 European languages automatically and does not support Japanese. There is no reason to overload the main film with engine details; if shown, keep these limits. Model availability and transcription quality vary.

The current app is ad-hoc signed and not Apple-notarized. Do not promise frictionless installation or seamless updates. The live site displayed version 0.0.3 during this review; omit version numbers from the evergreen film. Final release/download state needs a fresh check when the film is published.

## Source-image context

The current docs screenshots are real developer practice sessions. French practice and the English Compare example are distinct sessions; do not edit them into a fabricated single take. The English example visibly names a third-party review. For a coherent final walkthrough, capture a short developer-owned reference and real takes instead. Retain existing sources for inspection and do not retouch their transcript text, replies or measurements. The website copy `word-explanation.jpg` still shows Mimics/Ask and is excluded, alongside the historical tour poster. Current docs sources take precedence over duplicate JPEGs.

The rough movie demonstrates navigation and UI states but has no audio track. It supplies no evidence of acoustic audibility or improvement and is excluded from final media by user instruction.
