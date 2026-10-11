// Segment lengths and the transition that leads into each one. Scenes overlap
// for the length of their entering transition, so starts are derived below.
export const SEGMENTS = [
  // 0:00–0:06.5. The picker push (enter 56) begins at frame 390.
  { id: "opening", title: "Learn a phrase", dur: 446, enter: 0 },
  { id: "picker", title: "Bring a clip", dur: 360, enter: 56 },
  { id: "listen", title: "Listen, understand, repeat", dur: 740, enter: 40 },
  // Measured notes and "One more take" land with the read, then the push.
  { id: "compare", title: "Compare and choose", dur: 740, enter: 40 },
  { id: "recording", title: "Your own voice, too", dur: 300, enter: 40 },
  { id: "privacy", title: "Private on your Mac", dur: 822, enter: 40 },
  { id: "cta", title: "Get Ichido", dur: 420, enter: 60 },
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
  START.cta + SEGMENTS[SEGMENTS.length - 1].dur;
