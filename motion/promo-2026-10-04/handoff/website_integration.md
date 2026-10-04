# Website replacement plan · later implementation

The user intends to replace the existing tour with this film. No website change or deployment is part of this preparation work.

## Existing player

`website/index.html` has a button reading “Watch the earlier app tour”, a `tour-dialog`, native video controls with `playsinline`, `preload="none"`, `assets/tour-poster.jpg`, `assets/voice-coach-tour.mp4`, and `tour-captions.vtt`. Chapters currently seek to 0, 6, 18, 36 and 48 seconds. The dialog title and note explicitly describe earlier Voice Coach footage. `website/app.js` handles seeking, play attempts, active chapter state and pause-on-close. The noscript fallback also links the old movie.

## Final assets to deliver

Suggested names: `ichido-promo-2026-10-04.mp4`, `ichido-promo-2026-10-04-poster.jpg`, `ichido-promo-2026-10-04.en.vtt`, and a text transcript. Main video: animatic v5 runs 59.5 seconds, hard range 45–60; 1920×1080, 60 fps, H.264 with yuv420p and AAC audio for a broadly compatible web candidate; enable fast-start and inspect the actual export on Safari and Chromium. Choose bitrate/quality after inspecting fine UI text and file weight, not by an untested fixed preset. Keep a high-quality master separately.

The poster should show Ichido's actual interface and brand, not the historical Voice Coach frame. Final captions should follow the real VO and meaningful sound, labelled English. The old scene-description timestamps cannot be reused. Final chapter seeks derive from the final locked edit; the compact draft chapter set, from the animatic v5 storyboard, is 0 (Meet Ichido), 10 (Listen & Repeat), 13 (Understand), 22 (Compare), 30 (Try again), 38 (Your own recording), and 43 (Privacy). These are not final player timestamps yet.

## Code changes when the film is ready

Update source/poster/track paths, tour button copy, title, note, chapters and noscript link together. Possible reviewed labels: “Watch Ichido in action” and “Your private speaking room.” Preserve the native controls, keyboard access, focus return and pause-on-close. Do not switch the film to autoplay or an automatic download.

`scripts/check-website.mjs` currently requires “Earlier Voice Coach footage.” Its historical requirement must change in the same patch as the new current-film copy. Follow `docs/brand/messaging.md` and `docs/marketing-website.md`; do not merely overwrite the MP4 while leaving the historical labels and chapter times.

Verify `node scripts/check-website.mjs`, `node scripts/test-sound-ribbon.mjs`, `node scripts/build-website.mjs` and `git diff --check`; then test playback, captions, chapter seeks, dialog close/pause, focus return and mobile sizing in browsers. Deploy only through the existing Sites workflow after explicit publication instructions, preserving Site-only source changes and verifying a succeeded deployment. The preparation kit does not establish final media quality or production deployment state.
