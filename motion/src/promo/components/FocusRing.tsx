import React from "react";
import type { Rect } from "../motion";
import { COLORS } from "../theme";

// Editorial focus annotation drawn in screen pixels around a real control.
export const FocusRing: React.FC<{
  rect: Rect;
  opacity: number;
  radius?: number;
  gap?: number;
  width?: number;
  color?: string;
  fill?: number; // 0..1 strength of a soft tint inside the ring
}> = ({
  rect,
  opacity,
  radius = 12,
  gap = 6,
  width = 3,
  color = COLORS.ring,
  fill = 0,
}) => {
  if (opacity <= 0.001) {
    return null;
  }
  const g = gap + (1 - opacity) * 10;
  return (
    <div
      style={{
        position: "absolute",
        left: rect.x - g,
        top: rect.y - g,
        width: rect.w + g * 2,
        height: rect.h + g * 2,
        boxSizing: "border-box",
        borderRadius: radius + g,
        border: `${width}px solid ${color}`,
        background: fill > 0 ? `rgba(92, 118, 255, ${0.12 * fill})` : undefined,
        boxShadow: `0 0 0 4px rgba(40, 72, 232, 0.18), 0 0 28px rgba(92, 118, 255, 0.35)`,
        opacity,
      }}
    />
  );
};
