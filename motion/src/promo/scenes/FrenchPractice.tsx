import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { UI, WORDS } from "../assets";
import { Cursor, cursorAt, type CursorScript } from "../components/Cursor";
import { FocusRing } from "../components/FocusRing";
import { Kicker } from "../components/Kicker";
import { Phrase } from "../components/Phrase";
import { UiPanel } from "../components/UiPanel";
import { WordsInspector, type WordsPlate } from "../components/WordsInspector";
import {
  anchorAt,
  center,
  EASE,
  mixPlacement,
  outset,
  pulse,
  ramp,
  toScreen,
  type Placement,
  type Point,
  type Rect,
} from "../motion";
import { COLORS } from "../theme";

const card = UI.practiceCard;
const actions = UI.practiceActions;

// Beats, in scene frames.
const TO_WORDS = 166;
const MENU_CLICK = 240;
const EXPLAIN_CLICK = 276;
const FILLED = 298; // the app fills in the question just after the menu closes
const SEND_CLICK = 324;
const SENT = SEND_CLICK + 2;
const ANSWER = 382; // Thinking… ran 4.5 s in the recording; shortened, and disclosed in the storyboard
// Body copy and the gloss ring leave before the camera moves, so the glide
// carries only the panels and the headline swap.
const CLEAR = 516;
const TO_REPEAT = 560;
const GLIDE = 46;

// Panels scroll inside a viewport below the headline, like moving through the window.
const VIEW_TOP = 330;
const CARD: Placement = { x: 960, y: 664, scale: 0.8 };
// Beside Words the transcript steps into the left column, as in the app.
const CARD_SIDE: Placement = { x: 624, y: 630, scale: 0.5 };
const INSPECTOR: Placement = { x: 1531, y: 540, scale: 0.78 };
const INSPECTOR_IN: Placement = { ...INSPECTOR, x: INSPECTOR.x + 760 };
// Start practice sits below the transcript and left of Words: the camera moves
// down and left, so everything leaves up and right.
const DOWN_LEFT = { x: 760, y: -760 };
const shift = (p: Placement): Placement => ({ ...p, x: p.x + DOWN_LEFT.x, y: p.y + DOWN_LEFT.y });
const ACTIONS: Placement = { x: 960, y: 664, scale: 1.5 };
const ACTIONS_IN: Placement = { ...ACTIONS, x: ACTIONS.x - DOWN_LEFT.x, y: ACTIONS.y - DOWN_LEFT.y };

const MODE = toScreen(card, CARD, card.at.listenRepeat);
const START = toScreen(actions, ACTIONS, actions.at.start);
const words = (r: Rect) => toScreen(WORDS, INSPECTOR, r);
const SUGGESTED = words(WORDS.at.suggested);
const EXPLAIN = words(WORDS.rows.at);
const SEND = words(WORDS.at.send);
const GLOSSES = WORDS.at.glosses;

const on = (r: Rect, fx: number, fy: number): Point => ({ x: r.x + r.w * fx, y: r.y + r.h * fy });

const POINTER: CursorScript = {
  from: { x: 1500, y: 1010 },
  show: 74,
  hide: 346,
  moves: [
    { at: 104, to: { x: MODE.x + MODE.w - 14, y: MODE.y + MODE.h - 6 }, dur: 26, arc: 0.08 },
    { at: 236, to: on(SUGGESTED, 0.6, 0.68), dur: 40, arc: -0.06 },
    { at: 270, to: on(EXPLAIN, 0.62, 0.6), dur: 22, arc: 0.06 },
    { at: 320, to: on(SEND, 0.5, 0.62), dur: 20, arc: 0.1 },
    { at: 372, to: on(SEND, 1.6, 2.6), dur: 26 },
  ],
  clicks: [MENU_CLICK, EXPLAIN_CLICK, SEND_CLICK],
};

const POINTER_REPEAT: CursorScript = {
  from: { x: 1560, y: 1010 },
  show: 600,
  moves: [{ at: 640, to: { x: START.x + START.w - 22, y: START.y + START.h - 10 }, dur: 28, arc: -0.1 }],
};

// The menu item under the pointer's hotspot, as macOS highlights it.
const itemUnder = (p: Point, place: Placement): number | null => {
  const x = (p.x - place.x) / place.scale + WORDS.w / 2;
  const y = (p.y - place.y) / place.scale + WORDS.h / 2;
  const r = WORDS.rows.at;
  const k = Math.floor((y - r.y) / r.h);
  return x >= r.x && x < r.x + r.w && k >= 0 && k < WORDS.rows.count ? k : null;
};

