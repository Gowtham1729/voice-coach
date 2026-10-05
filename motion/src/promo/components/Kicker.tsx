import React from "react";
import { useCurrentFrame } from "remotion";
import { EASE, ramp } from "../motion";
import { COLORS, STACK, TRACKING } from "../theme";

// Website eyebrow: Space Grotesk caps with a cobalt status dot.
export const Kicker: React.FC<{
  text: string;
  at: number;
  out?: number;
  x?: number;
  y?: number; // top edge
  size?: number;
  color?: string;
  dotColor?: string;
}> = ({
  text,
  at,
  out,
  x = 96,
  y = 96,
  size = 22,
  color = COLORS.inkSoft,
  dotColor = COLORS.cobalt,
}) => {
  const frame = useCurrentFrame();
  const enter = ramp(frame, at, at + 26, EASE.out);
  const leave = out === undefined ? 0 : ramp(frame, out, out + 16, EASE.in);
  const dot = size * 0.42;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        display: "flex",
        alignItems: "center",
        gap: size * 0.55,
        opacity: enter * (1 - leave),
        translate: `${(1 - enter) * -18}px ${leave * -10}px`,
        fontFamily: STACK.display,
        fontWeight: 700,
        fontSize: size,
        lineHeight: 1,
        letterSpacing: `${TRACKING.kicker}em`,
        textTransform: "uppercase",
        color,
        whiteSpace: "nowrap",
      }}
    >
      <span
        style={{
          width: dot,
          height: dot,
          borderRadius: "50%",
          background: dotColor,
          boxShadow: `0 0 0 ${dot * 0.55}px rgba(40, 72, 232, 0.12)`,
          flexShrink: 0,
          scale: String(0.4 + 0.6 * enter),
        }}
      />
      {text}
    </div>
  );
};
