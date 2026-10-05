# Ichido launch film

1920×1080, 60 fps, 63.2 seconds (3793 frames). Composition `IchidoPromo20261004` in `motion/src/promo/`. Timing lives in `src/promo/timeline.ts`. The end card holds so the closing line finishes.

Studio: `npm run dev` from `motion/`. The composition plays the mixed soundtrack.

```sh
npx remotion render IchidoPromo20261004 promo-2026-10-04/out/ichido-promo.mp4 --crf=15 --audio-bitrate=320k
```

Renders stay in gitignored `out/`. The current master on this machine is `out/ichido-promo-scored.mp4`.

`IchidoPromo20261004-Animatic` turns on guides and a scratch read. Regenerate that read with `./scripts/make-scratch-vo.sh` (macOS). It is not committed. Scene compositions and style frames are in the same Remotion folder, for checking one beat without rendering the film.

## Picture

Real crops and two full windows. Do not retouch labels, transcripts, or measured values, and do not invent a loading, playback, recording, or success state that was not captured.

| Asset | Role |
| --- | --- |
| `assets/components/` | Crops the scenes place on screen. Bounds are in `crop-map.json` and `src/promo/assets.ts` |
| `assets/product/docs/01-home.png`, `09-new-mimic.png` | Windows shown whole |
| `04`, `05`, `07` in that same folder | Sources for the practice, compare, and take crops |
| `assets/brand/brand-mark.png` | Opening and end-card mark |
| `public/promo-2026-10-04/` | What Remotion loads. Refresh it with `./scripts/sync-promo-assets.sh` |

Words plates come from the local recording `assets/product/recordings/words-chat-2026-10-05.mov` (gitignored). Rebuild with `PYTHONPATH=build/pylib python3 scripts/make-words-plates.py`, then sync. Words is experimental and off by default. The panel's own line stays visible: it can be wrong, and it cannot hear or evaluate audio.

On-screen privacy stays the full line: “No account. No recording uploads. No analytics.” then “Update checks and optional model downloads use the network.” The finished read says the voice stays completely offline. Leave the picture as the product line.

## Audio

| File | Role |
| --- | --- |
| `public/promo-2026-10-04/vo/ichido-promo.wav` | Voice stem |
| `public/promo-2026-10-04/music/calculated-grace.mp3` | Score |
| `public/promo-2026-10-04/vo/ichido-promo-mix.wav` | What the film plays |

Replace the read with `PYTHONPATH=build/pylib python3 scripts/finish-vo.py <read.wav>`. That removes gap clicks and hard cut-ins without moving words. Then `PYTHONPATH=build/pylib python3 scripts/mix-score.py`. The score ducks under speech, sits lower from 42.9–55.8 s, and fades out with the last frame. Both scripts need numpy (`python3 -m pip install --target build/pylib numpy`) and ffmpeg.
