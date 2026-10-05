import { measureText } from "@remotion/layout-utils";
import type { Point, Rect } from "./motion";
import { BRAND } from "./assets";
import { METRICS, STACK, TRACKING, WEIGHT, type FontRole } from "./theme";

export const textWidth = (
  text: string,
  role: FontRole,
  size: number,
  tracking = 0,
): number =>
  measureText({
    text,
    fontFamily: STACK[role],
    fontSize: size,
    fontWeight: String(WEIGHT[role]),
    letterSpacing: `${tracking}em`,
  }).width;

// Top of a line-height:1 text box whose first baseline sits at `baseline`.
export const topForBaseline = (
  baseline: number,
  size: number,
  role: FontRole = "display",
  lineHeight = 1,
): number => baseline - (METRICS[role].baseline + (lineHeight - 1) / 2) * size;

// Centre of the cobalt period that follows `text` set at (left, baseline).
export const periodAfter = (
  text: string,
  left: number,
  baseline: number,
  size: number,
  tracking: number,
  role: FontRole = "display",
): { at: Point; radius: number } => {
  const m = METRICS[role];
  return {
    at: {
      x: left + textWidth(text, role, size, tracking) + (m.dotLead + m.dot / 2) * size,
      y: baseline - m.dotLift * size,
    },
    radius: (m.dot / 2) * size,
  };
};

const RIBBON_RATIO = BRAND.ribbon.h / BRAND.ribbon.w;

export type Lockup = {
  size: number;
  baseline: number;
  ribbon: Rect;
  wordLeft: number;
  wordWidth: number;
  dot: Point;
  dotRadius: number;
};

// Website wordmark proportions: ribbon 2em wide, 10/24 em gap, -0.04em tracking.
export const lockup = (size: number, cx: number, baseline: number): Lockup => {
  const m = METRICS.display;
  const ribbonW = 2 * size;
  const ribbonH = ribbonW * RIBBON_RATIO;
  const gap = (10 / 24) * size;
  const word = textWidth("ichido", "display", size, TRACKING.chapter);
  const total = ribbonW + gap + word + (m.dotLead + m.dot) * size;
  const left = cx - total / 2;
  const wordLeft = left + ribbonW + gap;
  return {
    size,
    baseline,
    ribbon: {
      x: left,
      y: baseline - 0.346 * size - ribbonH / 2,
      w: ribbonW,
      h: ribbonH,
    },
    wordLeft,
    wordWidth: word,
    dot: {
      x: wordLeft + word + (m.dotLead + m.dot / 2) * size,
      y: baseline - m.dotLift * size,
    },
    dotRadius: (m.dot / 2) * size,
  };
};

// Opening phrase row: small ribbon, then "One more try" and its period.
export const OPENING = {
  phraseSize: 140,
  phraseBaseline: 590,
  ribbonScale: 1.3,
  lockupSize: 120,
  lockupBaseline: 548,
};

export const openingRow = () => {
  const { phraseSize: size, phraseBaseline: baseline, ribbonScale } = OPENING;
  const m = METRICS.display;
  const ribbonW = ribbonScale * size;
  const ribbonH = ribbonW * RIBBON_RATIO;
  const gap = 0.32 * size;
  const phrase = textWidth("One more try", "display", size, TRACKING.opening);
  const total = ribbonW + gap + phrase + (m.dotLead + m.dot) * size;
  const left = 960 - total / 2;
  const phraseLeft = left + ribbonW + gap;
  return {
    size,
    baseline,
    ribbon: {
      x: left,
      y: baseline - 0.346 * size - ribbonH / 2,
      w: ribbonW,
      h: ribbonH,
    },
    phraseLeft,
    dot: {
      x: phraseLeft + phrase + (m.dotLead + m.dot / 2) * size,
      y: baseline - m.dotLift * size,
    },
    dotRadius: (m.dot / 2) * size,
  };
};

export const openingLockup = () =>
  lockup(OPENING.lockupSize, 960, OPENING.lockupBaseline);

export const CTA = { size: 120, baseline: 440 };

export const ctaLockup = () => lockup(CTA.size, 960, CTA.baseline);

export const RECORDING_HEADLINE = {
  text: "Record yourself, too.",
  left: 96,
  baseline: 330,
  size: 104,
};

export const recordingPeriod = () =>
  periodAfter(
    "Record yourself, too",
    RECORDING_HEADLINE.left,
    RECORDING_HEADLINE.baseline,
    RECORDING_HEADLINE.size,
    TRACKING.chapter,
  );
