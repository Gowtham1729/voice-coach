# Marketing website

`website/` is the static site for the Mac app. The public URL is https://voice-coach-studio.gowtham.chatgpt.site/ and stays that address through the rebrand. `.openai/hosting.json` publishes the `dist` directory. The site does not record, analyse audio, or require an account.

## Check and build

```sh
node scripts/check-website.mjs
node scripts/test-sound-ribbon.mjs
node scripts/build-website.mjs
node scripts/serve-website.mjs --port 4173
```

`check-website.mjs` is the contract, and it is not part of CI job `test`. It checks local assets, unique IDs, ARIA targets, four workflow tabs, the latest-release download with no pinned version, no external scripts, no capture or analytics APIs, no em dashes, and the exact strings in its `requiredCopy` array. Change one of those sentences only by editing `website/index.html` and the checker in the same change. Browser checks for dialogs, focus return, tabs, the mobile menu, FAQ, video chapters, overflow, and the ribbon are separate from that script. Neither those checks nor `check-website.mjs` prove app contracts, signing, persistence, language accuracy, or hardware audio.

## Copy and claims

Follow `docs/brand/messaging.md`. The page says **Listen → Understand → Repeat → Compare**. Understand is the optional language step. The app’s own reference loop remains Listen → Repeat → Compare. No accent grades, fluency guarantees, or medical claims.

Use the shared product terms from the messaging guide in headings, instructions, FAQs, and image captions. The FAQ gives short answers to practical questions; avoid internal storage details and former feature names. Keep the Ichido name, descriptor, and website headline consistent with that guide. Replace product screenshots with real captures when visible labels change.

The download URL stays `https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip`. Publish copy for a new version only after that release’s ZIP aliases and signed appcast exist. The app is ad-hoc signed and not notarized.

## Assets

- Product images are real app captures. Do not retouch labels, transcripts, replies, or measurements, and do not replace them with `build/previews` fixtures.
- `voice-coach-tour.mp4` is earlier Voice Coach footage. Keep it labelled historical. Do not present those frames as the current Ichido interface. The caption track may describe scenes. Do not rewrite it as a verbatim speech transcript.
- The desktop ribbon is decorative. Mobile omits it. Reduced motion keeps the still image. Do not add a runtime dependency, microphone use, or an outbound data path.
