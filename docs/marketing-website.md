# Marketing website

`website/` is the static promo site for the Mac app. The public URL is https://ichido.app/ (apex). `www.ichido.app` redirects there. Firebase Hosting on project `ichido-511210` publishes `dist/` when GitHub Actions pushes to `main`, using Workload Identity Federation (`.github/workflows/deploy-website.yml`). The site does not record audio, analyse speech, or require an account.

## Check and build

From the repo root:

```sh
node scripts/check-website.mjs
node scripts/build-website.mjs
node scripts/serve-website.mjs
```

`build-website.mjs` copies `website/` to `dist/` and fingerprints assets for Hosting. `serve-website.mjs` previews the `website/` source on port 4173. It does not serve `dist/`. `node scripts/test-sound-ribbon.mjs` exercises the decorative ribbon when that script changes.

Stylesheet, app, and ribbon URLs carry a short content hash (`?v=`). The checker expects those hashes to match the files. Hosting rewrites asset names again at build time.

`check-website.mjs` confirms local files, unique IDs, ARIA targets, JavaScript syntax, the apex canonical and share URLs, the latest-release download, and that the page does not load external scripts, capture audio, or add analytics. It does not lock sentences. It is not part of CI job `test`. A website-only change does not need Peekaboo or `./scripts/render-previews.sh`.

Product names and claims are in `docs/brand/messaging.md`. The published share image is `website/assets/ichido-share.jpg`. Do not add analytics, a recording path, Terraform, or a paid host. Do not point the page at a former host.
