import React from "react";
import { Img, interpolate, useCurrentFrame } from "remotion";
import { BRAND } from "../assets";
import { Dot } from "../components/Dot";
import { Phrase } from "../components/Phrase";
import { Paper } from "../components/Stage";
import { ctaLockup, topForBaseline } from "../layout";
import { EASE, ramp } from "../motion";
import { COLORS, STACK, TRACKING } from "../theme";

// S08 · the cobalt stage closes into the wordmark's period; one action holds.
export const Cta: React.FC = () => {
  const frame = useCurrentFrame();
  const lock = ctaLockup();
  const settle = interpolate(frame, [0, 70], [1.04, 1], {
    extrapolateRight: "clamp",
    easing: EASE.out,
  });
  const button = ramp(frame, 34, 62, EASE.out);

  return (
    <Paper>
      <div
        style={{
          position: "absolute",
          inset: 0,
          scale: String(settle),
          transformOrigin: `${lock.dot.x}px ${lock.dot.y}px`,
        }}
      >
        <Img
          src={BRAND.ribbon.src}
          style={{
            position: "absolute",
            left: lock.ribbon.x,
            top: lock.ribbon.y,
            width: lock.ribbon.w,
            height: lock.ribbon.h,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: lock.wordLeft,
            top: topForBaseline(lock.baseline, lock.size),
            fontFamily: STACK.display,
            fontWeight: 700,
            fontSize: lock.size,
            lineHeight: 1,
            letterSpacing: `${TRACKING.chapter}em`,
            color: COLORS.ink,
            whiteSpace: "nowrap",
          }}
        >
          ichido
        </div>
      </div>
      <Dot x={lock.dot.x} y={lock.dot.y} radius={lock.dotRadius} />

      <div
        style={{
          position: "absolute",
          left: 960,
          top: 610,
          translate: `-50% calc(-50% + ${(1 - button) * 18}px)`,
          scale: String(0.97 + 0.03 * button),
          opacity: button,
          display: "flex",
          alignItems: "center",
          gap: 18,
          height: 92,
          padding: "0 44px",
          borderRadius: 999,
          background: COLORS.cobalt,
          color: COLORS.white,
          boxShadow: "0 22px 54px rgba(40, 72, 232, 0.26)",
          fontFamily: STACK.display,
          fontWeight: 700,
          fontSize: 36,
          letterSpacing: "-0.01em",
          whiteSpace: "nowrap",
        }}
      >
        Get Ichido for Mac
        <Img src={BRAND.arrowDown} style={{ width: 30, height: 30, filter: "invert(1)" }} />
      </div>
      <Phrase
        text="Free while in early access · macOS 26+"
        role="body"
        at={44}
        stagger={2}
        size={36}
        color={COLORS.inkSoft}
        align="center"
        x={960}
        baseline={730}
      />
    </Paper>
  );
};
