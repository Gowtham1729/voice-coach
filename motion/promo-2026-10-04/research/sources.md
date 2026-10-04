# Research and source record

Accessed 4 October 2026. External sources inform workflow; Ichido claims come from the product source and real captures. Creative choices such as runtime, font sizes, pulse range and shot allocations are our draft recommendations, not research findings.

| Source | Finding applied | Practical effect |
| --- | --- | --- |
| [Movez's linked article](https://x.com/0xMovez/article/2104216919033192746) | Real assets, shot states, deterministic rendering, sound planning and visual critique | See `article_notes.md` for the bounded adaptation and access limits |
| [School of Motion: project workflow](https://connect.schoolofmotion.com/hubfs/Email%20Images/Bring%20Your%20Ideas%20To%20Life%20Workshop/Bring_Your_Ideas_To_Life.pdf) | A brief, script, references, storyboard, style frames, animatic and audio are distinct preparation stages | Provide explicit preproduction documents instead of a single animation prompt |
| [School of Motion: completing a motion design project](https://schoolofmotion.com/blog/guide-completing-motion-design-project) | An animatic exposes timing and pacing problems before expensive polish | Later agent should test the whole story at low fidelity before final motion |
| [Remotion: animating properties](https://www.remotion.dev/docs/animating-properties) | Animations should derive from frame time; time-based CSS transitions can flicker | Deterministic animation contract |
| [Remotion: spring](https://www.remotion.dev/docs/spring) | Frame-based physics parameters support controlled settling | Tune motion in playback; no unvalidated universal preset |
| [Remotion: assets](https://www.remotion.dev/docs/assets) | Browser-rendered media must be reachable through public assets and supported components | Copy only selected production assets to public during implementation |
| [Remotion: fonts](https://www.remotion.dev/docs/fonts) | Local fonts can load through FontFace with render waiting | Use existing font files; prevent fallback at render time |
| [Remotion: Video](https://www.remotion.dev/docs/media/video) | Current component supports controlled media timing | Only relevant to future fresh capture clips; check pinned version API |
| [W3C: planning audio/video](https://www.w3.org/WAI/media/av/planning/) | Plan captions, descriptions and transcripts with the media | Final VO captions, usable chapter labels and text transcript |
| [Live Ichido site](https://voice-coach-studio.gowtham.chatgpt.site/) | Current brand, story, product captures and historical tour status | Cobalt/paper direction and a new combined launch/walkthrough film |

## Local primary sources inspected

`AGENTS.md`, `README.md`, `docs/brand/messaging.md`, `docs/marketing-website.md`, `docs/PEEKABOO.md`, all screenshots through a product contact sheet and selected full-size views, `website/index.html`, `website/styles.css`, `website/app.js`, `website/assets/tour-captions.vtt`, font licenses, the wordmark SVG, and `scripts/check-website.mjs`.

Selected code paths: `Sources/VoiceCoachCore/Coaching/CoachingPlan.swift`, `Sources/VoiceCoachCore/Mimic/MimicComparison.swift`, `Sources/VoiceCoachApp/Features/Mimic/MimicComparisonView.swift`, its chart/timing extensions, `MimicReferencePicker.swift`, and Take/transcript source searches. These support feature boundaries; no build, live audio or efficacy validation was inferred from reading them.

Existing Remotion setup: `motion/README.md`, `package.json`, `src/Root.tsx`, `src/Composition.tsx`, `remotion.config.ts`. The source still contains the user's 5-second paper-background starter composition.

The live site was successfully opened and visually inspected in the browser after the web reader failed. Its headline, palette, Words qualification, privacy statement and earlier-tour wording agree with local source. Deployment SHA was not queried and is not asserted.
