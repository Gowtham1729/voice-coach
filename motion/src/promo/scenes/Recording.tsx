import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { UI } from "../assets";
import { Cursor, type CursorScript } from "../components/Cursor";
import { FocusRing } from "../components/FocusRing";
import { Kicker } from "../components/Kicker";
import { Phrase } from "../components/Phrase";
import { UiPanel } from "../components/UiPanel";
import { RECORDING_HEADLINE } from "../layout";
import { pulse, toScreen, type Placement } from "../motion";

const words = UI.takeWords;
const ROW: Placement = { x: 96 + ((words.w + 52) * 1.3) / 2, y: 520, scale: 1.3 };
const LIKE = toScreen(words, ROW, words.at.like);

const POINTER: CursorScript = {
  from: { x: 1300, y: 990 },
  show: 160,
  moves: [{ at: 194, to: { x: LIKE.x + LIKE.w - 30, y: LIKE.y + LIKE.h - 12 }, dur: 28, arc: 0.08 }],
};

// S06 · a separate ordinary recording. A real transcript word is hovered;
// the selected-word replay state waits for a capture. The headline's period
// becomes the cobalt privacy stage.
export const Recording: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill>
      <Kicker text="New example · Recording" at={22} y={110} />
      <Phrase
        text={RECORDING_HEADLINE.text}
        at={36}
        stagger={5}
        size={RECORDING_HEADLINE.size}
        x={RECORDING_HEADLINE.left}
        baseline={RECORDING_HEADLINE.baseline}
      />
      <UiPanel crop={words} {...ROW} />
      <Phrase
        text="Click a word. Replay that moment."
        role="body"
        at={160}
        stagger={3}
        size={52}
        x={96}
        baseline={720}
      />
      <FocusRing rect={LIKE} radius={14} opacity={pulse(frame, 188, 296, 8, 12)} />
      <Cursor script={POINTER} />
    </AbsoluteFill>
  );
};
