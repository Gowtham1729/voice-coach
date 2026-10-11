import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { UI } from "../assets";
import { Cursor, type CursorScript } from "../components/Cursor";
import { FocusRing } from "../components/FocusRing";
import { Kicker } from "../components/Kicker";
import { Phrase } from "../components/Phrase";
import { UiPanel } from "../components/UiPanel";
import { topForBaseline } from "../layout";
import {
  anchorAt,
  EASE,
  follow,
  inFlight,
  mixPlacement,
  mixRect,
  pulse,
  ramp,
  toScreen,
  type Key,
  type Placement,
  type Rect,
} from "../motion";
import { COLORS, STACK } from "../theme";

const chart = UI.comparePitch;
const next = UI.practiceNext;
const retry = UI.tryAgain;
const take = UI.takeSelector;

const CHART: Placement = { x: 939, y: 656, scale: 0.78 };
// Dive toward "about", where the dashed reference sits well above the solid
// take. Framed so the subtitle and panel bottom fall just outside the frame,
// the legend stays whole, and the right edge lands between "iPhone," and "the".
const CHART_ZOOM = anchorAt(chart, { x: 706, y: 450 }, { x: 1058, y: 458 }, 1.52);
// One camera pan carries both panels the same distance; the zoomed chart is
// too wide to clear the frame, so it also fades.
const PAN = 1500;
const CHART_GONE: Placement = { ...CHART_ZOOM, x: CHART_ZOOM.x - PAN };

const NEXT_IN: Placement = { x: 1352 + PAN, y: 548, scale: 1.2 };
const NEXT: Placement = { x: 1352, y: 548, scale: 1.2 };
const NEXT_UP: Placement = { x: 1352, y: 548 - 980, scale: 1.2 };
const RETRY_IN: Placement = { x: 1352, y: 1420, scale: 1.2 };
const RETRY: Placement = { x: 1352, y: 640, scale: 1.2 };
const TAKE: Placement = { x: 1602, y: 486, scale: 1 };

const TAB = {
  pitch: toScreen(chart, CHART, chart.at.pitch),
  timing: toScreen(chart, CHART, chart.at.timing),
  emphasis: toScreen(chart, CHART, chart.at.emphasis),
};
const TAB_KEYS: readonly Key<Rect>[] = [
  { at: 156, to: TAB.timing, dur: 14, ease: EASE.out },
  { at: 194, to: TAB.emphasis, dur: 14, ease: EASE.out },
  { at: 250, to: TAB.pitch, dur: 16, ease: EASE.out },
];
const TARGET_ONE = toScreen(next, NEXT, next.at.first);
const TARGET_TWO = toScreen(next, NEXT, next.at.second);
const RETRY_BUTTON = toScreen(retry, RETRY, retry.at.button);

const POINTER: CursorScript = {
  from: { x: 1720, y: 1010 },
  show: 600,
  hide: 720,
  moves: [
    {
      at: 630,
      to: { x: RETRY_BUTTON.x + RETRY_BUTTON.w - 26, y: RETRY_BUTTON.y + RETRY_BUTTON.h - 10 },
      dur: 28,
      arc: 0.08,
    },
  ],
};

// Like a segmented control's pill: it widens mid-hop, then lands on the label.
const stretch = (r: Rect, t: number | null): Rect => {
  if (t === null) {
    return r;
  }
  const grow = 0.3 * Math.sin(Math.PI * t) * r.w;
  return { ...r, x: r.x - grow / 2, w: r.w + grow };
};

