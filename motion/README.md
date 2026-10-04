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
npx remotion render MyComp out/promo.mp4
```

## Films

- `IchidoPromo20261004`: the Ichido launch and walkthrough film (59.5 s). Source is in `src/promo/`; the kit, script, storyboard and review log are in [`promo-2026-10-04/`](promo-2026-10-04/README.md). The `-Animatic` version plays a scratch read that is generated, not committed: run `./scripts/make-scratch-vo.sh` (macOS) first.

## Notes

- Put imported media in `public/`
- Copy brand assets from `../website/assets/` when a composition needs them
- Upgrade with `npx remotion upgrade` so Remotion packages stay on one version
- Agent skills (optional): `npx remotion skills add`
