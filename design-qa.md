# Landing page verification

Date: 2026-09-22. Final result: passed.

This is an original landing-page design, not a reproduction of a supplied page
mockup. Visual grounding: the user-provided app tour and extracted frames in
`website/assets/`, plus the generated sound sculpture at
`website/assets/sound-sculpture.jpg` (1536 × 1024). Product screenshot source
dimensions are 1112 × 720. App images preserve their native aspect ratio.

Implementation evidence: browser-rendered screenshots captured in this task's
Codex in-app browser, at the local preview on port 4175. These are recorded in the
conversation, not saved as repository screenshot files. Inspected the hero,
practice/Insight panel, tour, privacy section, and download modal. Screenshot
capture used the browser viewport API; no mock browser images were substituted.

## Visual review

- Typography: self-hosted DM Sans and Space Grotesk load correctly. Georgia italic
  supplies the editorial accent. Desktop and phone headings wrap without clipping.
- Layout: checked 1280 × 720, 1280 × 900, 768 × 1024, 390 × 844, and 320 × 740 CSS
  viewports. Document width equals viewport width. The native screenshot method
  initially cropped a resized tablet capture; a direct viewport screenshot and
  DOM geometry confirmed the actual 768 px layout correctly.
- Color: cream/cobalt/lime tokens remain consistent through the page; selected,
  hover, and keyboard-focus states are distinguishable.
- Assets: real tour stills retain aspect ratio; the hero uses the generated
  sculpture rather than a code-drawn approximation. Fonts, icons, and video are
  local site assets. The source app icon is reused.
- Copy: the exact pause Insight matches the Swift source. Walkthrough data is
  labeled illustrative. No customer testimonials or invented performance scores.
  Download and tour disclose the public-release/development-build distinction.

## Iterations resolved

1. Hero art caused desktop horizontal overflow. Reduced art width and contained
   decorative overflow; verified 1280/1280 and 390/390 document/viewport widths.
2. The hero's ivory image background became a visible rectangle with multiply
   blending. Changed to darken blending; the final saturated ribbon integrates
   with the paper background without the rectangle.
3. A mobile decorative caption overlapped the tour action. Put mobile artwork
   after the copy in normal document flow; rechecked at 390 and 320 px.
4. The initial Python server did not support reliable Safari video seeking.
   Added a dependency-free server with byte-range responses. Verified chapter
   seek at 18.215 seconds, readyState 4, duration 58.85 seconds, playing.
5. Added explicit whitespace when the FAQ heading's line break is hidden on
   mobile. Download links now open the install modal directly, retaining their
   anchor fallback without JavaScript.

## Interaction checks

- Record → notice → retry → record progression; selected states and panel labels.
- Arrow-key practice tabs and native tab focus.
- Compare / Analysis / Library image changes and pressed states.
- Talk / pitch / interview scenario switching.
- Tour opens, plays, seeks, displays scene captions, and pauses on close.
- Native modal Escape behavior and focus return.
- Privacy disclosure opens and closes; FAQ expands with its answer.
- Header/hero download → install disclosure → correct public ZIP URL.
- Public ZIP URL verified through GitHub API and HTTP redirect.
- Browser console: no warnings or errors in the tested run.
- `node scripts/check-website.mjs`: 37 references, 35 unique IDs, valid ARIA
  targets, JavaScript syntax, and no external scripts or recording APIs.
- `git diff --check`: passed.

## Remaining limits

Responsive checks used browser viewport emulation, not physical phones. The
Swift application was not modified or rebuilt. Its microphone, system audio,
and analysis behavior are outside this website validation. The existing public
app release remains ad-hoc signed and not notarized. Sites audience remains
owner-private unless the user requests a sharing change.
