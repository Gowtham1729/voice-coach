# Ichido marketing website

`website/` is the static marketing source for the native macOS app. The existing
public Site is https://voice-coach-studio.gowtham.chatgpt.site/; its URL is retained
through the rebrand. `.openai/hosting.json` points to the same Sites project and
`dist` output. The website does not record, analyse audio, or require an account.

## Product story and visual system

Ichido is **Your private speaking room**. The hero says **Your words. Your voice.
One more try.** The website explains **Listen → Understand → Repeat → Compare**.
Understand is optional, experimental language help; the app's ordinary reference
loop remains Listen → Repeat → Compare. Ordinary recordings show measurements;
reliably matched reference attempts can receive two measured practice targets.
There are no accent grades, phoneme scores, fluency guarantees, or medical claims.

Cobalt, warm paper, the ribbon mark, DM Sans, and Space Grotesk carry the existing
identity forward. The desktop hero retains the dependency-free interactive ribbon:
pointer movement, click/Enter/Space waves, and a pause/resume control. Mobile omits
the artwork and graphics context; reduced motion retains the still image. Rendering
stops offscreen and when hidden. The ribbon is decorative, not acoustic evidence.

Four accessible tabs demonstrate the reference workflow. Every screenshot opens
in a native dialog, with an original-image link, Escape dismissal, and return focus.
Words has a real language-inspector inset displayed through CSS, with the unchanged
full screenshot available. Input cards explain mic recording, Mac-audio capture,
and file import. Privacy, language/model requirements, experimental limitations,
installation details, and the transition from Voice Coach are visible in the FAQ
and download dialog. The silent earlier tour remains explicitly labelled historical.

## Product truth

Audio, acoustic analysis, supported transcription, translation, and experimental
language chat run on the Mac. Update checks and optional model downloads use the
network. There is no recording upload path or telemetry. Clipboard export to an
external AI service is a separate, explicit user action.

Apple supports selected on-device speech languages, with model downloads as needed.
The optional Parakeet v3 recognizer supports 25 European languages automatically;
it does not support Japanese. Words requires available Apple Intelligence, works
with text, can be wrong, cannot evaluate audio, and clears conversations on quit.

The early-access app is ad-hoc signed and not Apple-notarized. The stable download
is `/releases/latest/download/Ichido-macOS.zip`. The identical legacy
`Voice-Coach-macOS.zip` alias and existing Sparkle identity/feed are preserved.
Publish the new version copy only after the corresponding release assets exist.

## Asset provenance

- `reference-practice.jpg`, `repeat-practice.jpg`: actual rebuilt Ichido app,
  existing French reference session, captured using macOS controls on 2026-10-04.
  Both show the ready Practice view; neither pretends a recording is in progress.
- `language-chat.jpg`: actual rebuilt Ichido app, Apple on-device response to
  “What does this French transcript mean in English? Explain ‘déréglée’ too.”
  The meaning and vocabulary response is real, not a seeded fixture or generated
  screenshot. It does not establish general language accuracy.
- `mimic-compare.jpg`: user-supplied live English comparison capture, showing
  matched relative pitch and two practice targets. Earlier Mimic/Ask labels are
  disclosed. `word-explanation.jpg` and `reference-analysis.jpg` retain the user's
  additional live captures as supporting marketing assets.
- `take-analysis.jpg`, `library.jpg`: current live app screenshots from
  `docs/screenshots/07-take.png` and `02-library.png` on main at `57c9bf8` (#68).
- Screenshot JPEG encoding preserves the original interface and measurements.
  No screen labels, transcripts, replies, or acoustic results were retouched.
  Rendered synthetic fixtures are used for layout checks, not website product media.
- `tour-poster.jpg`: retained earlier tour frame. `voice-coach-tour.mp4` is the
  user-provided 58.85-second tour; its caption track describes scenes rather than
  inventing a verbatim speech transcript.
- `ichido-share.png`: 1200 × 630 export of the code-native
  `brand/share-card.html`, with exact type and the existing decorative sculpture.
  `ichido-wordmark.svg` is the editable type-based wordmark source.
- `app-icon.png`, `favicon.png`, `brand-mark.png`: existing cobalt ribbon identity.
- `sound-sculpture.jpg`: existing ImageGen-created decorative cobalt sculpture,
  1536 × 1024. The rebrand reuses it rather than replacing it.
- `fonts/`: locally served DM Sans and Space Grotesk, with OFL licenses.
- `icons/`: Phosphor regular SVG icons, with MIT license.

## Build and verification

```sh
node scripts/check-website.mjs
node scripts/test-sound-ribbon.mjs
node scripts/build-website.mjs
node scripts/serve-website.mjs --port 4173
```

The checker verifies asset and anchor references, unique IDs, ARIA targets, four
workflow tabs, download routing, product boundaries, JavaScript syntax, and absence
of external scripts/audio capture/analytics. Browser QA covers screenshot/download
modals, return focus, tabs with arrows/Home/End, mobile navigation, FAQ, video
chapters, responsive overflow, and ribbon controls. App contracts, bundled signing,
persistence fixtures, real navigation/language help, and system appearance are
verified separately; website checks do not establish hardware audio accuracy.

Source history was compared with the existing hosted Site before edits. The Site
had no unique website changes to preserve. Publish only the exact pushed source
SHA and its matching archive, preserve the public audience, require deployment
status `succeeded`, then check the live page, assets, and download destination.

The new launch campaign, motion design, and demo video are the next phase.