const plateAt = (frame: number): WordsPlate =>
  frame < FILLED ? "idle" : frame < SENT ? "filled" : frame < ANSWER ? "thinking" : "answer";

// S03 → S03c · one French session. Listen, explore the words in the real Words
// inspector, then back to Start practice. Listen & Repeat is already selected
// in the capture, so it is focused, never clicked; Start practice gets a hover
// hold until the playback and recording states are captured.
export const FrenchPractice: React.FC = () => {
  const frame = useCurrentFrame();
  const toWords = ramp(frame, TO_WORDS, TO_WORDS + GLIDE, EASE.inOut);
  const toRepeat = ramp(frame, TO_REPEAT, TO_REPEAT + GLIDE, EASE.inOut);

  const cardPlace =
    frame < TO_REPEAT ? mixPlacement(CARD, CARD_SIDE, toWords) : mixPlacement(CARD_SIDE, shift(CARD_SIDE), toRepeat);
  const actionsPlace = mixPlacement(ACTIONS_IN, ACTIONS, toRepeat);

  // A slow lean toward the reply while it is read, glosses held in place.
  const glossAt = center(words(GLOSSES));
  const lean = mixPlacement(
    INSPECTOR,
    anchorAt(WORDS, center(GLOSSES), glossAt, 0.8),
    ramp(frame, ANSWER, TO_REPEAT, EASE.inOut),
  );
  const inspectorPlace =
    frame < TO_REPEAT ? mixPlacement(INSPECTOR_IN, lean, toWords) : mixPlacement(lean, shift(lean), toRepeat);

  // Menu: opens on the click, blinks the chosen item, then fades like macOS.
  const menu =
    ramp(frame, MENU_CLICK + 2, MENU_CLICK + 5, EASE.linear) *
    (1 - ramp(frame, EXPLAIN_CLICK + 7, EXPLAIN_CLICK + 15, EASE.linear));
  const blinkOff = frame > EXPLAIN_CLICK && frame <= EXPLAIN_CLICK + 4;
  const row =
    frame >= EXPLAIN_CLICK ? (blinkOff ? null : 0) : itemUnder(cursorAt(frame, POINTER), inspectorPlace);

  return (
    <AbsoluteFill>
      <Kicker text="Example · French clip" at={22} y={110} />
      <Phrase text="Listen." at={30} stagger={8} size={104} x={96} baseline={262} out={TO_WORDS - 6} />
      <Phrase text="Understand." at={TO_WORDS + 10} stagger={8} size={104} x={96} baseline={262} out={TO_REPEAT - 4} />
      <Phrase
        text={"Explore meanings, grammar, synonyms,\nand translations on your Mac."}
        role="body"
        at={TO_WORDS + 28}
        stagger={2}
        size={40}
        lineHeight={1.3}
        x={96}
        baseline={346}
        out={CLEAR + 4}
      />
      <Phrase
        text="Experimental and off by default. Chat requires available Apple Intelligence."
        role="body"
        at={TO_WORDS + 48}
        stagger={1}
        size={28}
        color={COLORS.inkSoft}
        x={96}
        baseline={868}
        out={CLEAR}
      />
      <Phrase text="Repeat." at={TO_REPEAT + 16} stagger={8} size={104} x={96} baseline={262} />

      <div
        style={{
          position: "absolute",
          left: 0,
          top: VIEW_TOP,
          width: 1920,
          height: 1080 - VIEW_TOP,
          overflow: "hidden",
          maskImage: "linear-gradient(to bottom, transparent 0px, #000 36px)",
          WebkitMaskImage: "linear-gradient(to bottom, transparent 0px, #000 36px)",
        }}
      >
        <div style={{ position: "absolute", left: 0, top: -VIEW_TOP, width: 1920, height: 1080 }}>
          <UiPanel crop={card} {...cardPlace} />
          <UiPanel crop={actions} {...actionsPlace} pad={20} radius={22} />
        </div>
      </div>

      <WordsInspector
        {...inspectorPlace}
        plate={plateAt(frame)}
        menu={menu}
        row={row}
        thinkingFrom={SENT}
      />

      <FocusRing rect={MODE} radius={10} opacity={pulse(frame, 98, TO_WORDS - 16, 8, 10)} />
      <FocusRing
        rect={outset(toScreen(WORDS, inspectorPlace, GLOSSES), 10)}
        radius={12}
        opacity={pulse(frame, ANSWER + 16, CLEAR + 4, 10, 12)}
      />
      <FocusRing rect={START} radius={16} opacity={pulse(frame, 634, 700, 8, 10)} />
      <Cursor script={POINTER} />
      <Cursor script={POINTER_REPEAT} />
    </AbsoluteFill>
  );
};
