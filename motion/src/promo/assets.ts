import { staticFile } from "remotion";
import { rect, type Rect } from "./motion";

const file = (path: string) => staticFile(`promo-2026-10-04/${path}`);

// Every rectangle is in source pixels of the unresized crop (see
// promo-2026-10-04/assets/components/crop-map.json). Bounds were measured by
// flood-filling each control's own fill, so focus rings sit on the real edges.
const crop = <K extends string>(
  path: string,
  w: number,
  h: number,
  bg: string,
  at: Record<K, Rect>,
) => ({ src: file(path), w, h, bg, at });

export type Crop = ReturnType<typeof crop>;

export const UI = {
  homeActions: crop("ui/home-actions.png", 830, 85, "#27212b", {
    import: rect(28, 23, 194, 48),
    referencePractice: rect(246, 22, 352, 50),
    record: rect(623, 25, 178, 44),
  }),
  referenceInputs: crop("ui/reference-inputs.png", 650, 155, "#232027", {
    import: rect(22, 25, 243, 50),
    capture: rect(289, 26, 330, 48),
  }),
  practiceCard: crop("ui/practice-card.png", 2110, 670, "#1e1e1e", {
    label: rect(58, 57, 128, 15),
    transcript: rect(57, 156, 1946, 211),
    styleControl: rect(271, 484, 476, 48),
    listenRepeat: rect(271, 485, 236, 46),
    speakAlong: rect(503, 484, 244, 48),
    helper: rect(59, 592, 549, 22),
  }),
  practiceActions: crop("ui/practice-actions.png", 570, 80, "#242424", {
    listen: rect(28, 10, 127, 56),
    start: rect(177, 16, 212, 44),
    record: rect(412, 10, 138, 56),
  }),
  comparePitch: crop("ui/compare-pitch.png", 2110, 840, "#201d26", {
    title: rect(45, 54, 128, 15),
    modes: rect(1546, 38, 495, 48),
    pitch: rect(1546, 38, 165, 48),
    timing: rect(1711, 38, 165, 48),
    emphasis: rect(1878, 38, 163, 48),
    plot: rect(30, 190, 2050, 380),
    legend: rect(45, 775, 256, 15),
    aboutLabel: rect(673, 686, 67, 24),
    aboutColumn: rect(631, 196, 149, 526),
  }),
  practiceNext: crop("ui/practice-next.png", 630, 640, "#1e1e1e", {
    header: rect(12, 25, 212, 15),
    first: rect(0, 70, 630, 268),
    second: rect(0, 383, 630, 232),
  }),
  tryAgain: crop("ui/try-again.png", 630, 65, "#1e1e1e", {
    button: rect(13, 13, 614, 44),
  }),
  takeSelector: crop("ui/take-selector.png", 265, 65, "#201d26", {
    control: rect(40, 13, 212, 42),
  }),
  takeWords: crop("ui/take-words.png", 1220, 71, "#232323", {
    w0: rect(6, 9, 186, 54),
    w1: rect(210, 9, 187, 54),
    like: rect(415, 9, 186, 54),
    w3: rect(619, 9, 187, 54),
    w4: rect(824, 9, 186, 54),
    w5: rect(1028, 9, 186, 54),
  }),
};

// Words inspector from the 2026-10-05 screen recording, one plate per captured
// state (scripts/make-words-plates.py). Every plate shares this card geometry.
export const WORDS = {
  w: 680,
  h: 1186,
  bg: "#1b1b1b",
  plates: {
    idle: file("ui/words-idle.png"),
    menu: file("ui/words-menu.png"),
    filled: file("ui/words-filled.png"),
    thinking: file("ui/words-thinking.png"),
    answer: file("ui/words-answer.png"),
  },
  // Suggested questions items, highlighted, stacked in menu order.
  rows: { src: file("ui/words-menu-rows.png"), at: rect(32, 808, 360, 44), count: 4 },
  // One recorded frame per 48 px cell, about 30 fps.
  spinner: { src: file("ui/words-spinner.png"), at: rect(62, 320, 48, 48), frames: 60, fps: 30 },
  at: {
    suggested: rect(32, 996, 302, 40),
    send: rect(574, 1056, 74, 44),
    glosses: rect(33, 605, 347, 115),
  },
};

// Full captures with their own rounded window corners (~31 px at source scale).
export const PRODUCT = {
  home: {
    src: file("product/01-home.png"),
    w: 3420,
    h: 2146,
    radius: 31,
    at: {
      homeActions: rect(2220, 350, 830, 85),
    },
  },
  picker: {
    src: file("product/09-new-mimic.png"),
    w: 1360,
    h: 1280,
    radius: 31,
    bg: "#231d29",
    at: {
      import: rect(382, 645, 243, 50),
      capture: rect(649, 646, 330, 48),
      inputs: rect(360, 620, 650, 155),
    },
  },
};

export const BRAND = {
  ribbon: { src: file("brand/brand-mark.png"), w: 800, h: 330 },
  arrowDown: file("icons/arrow-down.svg"),
};
