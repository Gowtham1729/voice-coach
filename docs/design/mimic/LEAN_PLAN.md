# Mimic: focused first release

This is the recommended plan. It supersedes the broader exploration in [README.md](README.md). The three images there are alternative sketches of screens, not three features to ship.

## One concept

**A Mimic session has one reference clip and a history of your attempts.** An attempt is an ordinary recorded Take. The reference is stored separately and never counted as a Take.

There is no prerequisite recording. You do not first create a Take and then find a reference for it. The primary path is:

> New Mimic session → add reference → listen/read → record yourself → hear and see the difference → try again.

All attempts in the session use the same reference excerpt. Changing the target after attempts exist starts a new Mimic session, keeping previous comparisons meaningful. Existing regular sessions and Takes stay as they are.

## First-time flow

1. **New Session → Mimic.** Import one local audio or video clip. Extract audio on-device. If it is long, select a short excerpt with waveform trim handles; recommend roughly 5–20 seconds. Give the session an editable name derived from the file. Display the reference transcript if local transcription succeeds. A missing transcript does not prevent audio practice.
2. **Practice.** The session page pins a small reference player above a readable sentence. Choose **Listen & Repeat** or **Speak Along**. In Listen & Repeat, the reference plays, then the microphone records. In Speak Along, reference playback and microphone capture start together after a visible count-in. A headphone hint and reference-volume control appear for Speak Along. In both styles the user can stop explicitly. Only the microphone is recorded.
3. **Compare.** Saving the recording creates Take 1 and opens its comparison in the same session. Show two labelled transcript rows when alignment is reliable, A/B phrase playback, and one observation the user can verify by listening. Offer Pitch, Timing and Emphasis views; pauses sit within Timing. If words or metrics cannot be matched, say what is unavailable and keep playback usable.
4. **Retry.** **Try Again** returns to recording readiness with the same reference, style and focus. Each finished attempt becomes Take 2, Take 3, etc. A compact take picker switches attempts; selecting one restores its comparison. No new name, import, session or reference selection on retry.

## The screen

Preserve the existing macOS sidebar, toolbar, materials and inspector. A Mimic session uses its existing detail area for two states:

- **Ready/recording:** pinned reference, readable script, style picker, microphone level and one primary recording action.
- **Result:** reference-versus-selected-take transcript, one specific observation, a single selected chart, A/B transport and **Try Again**.

The reference remains pinned in both states. The existing Take picker becomes the attempt picker. The inspector supplements the center: recording devices and level during practice; selected word or comparison details during review. The loop works with the inspector hidden. **Open Take Analysis** leads to the current detailed Take page without changing its report/export behavior.

## What comparison claims

Pitch compares contour shape on a shared relative-semitone scale, not absolute speaking pitch. Timing displays actual word lengths and pauses; alignment must not hide the timing difference. Emphasis begins with relative acoustic energy plus duration/pitch evidence, not a confident claim about intended linguistic stress. A/B plays both sources at their original speed.

Show a supported statement such as “Your pause before ‘think’ was 180 ms longer” with **Hear Difference**. Do not ship percentage similarity, a composite score, phoneme correction or “best take” until evaluated. When transcription or correspondence is poor, show “Word comparison unavailable” and let the user listen and retry. No cloud analysis path is needed.

## First-release boundaries

Include: one imported reference excerpt per Mimic session; both practice styles; automatic saving of every attempt; selected-take history; reference/user playback; reliable pitch, timing and relative-energy views; one evidence-backed difference; one-action retry. Keep the current recording limit and permit attempts longer than the reference.

Defer: recording a reference inside the app, choosing an old Take as reference, multiple phrases/excerpts in one session, detected phonemes, aggregate scores, generated corrected audio and AI coaching. Those fit later without changing the session → reference → attempts model. The Phrase Workshop sketch is a later long-form extension, not part of this release.

## Build sequence and acceptance

1. Add session-owned reference storage and a safe library migration. Mimic always keeps its reference and all attempts; the existing “keep only newest” deletion path must not run on Mimic sessions. Add migration/persistence checks.
2. Add reference import and the one-screen practice states. Coordinate simultaneous playback and microphone capture deliberately for Speak Along; the current recording path stops playback. Preserve ordinary recording behavior.
3. Add conservative word alignment/comparison, linked selection, A/B listening and Try Again. Reuse full-resolution acoustic frames rather than downsampled export contours; preserve the existing report shape.
4. Validate Core contracts, app build, fixture previews and live microphone/headphone use. Test both styles, retries, relaunch/history, missing transcription, mismatched words, audio-route changes and recording interruption. Synthetic screenshots alone do not establish audio synchronization.

The release is successful when a new user can import a reference, practise with either style, compare and hear one meaningful difference, retry immediately, and reopen every saved attempt—without having to understand pairing two existing Takes.
