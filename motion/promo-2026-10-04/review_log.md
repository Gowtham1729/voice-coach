# Preparation review · revision 2

## Decisions carried forward

The user chose one 45–60 second Ichido product launch/walkthrough and a blend of the two supplied style clips. The plan now targets 55 seconds at 60 fps. The first clip informs component selection and continuity; the second informs type and story pacing. Analysis used half-second samples and 0.125-second transition strips, not an audio audition or continuous-playback quality review.

The app/brand guide and current docs captures support the script. Source code confirms Home → reference picker, Listen & Repeat behavior, comparison tabs, Try again and transcript-word actions. The old website word-explanation image still shows Mimics/Ask; it and the historical tour poster are excluded. Current docs filenames are historical, but the selected visible controls are current.

## Cleanup completed

- Replaced long-film timing, alternate cuts and unresolved runtime questions with one 55-second timeline and a hard 45–60 second range.
- Removed separate Words/settings/library/engine sections, a second practice-mode demonstration and extra art interludes.
- Condensed the VO to 84 words; the descriptor appears once, with a deliberate opening/closing phrase bookend.
- Replaced blanket bans on redrawing UI/cursor clicks with faithful editable-control guidance and explicit verified-response rules.
- Prioritized current docs originals over duplicate website JPEGs. The active pack has eleven exact crops and three editable SVG overlays.
- Demoted three competing generated concepts to reserve; only the ribbon cutout remains an optional bookend.
- Updated script, timeline, storyboard, type/motion guidance, action plan, asset flags, audio brief, Opus handoff, player chapter proposal and review board together.

## Checks performed

All 63 packaged asset hashes match the full inventory; copied source hashes also match. All JSON parses. All eleven crops are byte-for-byte pixel-equivalent to the specified rectangles in their source images. Pointer anchors fall inside their crops. Every timeline candidate is active/optional eligible media. Eight scenes cover exactly 3300 frames at 60 fps, without gaps or overlaps. All seven proposed action cues lie inside their scenes and map to documented pointer targets. All local Markdown and review-page links resolve.

Browser inspection confirmed all 22 review images loaded, fonts loaded, both reference-video metadata streams loaded, and no horizontal overflow at the 1280×720 viewport. The hero and product planning panels were visually inspected. A CSS specificity issue reduced storyboard title type; it was fixed and the corrected title/privacy/CTA sizes were checked. `review/preview.jpg` is the updated overview. This board is a static preparation artifact, not video-quality proof.

Git status contains only the new promo folder. Reference videos/derived style frames and the Desktop recording remain Git-ignored. No app, website or existing Remotion source/dependencies changed; no final video, BGM or VO was produced.

## Remaining production inputs

Six action responses still need authentic state evidence for the complete click sequence: loaded reference, playback/recording, Timing, Emphasis, retry and selected-word playback. Each has an immediate focus/hold fallback in `interaction_plan.json` and `capture_plan.md`. Current practice/comparison/ordinary-recording assets are separate sessions; use explicit example changes until fresh consistent captures replace them.

Before fine animation, make representative stills and a scratch-VO animatic. After final BGM/VO arrives, audition and retime. Later review must inspect actual playback, consecutive transition frames, cursor alignment, source-scale readability, claim fidelity, audio mix, captions and the CTA hold. No finished smoothness, audio sync, learning outcome or audience acceptance is established by this preparation.

## Production review · animatic v1 to v5

Built in `motion/src/promo/` (Remotion 4.0.532, 1920×1080, 60 fps). Renders live in `out/` (Git-ignored); style frames in `review/style-frames/`; one-frame-per-second sheet in `review/animatic-v5-contact.jpg`. Each row's timecodes belong to the pass it names.

