# Interaction layers

Original editable SVG assets prepared for this promo. `cursor.svg` is a stylized pointer, not a pixel-perfect system cursor. Its hotspot is `(9,5)` in a 48×64 viewBox. At 1080p, start with 28 px width. `click-ring.svg` is a separate editorial click cue; start near 44 px diameter and use sparingly. `focus-outline.svg` marks the component being explained; rebuild its rectangle at the target dimensions to keep the 2 px stroke, rather than stretching the entire SVG.

These layers belong above faithful component crops. They are annotations, not captured app states. Animate their transforms later from frame time. A cursor click requires a verified next state in `interaction_plan.json`; otherwise use a hover/focus hold and the specified fallback. Do not add fake loading, recording, selected-word or success states.
