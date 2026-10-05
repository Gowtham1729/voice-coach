import { Easing, interpolate } from "remotion";

export type EaseFn = (t: number) => number;

export const EASE = {
  // Reveals and settles: immediate response, long quiet landing.
  out: Easing.bezier(0.16, 1, 0.3, 1),
  // The website's button curve, for small UI responses.
  ui: Easing.bezier(0.22, 1, 0.36, 1),
  // Camera moves, pushes and panel repositioning.
  inOut: Easing.bezier(0.65, 0, 0.35, 1),
  // Exits accelerate away.
  in: Easing.bezier(0.55, 0, 0.75, 0.25),
  // A hand on a trackpad: already moving, long deceleration onto the target.
  pointer: Easing.bezier(0.3, 0.4, 0.1, 1),
  linear: Easing.linear,
} as const;

const CLAMP = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;

export const ramp = (
  frame: number,
  from: number,
  to: number,
  easing: EaseFn = EASE.out,
): number => interpolate(frame, [from, to], [0, 1], { ...CLAMP, easing });

// Rises over [inAt, inAt + inDur], falls over [outAt, outAt + outDur].
export const pulse = (
  frame: number,
  inAt: number,
  outAt: number,
  inDur = 10,
  outDur = 10,
): number =>
  Math.min(
    ramp(frame, inAt, inAt + inDur, EASE.ui),
    1 - ramp(frame, outAt, outAt + outDur, EASE.in),
  );

export const lerp = (a: number, b: number, t: number): number =>
  a + (b - a) * t;

export type Point = { x: number; y: number };
export type Rect = { x: number; y: number; w: number; h: number };

export const rect = (x: number, y: number, w: number, h: number): Rect => ({
  x,
  y,
  w,
  h,
});

export const mixPoint = (a: Point, b: Point, t: number): Point => ({
  x: lerp(a.x, b.x, t),
  y: lerp(a.y, b.y, t),
});

export const mixRect = (a: Rect, b: Rect, t: number): Rect => ({
  x: lerp(a.x, b.x, t),
  y: lerp(a.y, b.y, t),
  w: lerp(a.w, b.w, t),
  h: lerp(a.h, b.h, t),
});

export const center = (r: Rect): Point => ({ x: r.x + r.w / 2, y: r.y + r.h / 2 });

export const outset = (r: Rect, d: number): Rect => ({
  x: r.x - d,
  y: r.y - d,
  w: r.w + d * 2,
  h: r.h + d * 2,
});

// A keyframe arrives at `at`, travelling for `dur` frames from the previous value.
export type Key<T> = { at: number; to: T; dur?: number; ease?: EaseFn };

export const follow = <T>(
  frame: number,
  initial: T,
  keys: readonly Key<T>[],
  mix: (a: T, b: T, t: number) => T,
): T => {
  let value = initial;
  for (const key of keys) {
    const dur = key.dur ?? 30;
    if (frame >= key.at) {
      value = key.to;
      continue;
    }
    if (dur > 0 && frame > key.at - dur) {
      const t = (key.ease ?? EASE.inOut)((frame - (key.at - dur)) / dur);
      return mix(value, key.to, t);
    }
    return value;
  }
  return value;
};

// Raw progress of the key travelling at `frame`, or null between moves.
export const inFlight = <T>(frame: number, keys: readonly Key<T>[]): number | null => {
  for (const key of keys) {
    const dur = key.dur ?? 30;
    if (frame < key.at && frame > key.at - dur) {
      return (frame - (key.at - dur)) / dur;
    }
  }
  return null;
};

// Screen placement of a crop: the crop's centre lands on (x, y) at `scale`.
export type Placement = { x: number; y: number; scale: number };

export const mixPlacement = (
  a: Placement,
  b: Placement,
  t: number,
): Placement => ({
  x: lerp(a.x, b.x, t),
  y: lerp(a.y, b.y, t),
  // Equal ratios per frame read as constant zoom speed.
  scale: a.scale * Math.pow(b.scale / a.scale, t),
});

export type Sized = { w: number; h: number };

export const toScreen = (crop: Sized, p: Placement, r: Rect): Rect => ({
  x: p.x + (r.x - crop.w / 2) * p.scale,
  y: p.y + (r.y - crop.h / 2) * p.scale,
  w: r.w * p.scale,
  h: r.h * p.scale,
});

export const pointToScreen = (crop: Sized, p: Placement, pt: Point): Point => ({
  x: p.x + (pt.x - crop.w / 2) * p.scale,
  y: p.y + (pt.y - crop.h / 2) * p.scale,
});

// Placement that keeps crop point `pt` on screen point `at` at the given scale.
export const anchorAt = (
  crop: Sized,
  pt: Point,
  at: Point,
  scale: number,
): Placement => ({
  x: at.x - (pt.x - crop.w / 2) * scale,
  y: at.y - (pt.y - crop.h / 2) * scale,
  scale,
});
