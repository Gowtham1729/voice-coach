import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { CAPTURE_SLOTS, VO, storyAt, voFrames } from "../timeline";
import { MARGIN, STACK, VIDEO } from "../theme";

const pad2 = (n: number) => (n < 10 ? `0${n}` : String(n));

const label: React.CSSProperties = {
  position: "absolute",
  fontFamily: STACK.body,
  fontSize: 20,
  lineHeight: 1,
  color: "#fff",
  background: "rgba(16, 18, 17, 0.72)",
  padding: "9px 14px",
  borderRadius: 8,
  whiteSpace: "nowrap",
};

// Animatic overlay: scene name, timecode, safe area, capture slots, and the scratch line.
export const Guides: React.FC = () => {
  const frame = useCurrentFrame();
  const scene = storyAt(frame);
  const seconds = Math.floor(frame / VIDEO.fps);
  const sub = frame % VIDEO.fps;
  const slot = CAPTURE_SLOTS.find((s) => frame >= s.from && frame < s.to);
  const line = VO.find((v) => frame >= v.at && frame < v.at + voFrames(v.dur));

  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      <div
        style={{
          position: "absolute",
          left: MARGIN.side,
          top: MARGIN.top,
          right: MARGIN.side,
          bottom: MARGIN.bottom,
          border: "1px dashed rgba(255, 64, 160, 0.45)",
        }}
      />
      <div style={{ ...label, left: 16, top: 16 }}>
        {scene.id} · {scene.title}
      </div>
      <div style={{ ...label, right: 16, top: 16, fontVariantNumeric: "tabular-nums" }}>
        {pad2(seconds)}:{pad2(sub)} · f{frame}
      </div>
      {slot ? (
        <div
          style={{
            ...label,
            left: "50%",
            top: 16,
            translate: "-50% 0",
            background: "rgba(214, 140, 0, 0.92)",
            color: "#1b1300",
          }}
        >
          CAPTURE SLOT · {slot.label}
        </div>
      ) : null}
      {line ? (
        <div
          style={{
            ...label,
            left: "50%",
            bottom: 16,
            translate: "-50% 0",
            fontSize: 24,
            padding: "11px 18px",
          }}
        >
          <span style={{ opacity: 0.55, marginRight: 12 }}>SCRATCH VO</span>
          {line.text}
        </div>
      ) : null}
    </AbsoluteFill>
  );
};
