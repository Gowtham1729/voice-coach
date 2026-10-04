import type {
  TransitionPresentation,
  TransitionPresentationComponentProps,
} from "@remotion/transitions";
import React, { useId } from "react";
import { AbsoluteFill } from "remotion";
import { VIDEO } from "./theme";

type PushProps = { direction: "left" | "up"; blur: number };

// Both scenes travel together across one continuous paper surface. Directional
// blur follows the speed of the move; a new example always arrives this way.
const PushPresentation: React.FC<
  TransitionPresentationComponentProps<PushProps>
> = ({ children, presentationDirection, presentationProgress, passedProps }) => {
  const id = `push-${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
  const p = presentationProgress;
  const horizontal = passedProps.direction === "left";
  const span = horizontal ? VIDEO.width : VIDEO.height;
  const offset =
    presentationDirection === "entering" ? (1 - p) * span : -p * span;
  const blur = passedProps.blur * Math.sin(Math.PI * p);
  const blurred = blur > 0.3;
  return (
    <AbsoluteFill
      style={{ translate: horizontal ? `${offset}px 0px` : `0px ${offset}px` }}
    >
      {blurred ? (
        <svg width={0} height={0} style={{ position: "absolute" }}>
          <defs>
            <filter
              id={id}
              x="-5%"
              y="-5%"
              width="110%"
              height="110%"
              colorInterpolationFilters="sRGB"
            >
              <feGaussianBlur
                stdDeviation={horizontal ? `${blur} 0` : `0 ${blur}`}
              />
            </filter>
          </defs>
        </svg>
      ) : null}
      <AbsoluteFill style={{ filter: blurred ? `url(#${id})` : undefined }}>
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const push = (
  props: Partial<PushProps> = {},
): TransitionPresentation<PushProps> => ({
  component: PushPresentation,
  props: { direction: props.direction ?? "left", blur: props.blur ?? 26 },
});

type IrisProps = { x: number; y: number; radius: number; mode: "open" | "close" };

const farthestCorner = (x: number, y: number) =>
  Math.max(
    Math.hypot(x, y),
    Math.hypot(VIDEO.width - x, y),
    Math.hypot(x, VIDEO.height - y),
    Math.hypot(VIDEO.width - x, VIDEO.height - y),
  ) + 4;

// "open": the next scene appears through a dot that swells to fill the frame.
// "close": the current scene shrinks back into a dot on the next scene.
// Radius grows geometrically, which reads as an even zoom through the dot.
const IrisPresentation: React.FC<
  TransitionPresentationComponentProps<IrisProps>
> = ({ children, presentationDirection, presentationProgress, passedProps }) => {
  const { x, y, radius, mode } = passedProps;
  const far = farthestCorner(x, y);
  const grow = (t: number) => radius * Math.pow(far / radius, t);

  if (mode === "open") {
    if (presentationDirection === "exiting") {
      return <AbsoluteFill>{children}</AbsoluteFill>;
    }
    const r = grow(presentationProgress);
    return (
      <AbsoluteFill style={{ clipPath: `circle(${r}px at ${x}px ${y}px)` }}>
        {children}
      </AbsoluteFill>
    );
  }

  if (presentationDirection === "exiting") {
    return <AbsoluteFill>{children}</AbsoluteFill>;
  }
  // The entering scene is drawn on top, so it is shown outside the shrinking dot.
  const r = grow(1 - presentationProgress);
  const mask = `radial-gradient(circle at ${x}px ${y}px, transparent ${r - 0.75}px, #000 ${r + 0.75}px)`;
  return (
    <AbsoluteFill style={{ maskImage: mask, WebkitMaskImage: mask }}>
      {children}
    </AbsoluteFill>
  );
};

export const iris = (props: IrisProps): TransitionPresentation<IrisProps> => ({
  component: IrisPresentation,
  props,
});
