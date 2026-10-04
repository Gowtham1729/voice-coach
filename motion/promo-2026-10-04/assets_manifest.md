# Curated assets · revision 3

Only **active** and the single **optional** ribbon candidate belong to the current production plan. The full JSON retains provenance, dimensions and hashes for all copied sources. Reserve assets stay available for inspection, with `use_in_final: false`; excluded media must remain outside the film.

## Active component pack

| Asset | Native dimensions | Scene / purpose |
| --- | --- | --- |
| [home-actions](assets/components/home-actions.png) | 830×85 | S02 · Home actions; Reference practice… opens the picker |
| [reference-inputs](assets/components/reference-inputs.png) | 650×155 | S02 · Reference picker: Import clip… and Capture Mac audio |
| [practice-card](assets/components/practice-card.png) | 2110×670 | S03 · French reference practice, Take 2; transcript and mode |
| [practice-mode](assets/components/practice-mode.png) | 675×77 | S03 · Listen & Repeat is already selected; no new state implied |
| [practice-actions](assets/components/practice-actions.png) | 570×80 | S03 · Listen, Start practice and Record |
| [compare-pitch](assets/components/compare-pitch.png) | 2110×840 | S04 · English comparison, Take 7; real Pitch chart and legend |
| [compare-modes](assets/components/compare-modes.png) | 512×78 | S04 · Pitch, Timing, Emphasis; only Pitch response is captured |
| [practice-next](assets/components/practice-next.png) | 630×640 | S05 · Two real Practice next targets from English Take 7 |
| [try-again](assets/components/try-again.png) | 630×65 | S05 · Actual Try again control; following state needs a fresh capture |
| [take-selector](assets/components/take-selector.png) | 265×65 | S05 · Take 7 of 7; no open-menu state captured |
| [take-words](assets/components/take-words.png) | 1220×71 | S06 · Ordinary recording: first transcript-word row; no selected/playing state captured |

These are exact pixel crops, not retouched artwork. [crop-map.json](assets/components/crop-map.json) records source hashes, rectangles and pointer anchors. The source originals are current docs Home, picker, practice, Compare and Take captures. French practice, English comparison and ordinary recording are different sessions.

## Words plates (revision 3)

The Understand beat (S03b) uses recorded frames from the user's 2026-10-05 screen recording of a Words chat in the same French session, Take 2. Every plate is the inspector at source scale, 680×1186, built by `motion/scripts/make-words-plates.py`.

| Asset | Recorded state |
| --- | --- |
| [words-idle](assets/components/words-idle.png) | Empty chat, Explore the words |
| [words-menu](assets/components/words-menu.png) | Suggested questions open |
| [words-menu-rows](assets/components/words-menu-rows.png) | Each menu item highlighted, for the pointer to pass over |
| [words-filled](assets/components/words-filled.png) | "What does this transcript mean?" in the field |
| [words-thinking](assets/components/words-thinking.png) | Sent; Thinking… with the stop button |
| [words-spinner](assets/components/words-spinner.png) | 60 recorded spinner frames, about 30 fps |
| [words-answer](assets/components/words-answer.png) | The assistant reply with three glosses |

The plates are not exact rectangles: the empty chat area between the reply and the composer is dropped so the panel fits beside the transcript, and the recorded pointer is removed (the film draws its own). Menu items other than Explain the meaning reuse the captured highlight colour and corner radius under their own captured glyphs. No text, reply or control is retouched. The raw recording stays local and Git-ignored; `words-menu-explain` is a build intermediate.

## Brand, type and interaction

- Existing [brand mark](assets/brand/brand-mark.png) and [wordmark](assets/brand/ichido-wordmark.svg). The wordmark contains live text.
- Bundled Space Grotesk 700 and DM Sans 400, with OFL licenses.
- New [cursor](assets/interaction/cursor.svg), [click ring](assets/interaction/click-ring.svg) and [focus outline](assets/interaction/focus-outline.svg); usage/hotspot details in [interaction README](assets/interaction/README.md).
- Optional [generated ribbon cutout](assets/generated/01-ribbon-cutout.png), 1672×941 with real alpha. Inspect speckles/end margins; bookends only.

## Reserve and excluded material

The macro, private-room and night art, other screenshots, duplicate website JPEGs, website icon library, framed app icon and additional font weight are reserve assets. They are outside the active timeline; no extra raster generation is needed for this component story. Sources remain intact so useful evidence is recoverable.

Excluded: historical tour poster, older `word-explanation.jpg` showing Mimics/Ask, fixed social card, the 2026-10-04 rough Desktop recording (`reference/rough-desktop.mov`), both Twitter clips, and all reference frames/contact sheets. Reference clips and derived analysis stay Git-ignored. The old website tour is not usable current footage.

Fresh response states are specified in [capture_plan.md](capture_plan.md); the current atlas is not a recording of clicking, playback or improved results.

Complete inventory: [assets_manifest.json](assets_manifest.json).
