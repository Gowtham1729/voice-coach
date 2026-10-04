import React from "react";
import { useCurrentFrame } from "remotion";
import { EASE, ramp, type Point } from "../motion";
import { COLORS } from "../theme";

export type CursorMove = { at: number; to: Point; dur?: number; arc?: number };

export type CursorScript = {
  from: Point;
  show: number;
  hide?: number;
  moves: readonly CursorMove[];
  clicks?: readonly number[];
};

// Arrive-by keyframes with a slight wrist arc on each move. Hotspot position.
export const cursorAt = (frame: number, s: CursorScript): Point => {
  let at = s.from;
  for (const move of s.moves) {
    const dur = move.dur ?? 24;
    if (frame >= move.at) {
      at = move.to;
      continue;
    }
    if (frame > move.at - dur) {
      const t = EASE.pointer((frame - (move.at - dur)) / dur);
      const dx = move.to.x - at.x;
      const dy = move.to.y - at.y;
      const len = Math.hypot(dx, dy) || 1;
      const bow = (move.arc ?? 0.08) * len * Math.sin(Math.PI * t);
      return {
        x: at.x + dx * t + (-dy / len) * bow,
        y: at.y + dy * t + (dx / len) * bow,
      };
    }
    return at;
  }
  return at;
};

// Source: promo-2026-10-04/assets/interaction/cursor.svg (hotspot 9,5 in a 48×64 box).
const VIEW = { w: 48, h: 64, hx: 9, hy: 5 };
const WIDTH = 28;

// No click ring: the control's own response is the confirmation.
export const Cursor: React.FC<{ script: CursorScript }> = ({ script }) => {
  const frame = useCurrentFrame();
  const fadeIn = ramp(frame, script.show, script.show + 10, EASE.ui);
  const fadeOut =
    script.hide === undefined
      ? 0
      : ramp(frame, script.hide, script.hide + 10, EASE.in);
  const opacity = fadeIn * (1 - fadeOut);
  if (opacity <= 0.001) {
    return null;
  }

  const p = cursorAt(frame, script);
  const k = WIDTH / VIEW.w;
  let press = 0;
  for (const c of script.clicks ?? []) {
    const down = ramp(frame, c - 2, c + 2, EASE.ui);
    const up = ramp(frame, c + 4, c + 12, EASE.out);
    press = Math.max(press, down * (1 - up));
  }

  return (
    <svg
      width={WIDTH}
      height={VIEW.h * k}
      viewBox={`0 0 ${VIEW.w} ${VIEW.h}`}
      style={{
        position: "absolute",
        left: p.x - VIEW.hx * k,
        top: p.y - VIEW.hy * k,
        opacity,
        overflow: "visible",
        pointerEvents: "none",
        transformOrigin: `${VIEW.hx * k}px ${VIEW.hy * k}px`,
        scale: String(1 - 0.14 * press),
        filter: "drop-shadow(0 3px 4px rgba(0, 0, 0, 0.32))",
      }}
    >
      <path
        d="M9 5 L9 47 L19 37 L27 56 L34 53 L26 34 L41 34 Z"
        fill={COLORS.ink}
        stroke={COLORS.white}
        strokeWidth={2.5}
        strokeLinejoin="round"
      />
    </svg>
  );
};
