import React from "react";
import { AbsoluteFill, Img, useCurrentFrame } from "remotion";
import { PRODUCT } from "../assets";
import { Cursor, type CursorScript } from "../components/Cursor";
import { FocusRing } from "../components/FocusRing";
import { Kicker } from "../components/Kicker";
import { Phrase } from "../components/Phrase";
import { EASE, follow, mixRect, pulse, ramp, toScreen, type Placement } from "../motion";

const picker = PRODUCT.picker;

// The sheet is the picture. The blurred home window is gone: it taught nothing.
const SHEET: Placement = { x: 1400, y: 570, scale: 0.56 };
const IMPORT = toScreen(picker, SHEET, picker.at.import);
const CAPTURE = toScreen(picker, SHEET, picker.at.capture);
const SHEET_RECT = toScreen(picker, SHEET, { x: 0, y: 0, w: picker.w, h: picker.h });

const POINTER: CursorScript = {
  from: { x: 1580, y: 990 },
  show: 70,
  moves: [
    { at: 96, to: { x: IMPORT.x + IMPORT.w - 16, y: IMPORT.y + IMPORT.h - 7 }, dur: 22, arc: -0.08 },
    { at: 168, to: { x: CAPTURE.x + CAPTURE.w - 14, y: CAPTURE.y + CAPTURE.h - 7 }, dur: 22, arc: 0.06 },
  ],
  clicks: [],
};

// Say the job, then show the real picker. Import and Capture get focus, not clicks.
export const Picker: React.FC = () => {
  const frame = useCurrentFrame();
  const arrive = ramp(frame, 16, 42, EASE.out);
  const lineOne = 1 - 0.68 * ramp(frame, 164, 178, EASE.ui);
  const lineTwo =
    1 - 0.68 * ramp(frame, 112, 126, EASE.ui) + 0.68 * ramp(frame, 164, 178, EASE.ui);
  const inputRing = follow(frame, IMPORT, [{ at: 112, to: CAPTURE, dur: 24 }], mixRect);

  return (
    <AbsoluteFill>
      <Kicker text="Reference practice" at={8} y={220} />
      <Phrase
        text={"Bring a clip\nyou want to sound like."}
        at={14}
        stagger={4}
        size={64}
        lineHeight={1.05}
        x={96}
        baseline={390}
      />
      <Phrase text="Import a clip" at={40} size={52} x={96} baseline={620} opacity={lineOne} />
      <Phrase text="Capture Mac audio" at={48} size={52} x={96} baseline={700} opacity={lineTwo} />

      <div
        style={{
          position: "absolute",
          left: SHEET_RECT.x,
          top: SHEET_RECT.y,
          width: SHEET_RECT.w,
          height: SHEET_RECT.h,
          opacity: arrive,
          scale: String(0.97 + 0.03 * arrive),
          borderRadius: picker.radius * SHEET.scale + 2,
          overflow: "hidden",
          background: picker.bg,
          boxShadow: "0 30px 70px rgba(23, 29, 26, 0.26), 0 2px 8px rgba(23, 29, 26, 0.12)",
        }}
      >
        <Img
          src={picker.src}
          style={{
            width: SHEET_RECT.w,
            height: SHEET_RECT.h,
            maxWidth: "none",
          }}
        />
      </div>

      <FocusRing rect={inputRing} radius={8} opacity={pulse(frame, 96, 330, 8, 10) * arrive} />
      <Cursor script={POINTER} />
    </AbsoluteFill>
  );
};
