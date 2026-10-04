import React from "react";
import { Img } from "remotion";
import type { Placement } from "../motion";

type Source = { src: string; w: number; h: number; bg: string };

const shadow = (scale: number, lift: number) => {
  const k = 1 / Math.max(scale, 0.05);
  return [
    `0 ${22 * k * lift}px ${56 * k * lift}px rgba(23, 29, 26, ${0.22 * lift})`,
    `0 ${3 * k * lift}px ${10 * k * lift}px rgba(23, 29, 26, ${0.12 * lift})`,
    `inset 0 0 0 ${k}px rgba(255, 255, 255, 0.07)`,
  ].join(", ");
};

// An unretouched crop seated on a card of its own edge colour. The crop's
// centre lands on (x, y); children overlay in source pixels of the crop.
export const UiPanel: React.FC<
  Placement & {
    crop: Source;
    pad?: number;
    radius?: number;
    opacity?: number;
    lift?: number;
    blur?: number;
    children?: React.ReactNode;
  }
> = ({
  crop,
  x,
  y,
  scale,
  pad = 26,
  radius = 26,
  opacity = 1,
  lift = 1,
  blur = 0,
  children,
}) => {
  const w = crop.w + pad * 2;
  const h = crop.h + pad * 2;
  if (opacity <= 0.001) {
    return null;
  }
  return (
    <div
      style={{
        position: "absolute",
        left: x - w / 2,
        top: y - h / 2,
        width: w,
        height: h,
        scale: String(scale),
        opacity,
        borderRadius: radius,
        overflow: "hidden",
        background: crop.bg,
        boxShadow: shadow(scale, lift),
        filter: blur > 0.05 ? `blur(${blur / scale}px)` : undefined,
      }}
    >
      <Img
        src={crop.src}
        style={{
          position: "absolute",
          left: pad,
          top: pad,
          width: crop.w,
          height: crop.h,
        }}
      />
      {children ? (
        <div
          style={{
            position: "absolute",
            left: pad,
            top: pad,
            width: crop.w,
            height: crop.h,
          }}
        >
          {children}
        </div>
      ) : null}
    </div>
  );
};

// A full native capture that brings its own rounded window corners.
export const Window: React.FC<
  Placement & {
    shot: { src: string; w: number; h: number; radius: number };
    opacity?: number;
    lift?: number;
    blur?: number;
  }
> = ({ shot, x, y, scale, opacity = 1, lift = 1, blur = 0 }) => {
  if (opacity <= 0.001) {
    return null;
  }
  return (
    <div
      style={{
        position: "absolute",
        left: x - shot.w / 2,
        top: y - shot.h / 2,
        width: shot.w,
        height: shot.h,
        scale: String(scale),
        opacity,
        // Slightly wider than the capture's own corner to hide its white matte.
        borderRadius: shot.radius + 3,
        overflow: "hidden",
        boxShadow: shadow(scale, lift),
        filter: blur > 0.05 ? `blur(${blur / scale}px)` : undefined,
      }}
    >
      <Img
        src={shot.src}
        style={{ position: "absolute", inset: 0, width: shot.w, height: shot.h }}
      />
    </div>
  );
};