| Pass / timecode | Observed issue | Concrete repair | Recheck result |
| --- | --- | --- | --- |
| v1–v3 · style frames | A `<Still>` clips every inner Sequence to one frame, so stills came out partial | Style frames are full-length compositions frozen on one frame | All five stills match the same frames in the full render |
| v1–v3 · morphs | Tailwind preflight `img { max-width: 100% }` shrank crops wider than their parent | `maxWidth: "none"` on every crop and strip image | Crops render at source scale |
| v1–v3 · Compare dive | Zoom framing had to keep the chart legible | Dive anchored on "about": legend whole, subtitle and panel bottom just outside, right edge between words | Checked at the dive hold |
| v1–v3 · Try again | Take selector crossed Try again as both moved | Take count fades in only after Try again lands | No crossing in consecutive frames |
| v1–v3 · S07 copy | Draft VO put "Your recordings stay on your Mac." between the privacy statement and the network sentence | Network sentence moved directly after the statement | v4 gap between the two reads is 7 frames (48.72 s → 48.83 s) |
| v1–v3 · S02 copy | Script descriptor "Private speaking practice for Mac." differs from the brand docs | Uses the primary descriptor "Your private speaking room for Mac." | Matches `docs/brand/messaging.md` |
| v3 · determinism | Needed proof that renders are stable | Re-encoded frames 1460 and 2990 separately (v3 timeline) | PSNR 35.7–43 dB against the full render: encoder noise only |
| v4 · 00:10.4–00:22.1 | User asked for the Understand step (Words local chat) | French session split into Listen, Understand the words (S03b) and Then repeat (S03c), built from the user's 2026-10-05 recording | See rows below |
| v4 · 00:13.2–00:19.8 | Words has to read as the real app | Every state is a recorded plate; the menu highlight hit-tests the real rows under the film pointer; click blink and fade follow the recording | Frame by frame: highlight climbs Translate into → Explain the meaning, blinks off for four frames, gone 15 frames after the click |
| v4 · 00:15.5–00:16.5 | Thinking… runs about 4.5 s in the recording | Shortened to 0.93 s with the recorded spinner frames | Disclosed in `storyboard.json` (S03b capture_note) |
| v4 · 00:13.7–00:19.2 | Words requirements must be on screen | "Experimental and off by default. Chat requires available Apple Intelligence." holds about 5 s; the panel's own "AI can be wrong. It can't hear or evaluate your audio." stays visible | Present in every S03b frame checked |
| v4 · 00:19.3–00:19.9 | Sub-line and qualifier were still exiting while the panels glided through them | Body copy and the gloss ring leave 44 frames before the camera moves | Frames 1160–1216 carry only panels and the headline swap |
| v4 · 00:13.1–00:13.3 and from 00:19.7 | Glyph tips showed before the 1.3-leading sub-line entered; descenders stayed after it left | `Phrase` travel grows with leading (unchanged at line height 1) | Residue under "Repeat." 42 → 0 dark pixels; pre-entry tips gone |
| v4 · determinism | The new scene derives its state (plate, menu row, spinner cell) from the frame number alone | Rendered frame 1076 out of order (frozen still) and in order (sequence), both PNG | Bit-identical: 0 pixels differ |
| v4 · timing | Words beat lengthens the film | Compare gives back 50 frames after the targets hold, Recording and Privacy 20 each | 3476 frames, 57.93 s, inside 45–60 s |
| v4 · audio | Scratch VO must land on its beats | Three French lines replace one; cues stay scene-relative | Detected VO onsets: 10.74 s, 13.37 s, 23.37 s, 28.44 s, 41.04 s, 52.27 s, 55.00 s, each within 10 ms of its cue |
| v5 · 00:42.9–00:55.8 | User chose to name transcripts in the privacy read | The website sentence "Your recordings, transcripts, analysis, and language chat stay on your Mac." replaces "Your recordings stay on your Mac." and also lands on screen under the network sentence; the block moves up 38 px to stay centred | Statement, then the network sentence 7 frames after it, then the new line, which is on screen 4.6 s before the stage clears |
| v5 · timing | The scratch read is 5.18 s, about 3.4 s longer than the line it replaces (the option was offered as about 1.6 s) | Privacy +184 frames, paid for by the opening hook hold (−20), the Compare targets hold (−30) and the Recording hover (−40) | 3570 frames, 59.5 s, inside 45–60 s |
| v5 · 00:29.8–00:37.8 | After the trim, target one kept the ring 1.1 s against 1.5 s for target two (`follow` keys arrive at their frame) | Target-two hop arrives at frame 712 | About 1.3 s each |
| v5 · frames | Retimed stretches need a frame check | Opening lockup, Compare retry, Recording iris and all of Privacy reviewed at half scale; style frames re-rendered | No collisions or glyph residue; the new line enters word by word and clears with the stage |
| v5 · audio | Scratch VO must still land on its beats | Cues stay scene-relative | All 14 VO onsets within 10 ms of their cues; the privacy line ends 0.7 s before "Ichido. One more try." |

Open items: response-state captures listed in `capture_plan.md` (Import loaded, Start practice playback and recording, Timing and Emphasis, the state after Try again, selected-word replay); final VO and music, retimed to the real read (the film has 0.5 s of headroom under 60 s); an audition of actual playback with audio.

## Handoff simplification

Reduced `handoff/OPUS_BRIEF.md` to one production entry point with four initial reads. Timeline JSON remains the timing authority; remaining research, capture, claim, audio and integration documents are lookup material. The README now uses the same reading gate. This changes information delivery, not the script, assets or creative direction.

## Product subject clarified

Corrected the misleading phrase 'website launch' throughout the active brief. The film launches and demonstrates Ichido, the native Mac app. The existing website player is a distribution location only; site integration remains a later lookup document. The script, timing and assets are unchanged.