// "Pitch · Timing · Loudness": the app tab says Emphasis; outside the UI it is loudness.
const Measures: React.FC<{ at: number; out: number }> = ({ at, out }) => {
  const frame = useCurrentFrame();
  const enter = ramp(frame, at, at + 30, EASE.out);
  const leave = ramp(frame, out, out + 18, EASE.in);
  const dimming = ramp(frame, 118, 126, EASE.ui) - ramp(frame, 248, 262, EASE.ui);
  const focus = (from: number, to: number) =>
    1 - 0.62 * Math.max(0, dimming - pulse(frame, from, to, 8, 8));
  const items = [
    { text: "Pitch", opacity: focus(118, 150) },
    { text: "Timing", opacity: focus(152, 188) },
    { text: "Loudness", opacity: focus(190, 244) },
  ];
  return (
    <div
      style={{
        position: "absolute",
        right: 1920 - 1782,
        top: topForBaseline(236, 44, "body"),
        fontFamily: STACK.body,
        fontSize: 44,
        lineHeight: 1,
        color: COLORS.ink,
        whiteSpace: "nowrap",
        overflow: "hidden",
        padding: "0.1em 0 0.25em",
        margin: "-0.1em 0 -0.25em",
      }}
    >
      <div style={{ translate: `0 ${(1 - enter) * 1.2 - leave * 1.3}em` }}>
        {items.map((item, i) => (
          <React.Fragment key={item.text}>
            {i > 0 ? (
              <span style={{ color: COLORS.cobalt, margin: "0 0.32em" }}>·</span>
            ) : null}
            <span style={{ opacity: item.opacity }}>{item.text}</span>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
};

// S04 → S05 · English example, one session throughout: the real Pitch chart,
// then a camera glide to the two measured targets and Try again.
export const Compare: React.FC = () => {
  const frame = useCurrentFrame();

  const dive = ramp(frame, 200, 260, EASE.inOut);
  const pan = ramp(frame, 270, 340, EASE.inOut);
  const chartPlace =
    frame < 270
      ? mixPlacement(CHART, CHART_ZOOM, dive)
      : mixPlacement(CHART_ZOOM, CHART_GONE, pan);
  const column = toScreen(chart, chartPlace, chart.at.aboutColumn);

  const toRetry = ramp(frame, 520, 570, EASE.inOut);
  const nextPlace =
    frame < 520 ? mixPlacement(NEXT_IN, NEXT, pan) : mixPlacement(NEXT, NEXT_UP, toRetry);
  const retryPlace = mixPlacement(RETRY_IN, RETRY, toRetry);
  // The take count settles in once Try again has landed, so the two never cross.
  const takeIn = ramp(frame, 570, 600, EASE.out);
  const takePlace = { ...TAKE, y: TAKE.y + 16 * (1 - takeIn) };

  const tabRing = stretch(follow(frame, TAB.pitch, TAB_KEYS, mixRect), inFlight(frame, TAB_KEYS));
  const targetRing = follow(frame, TARGET_ONE, [{ at: 460, to: TARGET_TWO, dur: 20 }], mixRect);

  return (
    <AbsoluteFill>
      <Kicker text="Same loop. An English line." at={22} out={200} y={110} />
      <Phrase
        text="Compare your delivery."
        at={32}
        stagger={6}
        size={88}
        x={96}
        baseline={236}
        out={200}
      />
      <Measures at={56} out={200} />

      <UiPanel crop={chart} {...chartPlace} opacity={1 - ramp(frame, 300, 350, EASE.inOut)} />
      <FocusRing rect={tabRing} radius={9} opacity={pulse(frame, 116, 250, 8, 10)} />
      <FocusRing rect={column} radius={14} fill={1} opacity={pulse(frame, 210, 330, 12, 14)} />

      <Phrase
        text={"This take ran\n1.4 seconds long."}
        at={280}
        stagger={5}
        size={76}
        x={96}
        baseline={430}
        out={575}
      />
      <Phrase
        text="Match the pace through “about.”"
        role="body"
        at={450}
        stagger={2}
        size={40}
        color={COLORS.inkSoft}
        x={96}
        baseline={640}
        out={575}
      />
      <UiPanel crop={next} {...nextPlace} opacity={1 - ramp(frame, 520, 560, EASE.inOut)}>
        {/* The capture names “over”, which is not on the chart. “about” is. */}
        <div
          style={{
            position: "absolute",
            left: 70,
            top: 246,
            width: 545,
            height: 42,
            background: "#1e1e1e",
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 78,
            top: 254,
            fontFamily: STACK.body,
            fontSize: 18,
            lineHeight: 1.2,
            color: "#f2f2f4",
            whiteSpace: "nowrap",
          }}
        >
          using the transition into ‘about’ as a checkpoint.
        </div>
      </UiPanel>
      <FocusRing rect={targetRing} radius={14} gap={2} opacity={pulse(frame, 360, 520, 10, 12)} />

      <Phrase text="One more take." at={590} stagger={6} size={104} x={96} baseline={679} />
      <UiPanel crop={take} {...takePlace} pad={14} radius={18} opacity={takeIn} />
      <UiPanel crop={retry} {...retryPlace} pad={20} radius={22} />
      <FocusRing rect={RETRY_BUTTON} radius={12} opacity={pulse(frame, 630, 710, 8, 10)} />
      <Cursor script={POINTER} />
    </AbsoluteFill>
  );
};
