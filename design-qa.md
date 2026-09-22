# Landing page v2 verification

Date: 2026-09-22. Final result: passed.

## Final-pass verification

The final review was implemented and inspected at 390 x 844, 320 x 740,
and 1280 x 800 in the local browser preview.

- Frozen H1 retained verbatim. AI speech coach FAQ matches the supplied Q/A.
  Capture permission copy applies generally. The dialog separates the platform
  and exact early-access sentence into paragraphs. No em dashes in HTML or JS.
- At 390 px, both hero CTAs are 350 px wide and at least 52 px high. At 320 px,
  they are 280 px wide and at least 52 px high. Document width equals viewport
  width at both phone sizes; no main-content element extends beyond 320 px.
- All three input cards use the same cream background. The YouTube explanation
  occupies the full width below the stack.
- Mobile menu opens and closes after navigating. FAQ expands to the exact AI
  answer. The persistent Mac download link reaches the download section.
- Install details collapse on phones and expand on desktop. Notarization honesty
  stays visible. Expanded instructions include the general system-audio line.
- Mimic art starts at the 20 px mobile gutter and keeps its aspect ratio.
  Walkthrough screenshots use a bounded crop on phones, with full images on desktop.
- Phone tour dialog is 590 px tall at 390 x 844, with a 201 px video and 44 px
  chapter buttons. Seeking to Analysis reaches 36 seconds; closing pauses playback.
- Tip flip works by click, native Return, and Space, showing one example at a time.
  The only new decorative motions are tip flip and input-card press/icon breathing.
  The loaded reduced-motion stylesheet explicitly disables both new animations
  and card translation. The OS motion preference was not changed during QA.
- Browser error log was empty during the checked interactions. Website checks,
  build, and whitespace validation pass. Existing media files were not changed.

The v2 page keeps the original cream, cobalt, and pale-green visual identity
while replacing the poetry-first sequence with a clarity-first conversion path:
hero, three ways to start, Insights, Mimic, one privacy proof strip, FAQ, and
download. The user-supplied v2 brief was treated as review material. Claims were
checked against the app and repository before implementation.

## Visual review

- Desktop: inspected at 1280 x 720. The product, platform, privacy posture,
  primary action, and tour action are visible in the first viewport.
- Mobile: inspected at 390 x 844 and 320 x 740. Hero copy, entry cards, Insights,
  Mimic, tour dialog, and download disclosure remain readable and usable.
- Typography: self-hosted DM Sans and Space Grotesk load correctly. Georgia
  italic is limited to the brand accent in the hero and Insights heading.
- Assets: the hero retains the generated ribbed sound sculpture. Insights and
  Mimic use real frames from the supplied app tour at their native aspect ratio.
- Layout: section grids collapse to a single column without clipped copy or
  controls. The illustrative Insight card remains legible at the narrow
  breakpoint.
- Copy: the exact v2 hero, ways-in, honesty, Insight, privacy, and early-access
  strings are present. Landing-page copy contains no em dashes.

## Interaction checks

- Take / notice / retry tabs update selected state, panel content, and
  aria-labelledby; arrow keys, Home, and End are supported.
- Tour opens, plays, seeks by chapter, and pauses when closed.
- FAQ disclosure expands and closes other answers.
- Download actions open the install disclosure. The release link and direct ZIP
  target v3.2.0.
- Native modal Escape and focus behavior remain available through the dialog
  element.
- Browser console inspection found no page errors during the checked flows.

## Automated evidence

- node scripts/check-website.mjs: local references, unique IDs, ARIA targets,
  JavaScript syntax, no external scripts, no recording or analytics APIs,
  required v2 copy, banned claims, and the no-em-dash rule passed.
- node scripts/build-website.mjs: passed and rebuilt the Sites dist output.
- git diff --check: passed.
- GitHub's release API confirmed v3.2.0 and
  Voice-Coach-3.2.0-macOS.zip (2,157,070 bytes).

## Product limits

The website does not record, analyze, or upload audio. The Swift application was
not modified or rebuilt. Its live microphone, system-audio, and analysis behavior
remain outside this landing-page verification. The public app release is ad-hoc
signed and not Apple-notarized.
