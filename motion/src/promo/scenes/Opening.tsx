import React from "react";
import { AbsoluteFill, Img, interpolate, useCurrentFrame } from "remotion";
import { BRAND } from "../assets";
import { Dot } from "../components/Dot";
import { Phrase } from "../components/Phrase";
import { openingLockup, openingRow, OPENING } from "../layout";
import { EASE, lerp, mixPoint, mixRect, ramp } from "../motion";
import { COLORS, METRICS, TRACKING } from "../theme";

// S01 → start of S02. "One more try." lands with the ribbon; the words leave,
// and its cobalt period travels to become the period of the ichido wordmark.
export const Opening: React.FC = () => {
  const frame = useCurrentFrame();
  const row = openingRow();
  const lock = openingLockup();
  const m = METRICS.display;

  const ribbonIn = ramp(frame, 6, 44, EASE.out);
  const toLockup = ramp(frame, 130, 190, EASE.inOut);
  const ribbon = mixRect(row.ribbon, lock.ribbon, toLockup);

  const dotPop = interpolate(frame, [44, 53, 66], [0, 1.22, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: [EASE.out, EASE.inOut],
  });
  const dot = mixPoint(row.dot, lock.dot, toLockup);
  const dotRadius = lerp(row.dotRadius, lock.dotRadius, toLockup);

  // The wordmark rides on the travelling period at its final size.
  const baseline = lerp(row.baseline, lock.baseline, toLockup);
  const wordLeft = dot.x - (m.dotLead + m.dot / 2) * lock.size - lock.wordWidth;

  // A slow push through the whole hold keeps the opening alive.
  const drift = interpolate(frame, [0, 322], [1, 1.035]);

  return (
    <AbsoluteFill style={{ scale: String(drift) }}>
      <Img
        src={BRAND.ribbon.src}
        style={{
          position: "absolute",
          left: ribbon.x,
          top: ribbon.y,
          width: ribbon.w,
          height: ribbon.h,
          clipPath: `inset(-10% ${(1 - ribbonIn) * 100}% -10% 0)`,
          translate: `${(1 - ribbonIn) * -24}px 0px`,
        }}
      />
      <Phrase
        text="One more try"
        at={12}
        stagger={5}
        dur={34}
        out={128}
        outStagger={3}
        outDur={22}
        size={OPENING.phraseSize}
        tracking={TRACKING.opening}
        x={row.phraseLeft}
        baseline={row.baseline}
      />
      <Phrase
        text="ichido"
        at={150}
        dur={34}
        size={lock.size}
        tracking={TRACKING.chapter}
        x={wordLeft}
        baseline={baseline}
      />
      <Dot
        x={dot.x}
        y={dot.y}
        radius={dotRadius * dotPop}
        color={COLORS.cobalt}
      />
      <Phrase
        text="Your private speaking room for Mac."
        role="body"
        at={188}
        stagger={3}
        dur={30}
        size={46}
        color={COLORS.inkSoft}
        align="center"
        x={960}
        baseline={lock.baseline + 96}
      />
    </AbsoluteFill>
  );
};
