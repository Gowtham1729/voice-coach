import React from "react";
import { COLORS, METRICS, type FontRole } from "../theme";

// The period as a shape with the glyph's exact advance and baseline position,
// so it can travel, scale and flood the stage like the brand's cobalt dot.
export const InlineDot: React.FC<{
  role?: FontRole;
  color?: string;
  scale?: number;
}> = ({ role = "display", color = COLORS.cobalt, scale = 1 }) => {
  const m = METRICS[role];
  const bottom = m.dotLift - m.dot / 2;
  return (
    <span
      style={{
        display: "inline-block",
        width: `${m.dot}em`,
        height: `${m.dot}em`,
        marginLeft: `${m.dotLead}em`,
        marginRight: `${m.dotLead}em`,
        marginBottom: `${bottom}em`,
        verticalAlign: "baseline",
        borderRadius: "50%",
        background: color,
        scale: String(scale),
      }}
    />
  );
};

export const Dot: React.FC<{
  x: number;
  y: number;
  radius: number;
  color?: string;
  opacity?: number;
}> = ({ x, y, radius, color = COLORS.cobalt, opacity = 1 }) => (
  <div
    style={{
      position: "absolute",
      left: x - radius,
      top: y - radius,
      width: radius * 2,
      height: radius * 2,
      borderRadius: "50%",
      background: color,
      opacity,
    }}
  />
);
