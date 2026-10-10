# Marketing website

`website/` is the static site for the Mac app. The public URL is https://ichido-511210.web.app. Firebase Hosting on project `ichido-511210` publishes `dist/` when GitHub Actions pushes to `main`, using Workload Identity Federation. Local checks still use the scripts below. The site does not record, analyse audio, or require an account.

## Check and build

```sh
node scripts/check-website.mjs
node scripts/test-sound-ribbon.mjs
node scripts/build-website.mjs
node scripts/serve-website.mjs --port 4173
```

`node scripts/build-website.mjs` copies `website/` to `dist/` for Firebase Hosting. `node scripts/serve-website.mjs` previews the `website/` source. The server does not serve the `dist/` copy.

`check-website.mjs` is the contract, and it is not part of CI job `test`. It checks local assets, unique IDs, ARIA targets, four workflow tabs, the latest-release download with no pinned version, no external scripts, no capture or analytics APIs, no em dashes, and the locked sentences and URLs below. Browser checks for dialogs, focus return, tabs, the mobile menu, FAQ, video chapters, overflow, and the ribbon are separate from that script. Neither those checks nor `check-website.mjs` prove app contracts, signing, persistence, language accuracy, or hardware audio.

A website-only pull request is verified with the four commands above. It does not need Peekaboo or `./scripts/render-previews.sh`. Those Mac checks stay for app UI and layout changes.

### Locked sentences and URLs

Changing a locked sentence or URL means editing `website/index.html` and `scripts/check-website.mjs` in the same change. A page sentence outside this list can change in `website/` alone. The other checks in the script still apply.

`requiredCopy` in `scripts/check-website.mjs`:

- Your private speaking room for Mac
- Record with your mic
- Capture Mac audio
- Import a file
- Choose Capture Mac audio to use it as a reference.
- When enough words reliably match, two measured practice targets
- Experimental and off by default. You can skip this step.
- AI can be wrong.
- Words can’t hear or evaluate your audio. The apostrophe is a right single quotation mark (U+2019).
- Free while in early access. No account required.
- System audio access is needed when you capture Mac audio.
- Real app captures
- Watch the film

Host, download, and share URLs:

- Host: `https://ichido-511210.web.app/` (canonical link and Open Graph URL)
- Download: `https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip`
- Share image: `https://ichido-511210.web.app/assets/ichido-share.png`

The same script also locks these exact strings:

- Record a take. Try again, or practice against a reference.
- Version 0.0.3 · Early access · macOS 26+
- Ichido is your private speaking room for Mac. Record a take, practice with a reference, and try again. (meta description)
- A real practice session (sentence-case heading)

## Copy and claims

Follow `docs/brand/messaging.md`. The page says **Listen → Understand → Repeat → Compare**. Understand is the optional language step; Words also stays in the experimental section. The app’s own reference loop remains Listen → Repeat → Compare. No accent grades, fluency guarantees, or medical claims.

Use the shared product terms from the messaging guide in headings, instructions, FAQs, and image captions. The FAQ gives short answers to practical questions; avoid internal storage details and former feature names. Keep the Ichido name, descriptor, and website headline consistent with that guide. Replace product screenshots with real captures when visible labels change.

The download URL stays `https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip`. Publish copy for a new version only after that release’s ZIP aliases and signed appcast exist. The app is ad-hoc signed and not notarized.

## Assets

- Product images are real app captures. Do not retouch labels, transcripts, replies, or measurements, and do not replace them with `build/previews` fixtures.
- `ichido-launch-film.mp4` is the launch film. The website player has no subtitle track. Do not put older Voice Coach footage back in its place, and do not present those old frames as the current interface.
- **Watch Ichido** in the hero opens the film dialog, with a direct MP4 link when JavaScript is unavailable. Closing the dialog pauses playback. The README uses a bare GitHub video-attachment URL for an inline player; repository MP4 links alone do not embed a player.
- The desktop ribbon is decorative. Mobile omits it. Reduced motion keeps the still image. Do not add a runtime dependency, microphone use, or an outbound data path.
