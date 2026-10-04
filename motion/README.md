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

## Notes

- Put imported media in `public/`
- Copy brand assets from `../website/assets/` when a composition needs them
- Upgrade with `npx remotion upgrade` so Remotion packages stay on one version
- Agent skills (optional): `npx remotion skills add`
