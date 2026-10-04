# Ichido promo · 4 October 2026

Kit and production notes for one **Ichido product promo** combining a launch film and app walkthrough. Animatic v5 runs **59.5 seconds**, inside the user's **45–60 second** range. Final music and voiceover remain for a later session.

Open [the review board](review/index.html), [the script](script.md) and [the two-reference breakdown](research/reference_videos.md). The direction combines reference A's component interactions with reference B's type and narrative pacing: a pointer chooses a real control, its verified next state appears, and the explanation lands while that state holds.

| Decision | Current direction |
| --- | --- |
| Format | 1920×1080, 16:9, 60 fps; 59.5 seconds / 3570 frames |
| Story | Bring a clip → Listen → Understand (Words) → Repeat → Compare → choose next try; one brief ordinary-recording example |
| Type / color | Existing Space Grotesk 700 and DM Sans 400; paper, ink, cobalt |
| Product treatment | Real component crops and faithful editable UI layers; exact labels and measured data |
| Artwork | Existing brand mark leads. One generated ribbon is optional at the bookends; the other three concepts are reserve assets |
| Audio | Later user-chosen Gemini BGM and VO; a scratch timed read precedes fine animation |
| Reference files | The 2026-10-04 Desktop movie and both Twitter clips are context/style only, including their sampled frames. The 2026-10-05 Words recording is a production source; only its derived plates enter the film |

## Production entry point

Give Opus [OPUS_BRIEF.md](handoff/OPUS_BRIEF.md). It specifies four initial reads: script, style guide, reference analysis and curated assets. `storyboard.json` supplies the timings. Everything else is lookup material for a specific implementation question, not mandatory front-loaded reading.

The [review board](review/index.html) is the preparation-phase overview; its 55-second timings predate the animatic, and `storyboard.json` supersedes them. Capture gaps are in [capture_plan.md](capture_plan.md) / [interaction_plan.json](interaction_plan.json); claims in [product_facts.md](product_facts.md); implementation details in [motion_spec.md](motion_spec.md). Audio and website handoffs apply later. Research notes and reserve assets retain provenance.

## Curation

Eleven exact pixel crops and three editable SVG interaction layers are new in revision 2. Revision 3 adds seven Words plates from the user's 2026-10-05 screen recording. Source screenshots remain unmodified. The inventory marks active, reserve and excluded assets explicitly. The historical tour poster and older `word-explanation.jpg` are excluded; current docs captures take priority over duplicate website JPEGs.

Words appears once, as the website's optional Understand step inside the French session. Settings, engines, a library tour and a second practice-mode demonstration are outside this short film; their evidence stays in the reserve library. There is one runtime and one script; longer cuts and alternate story branches have been removed.

Fresh response states for recording, comparison tabs, retry and word replay are still production inputs. The supplied screenshots support the specified fallback immediately. See the capture plan for the exact difference; the kit does not claim new interactions or audio were recorded.

## Production

The film is `IchidoPromo20261004` in `motion/src/promo/` (`IchidoPromo20261004-Animatic` adds guides and the scratch read), registered beside the starter `MyComp`. Run `npm run dev` in `motion/` for the Studio. Scene timing lives in `src/promo/timeline.ts` and is mirrored in `storyboard.json`.

| Task | Command, from `motion/` |
| --- | --- |
| Rebuild Words plates from the recording | `python3 -m pip install --target build/pylib pillow numpy` once, then `PYTHONPATH=build/pylib python3 scripts/make-words-plates.py` and `./scripts/sync-promo-assets.sh`. Needs the local recording |
| Regenerate the scratch read | `./scripts/make-scratch-vo.sh` (macOS `say`) |
| Render the clean preview | `npx remotion render IchidoPromo20261004 promo-2026-10-04/out/preview.mp4 --props='{"guides":false,"scratchVo":true}'` |
| Render the animatic | `npx remotion render IchidoPromo20261004-Animatic promo-2026-10-04/out/animatic.mp4` |

Renders live in Git-ignored `out/`, and the raw Words recording stays local in Git-ignored `assets/product/recordings/`. Style frames are in `review/style-frames/`; the review log is [review_log.md](review_log.md). The app and website are untouched.
