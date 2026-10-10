# Marketing website

`website/` is the static site for the Mac app. The public URL is https://ichido.app. Firebase Hosting on project `ichido-511210` publishes `dist/` when GitHub Actions pushes to `main`, using Workload Identity Federation. Local checks still use the scripts below. The site does not record, analyse audio, or require an account.

## Check and build

```sh
node scripts/check-website.mjs
node scripts/test-sound-ribbon.mjs
node scripts/build-website.mjs
node scripts/serve-website.mjs --port 4173
```

`node scripts/build-website.mjs` copies `website/` to `dist/` for Firebase Hosting. `node scripts/serve-website.mjs` previews the `website/` source. The server does not serve the `dist/` copy.

The stylesheet, app module, and ribbon import URLs include the first 12 characters of each file’s SHA-256 as a `v` query parameter so returning browsers load changed assets immediately. After changing the ribbon, update its import version in `website/app.js` first. Then refresh the stylesheet and app versions in `website/index.html` for changed files; the checker verifies all three versions.

`check-website.mjs` is the contract, and it is not part of CI job `test`. It checks local assets, unique IDs, ARIA targets, four workflow tabs, the latest-release download with no pinned version, no external scripts, no capture or analytics APIs, no em dashes, and the exact strings in its `requiredCopy` array. Change one of those sentences only by editing `website/index.html` and the checker in the same change. Browser checks for dialogs, focus return, tabs, navigation, FAQ, video chapters, overflow, and the ribbon are separate from that script. Neither those checks nor `check-website.mjs` prove app contracts, signing, persistence, language accuracy, or hardware audio.

A website-only pull request is verified with the four commands above. It does not need Peekaboo or `./scripts/render-previews.sh`. Those Mac checks stay for app UI and layout changes.

## Copy and claims

Follow `docs/brand/messaging.md`. The page says **Listen → Understand → Repeat → Compare**. Understand is the optional language step, with Words’ experimental label and Apple Intelligence requirement beside its copy. The app’s own reference loop remains Listen → Repeat → Compare. No accent grades, fluency guarantees, or medical claims.

Use the shared product terms from the messaging guide in headings, instructions, FAQs, and image captions. The FAQ gives answers to practical questions and holds pronunciation and Words limitations; avoid repeating those cautions in feature copy or screenshot captions. Keep Words’ experimental badge and Apple Intelligence requirement beside the feature. Privacy has one full visible statement alongside the questions, with a link from its FAQ answer. Installation signing disclosure stays visible in the download dialog before the ZIP link, with installation steps collapsed on all screen sizes. Avoid internal storage details and former feature names. Keep the Ichido name, descriptor, and website headline consistent with that guide. Replace product screenshots with real captures when visible labels change.

The download URL stays `https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip`. Publish copy for a new version only after that release’s ZIP aliases and signed appcast exist. The app is ad-hoc signed and not notarized.

## Assets

- The social preview uses `ichido-share.jpg`. Its code-based composition is kept in `docs/brand/share-card.html`; it uses the same typography, messaging, and ribbon as the website.

- Product images are real app captures. Do not retouch labels, transcripts, replies, or measurements, and do not replace them with `build/previews` fixtures.
- `ichido-launch-film.mp4` is the launch film. The website player has no subtitle track. Do not put older Voice Coach footage back in its place, and do not present those old frames as the current interface.
- **Watch Ichido** in the hero opens the film dialog, with a direct MP4 link when JavaScript is unavailable. Closing the dialog pauses playback. The README uses a bare GitHub video-attachment URL for an inline player; repository MP4 links alone do not embed a player.
- The desktop ribbon is decorative. Mobile omits it. Reduced motion and unavailable WebGL use `sound-ribbon-still.jpg`, exported from the same ribbon renderer using `docs/brand/ribbon-still.html`. Do not add a runtime dependency, microphone use, or an outbound data path.
- The header and hero fill at least the small viewport height. Content can make the opening taller in short windows; do not clip it or capture wheel/touch scrolling. **Explore Ichido** is a native anchor to the next section. Practice steps enter with a short fade and rise, captures lift on hover, and section headings have a light scroll entrance where view timelines are supported. Content remains visible without that enhancement. Reduce Motion disables these effects and smooth anchor scrolling.
