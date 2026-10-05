import React from "react";
import { Img, useCurrentFrame } from "remotion";
import { WORDS } from "../assets";
import type { Placement, Point, Rect, Sized } from "../motion";
import { VIDEO } from "../theme";
import { UiPanel } from "./UiPanel";

export type WordsPlate = keyof typeof WORDS.plates;

const PLATES: readonly WordsPlate[] = ["filled", "thinking", "answer"];

// maxWidth: Tailwind's preflight would shrink strips wider than their window.
const fill: React.CSSProperties = {
  position: "absolute",
  left: 0,
  top: 0,
  width: WORDS.w,
  height: WORDS.h,
  maxWidth: "none",
};

// One cell of an image strip, shown where it sits on the card.
const Cell: React.FC<{
  src: string;
  at: Rect;
  offset: Point;
  size: Sized;
  opacity: number;
}> = ({ src, at, offset, size, opacity }) => (
  <div
    style={{
      position: "absolute",
      left: at.x,
      top: at.y,
      width: at.w,
      height: at.h,
      overflow: "hidden",
      opacity,
    }}
  >
    <Img
      src={src}
      style={{
        position: "absolute",
        left: -offset.x,
        top: -offset.y,
        width: size.w,
        height: size.h,
        maxWidth: "none",
      }}
    />
  </div>
);

// The real Words inspector. Every plate stays mounted so a state change never
// waits on a decode; only the current one is visible.
export const WordsInspector: React.FC<
  Placement & {
    plate: WordsPlate;
    menu: number; // Suggested questions menu opacity
    row: number | null; // menu item under the pointer
    thinkingFrom: number; // frame the spinner starts turning
  }
> = ({ plate, menu, row, thinkingFrom, ...place }) => {
  const frame = useCurrentFrame();
  const { rows, spinner } = WORDS;
  const cell = Math.floor(((frame - thinkingFrom) / VIDEO.fps) * spinner.fps);
  const turn = ((cell % spinner.frames) + spinner.frames) % spinner.frames;
  const item = row ?? 0;

  return (
    <UiPanel
      crop={{ src: WORDS.plates.idle, w: WORDS.w, h: WORDS.h, bg: WORDS.bg }}
      {...place}
      pad={18}
      radius={22}
    >
      {PLATES.map((name) => (
        <Img key={name} src={WORDS.plates[name]} style={{ ...fill, opacity: plate === name ? 1 : 0 }} />
      ))}
      <Img src={WORDS.plates.menu} style={{ ...fill, opacity: menu }} />
      <Cell
        src={rows.src}
        at={{ ...rows.at, y: rows.at.y + rows.at.h * item }}
        offset={{ x: 0, y: rows.at.h * item }}
        size={{ w: rows.at.w, h: rows.at.h * rows.count }}
        opacity={row === null ? 0 : menu}
      />
      <Cell
        src={spinner.src}
        at={spinner.at}
        offset={{ x: spinner.at.w * turn, y: 0 }}
        size={{ w: spinner.at.w * spinner.frames, h: spinner.at.h }}
        opacity={plate === "thinking" ? 1 : 0}
      />
    </UiPanel>
  );
};
