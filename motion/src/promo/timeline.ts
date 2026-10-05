import { VIDEO } from "./theme";

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

// Storyboard scene boundaries: the midpoint of each joining move, or the
// in-scene camera move that changes the subject.
export const STORY = [
  { id: "S01", title: "One more try", from: 0 },
  { id: "S02", title: "Bring a clip", from: 160 },
  { id: "S03", title: "Listen", from: START.listen + 20 },
  { id: "S03b", title: "Understand the words", from: START.listen + 188 },
  { id: "S03c", title: "Then repeat", from: START.listen + 583 },
  { id: "S04", title: "Compare delivery", from: START.compare + 20 },
  { id: "S05", title: "Choose the next try", from: START.compare + 500 },
  { id: "S06", title: "Your own voice, too", from: START.recording + 20 },
  { id: "S07", title: "Private on your Mac", from: START.privacy + 20 },
  { id: "S08", title: "Get Ichido", from: START.cta + 30 },
] as const;

export const storyAt = (frame: number) => {
  let current: (typeof STORY)[number] = STORY[0];
  for (const s of STORY) {
    if (frame >= s.from) {
      current = s;
    }
  }
  return current;
};

// Scratch read (macOS Samantha, 168 wpm) from scripts/make-scratch-vo.sh.
// Cues are scene-relative so a retime carries its narration with it.
const CUES = [
  { id: "vo01", seg: "opening", at: 30, dur: 1.014, text: "One more try." },
  { id: "vo02a", seg: "opening", at: 180, dur: 3.256, text: "Meet Ichido, your private speaking room for Mac." },
  { id: "vo02b", seg: "picker", at: 176, dur: 2.491, text: "Import a clip, or capture Mac audio." },
  { id: "vo03a", seg: "listen", at: 38, dur: 1.163, text: "Listen to a phrase." },
  { id: "vo03u", seg: "listen", at: 196, dur: 2.244, text: "Explore the words, right on your Mac." },
  { id: "vo03b", seg: "listen", at: 584, dur: 1.228, text: "Then record your version." },
  { id: "vo04", seg: "compare", at: 96, dur: 3.381, text: "Compare pitch, timing, and loudness with the reference." },
  { id: "vo05", seg: "compare", at: 400, dur: 4.956, text: "When enough words match reliably, two measured targets help you choose what to try next." },
  { id: "vo06a", seg: "recording", at: 52, dur: 1.706, text: "Record yourself, too." },
  { id: "vo06b", seg: "recording", at: 166, dur: 1.785, text: "Click a word to replay that moment." },
  { id: "vo07a", seg: "privacy", at: 46, dur: 3.853, text: "No account. No recording uploads. No analytics." },
  // The network sentence must follow the privacy statement directly, so the
  // "stay on your Mac" line comes after it.
  { id: "vo07c", seg: "privacy", at: 284, dur: 3.239, text: "Update checks and optional model downloads use the network." },
  {
    id: "vo07b",
    seg: "privacy",
    at: 485,
    dur: 5.175,
    text: "Your recordings, transcripts, analysis, and language chat stay on your Mac.",
  },
  { id: "vo08", seg: "cta", at: 74, dur: 2.372, text: "Ichido. One more try." },
] as const;

export const VO = CUES.map((cue) => ({ ...cue, at: START[cue.seg] + cue.at }));

export const voFrames = (seconds: number) => Math.ceil(seconds * VIDEO.fps);

// Where a verified response capture would replace the documented fallback.
const SLOTS = [
  { seg: "picker", from: 184, to: 330, label: "Import clip… loaded state not captured. Focus-only fallback." },
  { seg: "listen", from: 626, to: 700, label: "Start practice → playback → recording states not captured. Hover hold." },
  { seg: "compare", from: 146, to: 300, label: "Timing and Emphasis responses not captured. Tabs are highlighted, never clicked." },
  { seg: "compare", from: 884, to: 970, label: "Try again → next practice state not captured. Hover hold." },
  { seg: "recording", from: 196, to: 300, label: "Selected-word replay state not captured. Hover hold." },
] as const;

export const CAPTURE_SLOTS = SLOTS.map((slot) => ({
  from: START[slot.seg] + slot.from,
  to: START[slot.seg] + slot.to,
  label: slot.label,
}));
