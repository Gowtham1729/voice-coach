import React from "react";
import { useCurrentFrame } from "remotion";
import { Phrase } from "../components/Phrase";
import { CobaltStage } from "../components/Stage";
import { EASE, ramp } from "../motion";
import { COLORS } from "../theme";
import { SEGMENTS } from "../timeline";

const privacy = SEGMENTS.find((s) => s.id === "privacy");
const cta = SEGMENTS.find((s) => s.id === "cta");
if (!privacy || !cta) {
  throw new Error("Missing privacy or end-card segment");
}
// The iris into the end card starts this many frames into the privacy scene.
const CLOSE = privacy.dur - cta.enter;

const LEFT = 160;
const WHITE = COLORS.white;
const BODY = "rgba(255, 255, 255, 0.9)";

// S07 · the complete privacy line, each sentence landing with the read, then
// the network sentence immediately after, then what stays on the Mac. All of
// it holds until the stage closes.
export const Privacy: React.FC = () => {
  const frame = useCurrentFrame();
  // Gentle settle so the hold is not a frozen frame.
  const drift = 1 + 0.012 * ramp(frame, 40, CLOSE, EASE.linear);
  // Clear the lines while the stage closes into the end-card period.
  const clear = 1 - ramp(frame, CLOSE + 2, CLOSE + 28, EASE.inOut);
  return (
    <CobaltStage>
      <div
        style={{
          position: "absolute",
          inset: 0,
          scale: String(drift),
          transformOrigin: "30% 50%",
          opacity: clear,
        }}
      >
        <Phrase text="No account." at={40} size={96} color={WHITE} dot={WHITE} x={LEFT} baseline={372} />
        <Phrase text="No recording uploads." at={102} size={96} color={WHITE} dot={WHITE} x={LEFT} baseline={476} />
        <Phrase text="No analytics." at={202} size={96} color={WHITE} dot={WHITE} x={LEFT} baseline={580} />
        <Phrase
          text="Update checks and optional model downloads use the network."
          role="body"
          at={286}
          stagger={2}
          size={44}
          color={BODY}
          x={LEFT}
          baseline={692}
        />
        <Phrase
          text="Your recordings, transcripts, analysis, and language chat stay on your Mac."
          role="body"
          at={487}
          stagger={2}
          size={44}
          color={BODY}
          x={LEFT}
          baseline={768}
        />
      </div>
    </CobaltStage>
  );
};
