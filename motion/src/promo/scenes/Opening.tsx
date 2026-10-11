import React from "react";
import { AbsoluteFill, Img, interpolate, useCurrentFrame } from "remotion";
import { BRAND } from "../assets";
import { Dot } from "../components/Dot";
import { Phrase } from "../components/Phrase";
import { lockup } from "../layout";
import { EASE, ramp } from "../motion";
import { TRACKING } from "../theme";

// 60 fps. One shot, then the picker push at frame 390.
// The wordmark stays. The line under it changes, so this is not two title cards.
// 0–72: ribbon and "ichido." settle near center.
// 64–112: the mark rises as "Learn a phrase. Rehearse a talk." arrives under it.
// 188–203: that line leaves upward.
// 208–246: "Record yourself. / Hear how you said it." rises into the same place.
const MARK_AT = 8;
const JOB_AT = 72;
const JOB_OUT = 188;
const ACTION_AT = 208;

export const Opening: React.FC = () => {
  const frame = useCurrentFrame();
  const baseline = interpolate(frame, [64, 112], [560, 440], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: EASE.out,
  });
  const lock = lockup(120, 960, baseline);
  const ribbonIn = ramp(frame, MARK_AT - 4, MARK_AT + 14, EASE.out);
  const dotIn = ramp(frame, MARK_AT + 4, MARK_AT + 18, EASE.out);
  const drift = interpolate(frame, [0, 446], [1, 1.018], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ scale: String(drift) }}>
      <Img
        src={BRAND.ribbon.src}
        style={{
          position: "absolute",
          left: lock.ribbon.x,
          top: lock.ribbon.y,
          width: lock.ribbon.w,
          height: lock.ribbon.h,
          clipPath: `inset(-12% ${(1 - ribbonIn) * 100}% -12% 0)`,
          translate: `${(1 - ribbonIn) * -16}px 0px`,
        }}
      />
      <Phrase
        text="ichido"
        at={MARK_AT}
        dur={14}
        size={lock.size}
        tracking={TRACKING.chapter}
        dot={null}
        x={lock.wordLeft}
        baseline={lock.baseline}
      />
      <Dot x={lock.dot.x} y={lock.dot.y} radius={lock.dotRadius * dotIn} />
      <Phrase
        text="Learn a phrase. Rehearse a talk."
        at={JOB_AT}
        stagger={3}
        dur={14}
        out={JOB_OUT}
        outStagger={1}
        outDur={10}
        size={80}
        align="center"
        x={960}
        baseline={660}
      />
      <Phrase
        text={"Record yourself.\nHear how you said it."}
        at={ACTION_AT}
        stagger={4}
        dur={16}
        size={80}
        lineHeight={1.22}
        align="center"
        x={960}
        baseline={660}
      />
    </AbsoluteFill>
  );
};
