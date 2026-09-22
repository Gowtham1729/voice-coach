# Landing page v2 verification

Date: 2026-09-22. Final result: passed.

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
