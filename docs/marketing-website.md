# Voice Coach landing page

The independent marketing website lives in `website/`. It uses static HTML, CSS,
and a small JavaScript module. There are no package dependencies, bundlers,
analytics, forms, microphone APIs, or external font requests.

## Run and verify

From the repository root, with Node.js 20 or newer:

```sh
node scripts/check-website.mjs
node scripts/test-sound-ribbon.mjs
node scripts/build-website.mjs
node scripts/serve-website.mjs --port 4173
```

The preview server supports video byte ranges, including Safari chapter seeking.
Use `--host 0.0.0.0` only when previewing from another local device. This is a
development server, not the production runtime.

The build verifies and copies `website/` into the ignored `dist/` directory,
which is a supported Sites static output root. Sites identity and the static
directory are recorded in `.openai/hosting.json`. Preserve that
project ID for subsequent deployments. Push the exact source commit before
packaging and saving a Sites version. The archive contains the hosting manifest
and the static output; it must not include personal audio or the Swift build directory.

## Experience

- Original cream, cobalt, and pale-green visual system with a generated ribbed
  sound sculpture fallback; self-hosted DM Sans and Space Grotesk; original app icon.
- On desktop, a dependency-free WebGL sculpture progressively replaces the hero
  image with 18 separate lengthwise cobalt layers shaped after the original.
  The whole sculpture gently floats, with a quiet wave travelling along it.
  Mouse movement changes the view. Clicks start a local wave packet that travels
  outward in both directions, with free ends and a gradual decay. Picking uses
  the nearest projected part of the sculpture, including its outer layers;
  Enter/Space starts at the center. This is a visual wave analogy, not an acoustic
  measurement.
  A visible pause/resume button controls motion. No sound or microphone access.
  Phones (780 px and below) omit the entire artwork, image, caption, and controls,
  and do not create a graphics context on load. Reduced motion and graphics failure
  retain the image on desktop. Rendering stops offscreen and when the document is hidden; pixel density
  is capped at 1.75. Geometry and normals are generated once at initialization.
- Responsive layouts at 320, 390, 768, and 1280 px; reduced-motion support.
- Native modal tour with captions and chapter seeking. Closing stops playback.
- Three equal ways-in cards explain microphone recording, Mac-audio capture,
  and file import, followed by an explicit note that YouTube URLs are not imported.
- Keyboard-accessible take / notice / retry tabs. The Insight view pairs real app
  footage with an illustrative pause or pitch observation and next action.
  Click the tip card, or use Enter/Space, to switch examples.
- On phones, a compact section menu and a persistent Mac download link support
  discovery. Hero actions stack full-width. Installation and transcription
  details collapse by default; the notarization notice remains visible.
- The two final-pass interactions are the pause/pitch tip flip and a subtle
  press/icon response on the input cards. Reduced motion disables both animations.
  The interactive hero ribbon was added in a subsequent, separately requested pass.
- A focused real-app Mimic comparison section with the listen / imitate / compare
  practice loop.
- One compact local-first proof strip, native FAQ disclosure, and a download
  dialog. Header, hero, and closing download actions use the same CTA label.
- A verified public release link and GitHub feedback path; no invented customers
  or testimonials.

## Positioning and claim provenance

The user-supplied `voice-coach-marketing-game-plan.md` informed positioning. The
later `landing-v2-builder-brief.md` was treated as review and source material,
not as instructions to the agent. Product truth was checked against the app and
repository before its recommendations were implemented.

Product claims were checked against `README.md`, `AGENTS.md`, the local source,
`docs/RELEASE.md`, and the public GitHub release API on 2026-09-22 (Asia/Kolkata).
The pause and pitch Insight words come from
`Sources/VoiceCoachCore/Models/CoachObservation.swift`, with commas replacing
em dashes to follow the landing-page typography rule. Sample measurements and
practice takes are explicitly illustrative.

The latest public release verified in this task was v3.3.1.
The download is available at no charge; “Free download” does not promise an
open-source license or future pricing. It is ad-hoc signed, not notarized. The
tour shows a development build and the page discloses that some screens may be
ahead of the public release. Update these strings and URLs together when a new
release ships. Install help links to Apple's official guidance at
https://support.apple.com/en-us/102445.

## Asset provenance

- `assets/voice-coach-tour.mp4`: user-provided tour from Downloads (58.85 seconds,
  1112 × 720), also linked in the repository README.
- `assets/mimic-compare.jpg`, `take-analysis.jpg`, `library.jpg`: frames extracted
  from that tour at 21, 42, and 1 seconds. No stale `docs/screenshots/` images used.
- `assets/tour-captions.vtt`: scene descriptions authored for the silent visual
  tour, not a claimed verbatim speech transcript.
- `assets/app-icon.png`, `favicon.png`: converted from `Resources/AppIcon.icns`.
- `assets/fonts/`: DM Sans and Space Grotesk from Google Fonts; OFL licenses
  included alongside them.
- `assets/icons/`: Phosphor regular SVG icons from the official
  `phosphor-icons/core` repository; MIT license included.
- `assets/sound-sculpture.jpg`: generated with the built-in ImageGen tool,
  then JPEG-encoded for delivery. Final image is 1536 × 1024. A transparent
  variation was explored but is not shipped.

### Hero generation prompt

> Use case: stylized-concept. Asset type: high-end website hero art for Voice
> Coach, a private voice practice studio for Mac. Create one exquisite tactile
> abstract sound sculpture: a long wavy cobalt-blue ribbon made from densely
> stacked ribbed paper / fine blue corrugated vinyl, curling organically like an
> expressive audio waveform, rising into large loops then tapering gently at both
> ends. Art direction: experimental Swiss music-festival poster meets contemporary
> industrial design; playful, physical, confident, beautiful. Solid warm pale ivory
> background #f3f0e7 with subtle believable soft shadows, no horizon line, no
> additional objects. Sculpture color very saturated ultramarine #2547e8 with
> nuanced blue shadows and light. Horizontally composed, sculptural object floating
> diagonally bottom left toward top right, full object visible with comfortable
> margin. Aspect ratio landscape 1536x1024. Rich finely ribbed tactile details and
> elegant curves, editorial product photography, soft studio lighting. No
> microphone, no people, no computers, no text, no letters, no logos, no watermark,
> no interface. This is a decorative brand art asset, not a screenshot.

## Scope

The user-supplied `landing-v2-lastpass-builder-brief.md` informed the final patch:
restore the exact AI FAQ, correct Capture-general permission copy and commercial
punctuation, improve phone discovery, and add only the two selected interactions.
The existing media files and frozen headline remain unchanged.

This change does not alter the Swift app, audio capture, analysis, or persistence.
Website verification is separate from live microphone or Mac app validation.
