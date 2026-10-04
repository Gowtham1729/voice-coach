# Remotion production specification

Use the existing `motion/` project, pinned to Remotion 4.0.532. Composition: `IchidoPromo20261004`, **1920×1080 / 60 fps / 3570 frames (59.5 seconds)** in animatic v5, registered alongside the starter. Keep all retiming inside 45–60 seconds. `storyboard.json` is the scene timing authority; `interaction_plan.json` supplies proposed action cues.

## Visual grammar

- A phrase introduces the purpose; a real component demonstrates it.
- One pointer approaches, pauses briefly, clicks a verified control, then yields to a readable response.
- Keep the clicked control or panel center as a stable anchor through an expansion, crop or repositioning.
- Use related product states: Home → picker, practice → comparison, targets → retry. Avoid unrelated shape tricks.
- The existing ribbon is a brief bookend. Privacy is a simple type stage. No extra art interludes or feature mosaics.

Starting timing ranges at 60 fps: pointer approach 24–42 frames; target settle 6–10; click compression 4–6; component transition 24–42; useful state hold 90–180. These are tuning suggestions, not measured timings from the reference videos. Tune against the actual animatic and VO. Long target/qualifier copy needs a longer hold.

## Deterministic implementation

Drive all animation from frame time using `useCurrentFrame()`, `interpolate()` and `spring()` as appropriate. Keep transitions deterministic and seekable; no wall-clock timers, unseeded random motion or CSS transitions. Tune springs for precise settling; prevent type from overshooting into adjacent content. [Remotion animation guidance](https://www.remotion.dev/docs/animating-properties), [spring API](https://www.remotion.dev/docs/spring).

Create reusable component stages, cursor/interaction layers and phrase typography. Use the crop atlas for real UI pieces; keep native appearance and exact text. Faithful editable control reconstructions are allowed when verified against source/captures. Preserve plots, targets, transcripts and measured values as exact source layers or verified data-backed recreations. No fictional better values, success messages or future states.

Missing response states are explicit in the interaction plan. Use the hover/hold fallback until fresh captures exist. Separate French practice, English comparison and ordinary recording as examples if the existing sources remain.

## Assets and fonts

Copy only active selected assets into `motion/public/promo-2026-10-04/` during implementation. Never bundle `reference/`, its sample frames, excluded historical captures or reserve media without a deliberate script revision. Use `Img` and `staticFile` for images; check the installed `@remotion/media` API before adding video/audio. [Assets](https://www.remotion.dev/docs/assets), [media Video](https://www.remotion.dev/docs/media/video).

Load local Space Grotesk 700 and DM Sans 400 and wait for fonts before rendering. The SVG wordmark contains live text; verify it resolves correctly. Titles/captions/explanations remain editable. [Font guidance](https://www.remotion.dev/docs/fonts).

## Production sequence and review

Build representative hook, component, Compare and closing stills first. Then make an animatic with a scratch timed VO; resolve reading holds before fine motion. Final BGM/VO arrives later and requires measured retiming. Start Studio when the composition work begins; render/export when requested.

Review consecutive transition frames and actual playback, not only stills. Check pointer hotspots, click→response alignment, text loading, plot/legend fidelity, source scale, privacy/network reading time and final CTA hold. Test out-of-order rendering for determinism. Keep timecoded findings in `review_log.md`. This preparation has not assessed finished smoothness or audio sync.
