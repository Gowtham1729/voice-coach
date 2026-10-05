// Segment lengths and the transition that leads into each one. Scenes overlap
// for the length of their entering transition, so starts are derived below.
export const SEGMENTS = [
  { id: "opening", title: "One more try", dur: 322, enter: 0 },
  { id: "picker", title: "Bring a clip", dur: 360, enter: 56 },
  { id: "listen", title: "Listen, understand, repeat", dur: 740, enter: 40 },
  { id: "compare", title: "Compare and choose", dur: 1000, enter: 40 },
  { id: "recording", title: "Your own voice, too", dur: 350, enter: 40 },
  { id: "privacy", title: "Private on your Mac", dur: 824, enter: 40 },
  // The finished read runs past the end card, so the card holds to the last word.
  { id: "cta", title: "Get Ichido", dur: 473, enter: 60 },
] as const;

export type SegmentId = (typeof SEGMENTS)[number]["id"];

export const START = SEGMENTS.reduce(
  (acc, seg, i) => {
    const prev = i === 0 ? null : SEGMENTS[i - 1];
    acc[seg.id] = prev === null ? 0 : acc[prev.id] + prev.dur - seg.enter;
    return acc;
  },
  {} as Record<SegmentId, number>,
);

export const DURATION =
  START.cta + SEGMENTS[SEGMENTS.length - 1].dur; // 3793 frames, 63.2 s
