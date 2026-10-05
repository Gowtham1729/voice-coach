# Ichido launch film

1920×1080, 60 fps, 63.2 seconds (3793 frames). Composition `IchidoPromo20261004`. Timing is `motion/src/promo/timeline.ts`. The pictures and the mixed soundtrack live in `motion/public/promo-2026-10-04/`.

```sh
cd motion
npm i
npm run dev
npx remotion render IchidoPromo20261004 promo-2026-10-04/out/ichido-promo.mp4 --crf=15 --audio-bitrate=320k
```

Renders stay in gitignored `out/`. The master on this machine is `out/ichido-promo-scored.mp4`.

The film plays `vo/ichido-promo-mix.wav`. The voice alone is `vo/ichido-promo.wav`, and Calculated Grace is `music/calculated-grace.mp3`. To replace the read, run `PYTHONPATH=build/pylib python3 scripts/finish-vo.py <read.wav>`, then `PYTHONPATH=build/pylib python3 scripts/mix-score.py`. Both need numpy and ffmpeg.

On-screen privacy stays “No account. No recording uploads. No analytics.” then “Update checks and optional model downloads use the network.” The finished read says the voice stays completely offline. Leave the picture as the product line.

Words is experimental and off by default. The panel's own line stays visible: it can be wrong, and it cannot hear or evaluate audio. Do not retouch labels, transcripts, or measured values.
