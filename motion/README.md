# Ichido motion

Remotion project for Ichido marketing videos. Lives next to `website/` so brand work stays in-repo without touching the Swift app targets.

## Setup

```sh
cd motion
npm i
npm run dev
```

## Render

```sh
npx remotion render IchidoPromo20261004 promo-2026-10-04/out/ichido-promo.mp4
```

## Films

- `IchidoPromo20261004`: the finished Ichido launch film (63.2 s). Picture, timing, and audio notes are in [`promo-2026-10-04/README.md`](promo-2026-10-04/README.md).

## Notes

- Put imported media in `public/`
- Copy brand assets from `../website/assets/` when a composition needs them
- Upgrade with `npx remotion upgrade` so Remotion packages stay on one version
- Agent skills (optional): `npx remotion skills add`
