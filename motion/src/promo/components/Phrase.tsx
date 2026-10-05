import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { EASE } from "../motion";
import { topForBaseline } from "../layout";
import { COLORS, STACK, WEIGHT, type FontRole } from "../theme";
import { InlineDot } from "./Dot";

export type PhraseProps = {
  text: string; // "\n" starts a new line
  at: number; // first word starts to rise
  stagger?: number;
  dur?: number;
  out?: number; // words leave upward from this frame
  outStagger?: number;
  outDur?: number;
  size: number;
  role?: FontRole;
  color?: string;
  // Colour of display-type periods; null keeps the glyph in the text colour.
  dot?: string | null;
  tracking?: number; // em
  lineHeight?: number;
  align?: "left" | "center" | "right";
  // Absolute placement: x is the left, centre or right edge per `align`.
  x?: number;
  baseline?: number;
  opacity?: number;
  style?: React.CSSProperties;
};

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

// Words rise through a mask one after another, then hold. Exits lift them out
// the same way so a phrase never fades through a busy frame.
export const Phrase: React.FC<PhraseProps> = ({
  text,
  at,
  stagger = 4,
  dur = 30,
  out,
  outStagger = 2,
  outDur = 18,
  size,
  role = "display",
  color = COLORS.ink,
  dot = COLORS.cobalt,
  tracking = role === "display" ? -0.04 : 0,
  lineHeight = 1,
  align = "left",
  x,
  baseline,
  opacity = 1,
  style,
}) => {
  const frame = useCurrentFrame();
  const lines = text.split("\n");
  // Leading above 1 deepens each word's mask, so the travel grows with it;
  // otherwise glyph tips show before entry and descenders after exit.
  const lead = Math.max(0, lineHeight - 1);
  let index = 0;

  const placed: React.CSSProperties =
    x === undefined || baseline === undefined
      ? {}
      : {
          position: "absolute",
          top: topForBaseline(baseline, size, role, lineHeight),
          ...(align === "left"
            ? { left: x }
            : align === "right"
              ? { right: 1920 - x }
              : { left: x, translate: "-50% 0" }),
        };

  return (
    <div
      style={{
        fontFamily: STACK[role],
        fontWeight: WEIGHT[role],
        fontSize: size,
        letterSpacing: `${tracking}em`,
        lineHeight,
        color,
        textAlign: align,
        opacity,
        ...placed,
        ...style,
      }}
    >
      {lines.map((line, li) => (
        <div key={li} style={{ whiteSpace: "nowrap" }}>
          {line.split(" ").map((word, wi) => {
            const i = index++;
            const start = at + i * stagger;
            const enter = interpolate(frame, [start, start + dur], [0, 1], {
              ...CLAMP,
              easing: EASE.out,
            });
            const leave =
              out === undefined
                ? 0
                : interpolate(
                    frame,
                    [out + i * outStagger, out + i * outStagger + outDur],
                    [0, 1],
                    { ...CLAMP, easing: EASE.in },
                  );
            const accent =
              dot !== null && role === "display" && word.endsWith(".");
            const body = accent ? word.slice(0, -1) : word;
            return (
              <React.Fragment key={wi}>
                {wi > 0 ? " " : null}
                <span
                  style={{
                    display: "inline-block",
                    overflow: "hidden",
                    verticalAlign: "top",
                    padding: "0.12em 0.08em 0.24em",
                    margin: "-0.12em -0.08em -0.24em",
                  }}
                >
                  <span
                    style={{
                      display: "inline-block",
                      translate: `0 ${(1 - enter) * (1.2 + lead) - leave * (1.3 + lead)}em`,
                    }}
                  >
                    {body}
                    {accent ? (
                      <InlineDot role={role} color={dot ?? undefined} />
                    ) : null}
                  </span>
                </span>
              </React.Fragment>
            );
          })}
        </div>
      ))}
    </div>
  );
};
