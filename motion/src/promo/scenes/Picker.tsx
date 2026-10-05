import React from "react";
import {
  AbsoluteFill,
  Img,
  interpolateColors,
  spring,
  useCurrentFrame,
} from "remotion";
import { PRODUCT, UI } from "../assets";
import { Cursor, type CursorScript } from "../components/Cursor";
import { FocusRing } from "../components/FocusRing";
import { Kicker } from "../components/Kicker";
import { Phrase } from "../components/Phrase";
import { UiPanel, Window } from "../components/UiPanel";
import {
  EASE,
  follow,
  lerp,
  mixPlacement,
  mixRect,
  pulse,
  ramp,
  toScreen,
  type Placement,
} from "../motion";

const home = PRODUCT.home;
const picker = PRODUCT.picker;
const bar = UI.homeActions;

const WINDOW: Placement = { x: 960, y: 560, scale: 0.4 };
// Home actions as they sit inside the window, then lifted toward the viewer
// so that Reference practice… is centred where the picker will open.
const BAR_IN_WINDOW: Placement = {
  x: WINDOW.x + (home.at.homeActions.x + bar.w / 2 - home.w / 2) * WINDOW.scale,
  y: WINDOW.y + (home.at.homeActions.y + bar.h / 2 - home.h / 2) * WINDOW.scale,
  scale: WINDOW.scale,
};
const BAR: Placement = { x: 1243, y: 535.5, scale: 1 };
const SHEET: Placement = { x: 1250, y: 540, scale: 0.66 };

const BUTTON = toScreen(bar, BAR, bar.at.referencePractice);
const SHEET_RECT = toScreen(picker, SHEET, { x: 0, y: 0, w: picker.w, h: picker.h });
const IMPORT = toScreen(picker, SHEET, picker.at.import);
const CAPTURE = toScreen(picker, SHEET, picker.at.capture);

const CLICK = 114;
const OPEN_AT = CLICK + 2;

// Hover at the trailing end of each button so its label stays readable.
const POINTER: CursorScript = {
  from: { x: 1580, y: 990 },
  show: 76,
  moves: [
    { at: 106, to: { x: 1262, y: 547 }, dur: 26, arc: 0.1 },
    { at: 188, to: { x: IMPORT.x + IMPORT.w - 16, y: IMPORT.y + IMPORT.h - 7 }, dur: 22, arc: -0.08 },
    { at: 252, to: { x: CAPTURE.x + CAPTURE.w - 14, y: CAPTURE.y + CAPTURE.h - 7 }, dur: 22, arc: 0.06 },
  ],
  clicks: [CLICK],
};

// S02: brief native window, Reference practice… is pressed and the real
// picker opens from that button. Import and Capture get focus, not clicks.
export const Picker: React.FC = () => {
  const frame = useCurrentFrame();

  const lift = ramp(frame, 60, 102, EASE.inOut);
  const windowFade = ramp(frame, 64, 104, EASE.inOut);
  const barPlace = mixPlacement(BAR_IN_WINDOW, BAR, lift);
  const press = ramp(frame, CLICK - 2, CLICK + 2, EASE.ui);
  // About 15 frames to full size, a ~3% overshoot, settled within ~20 more.
  const grow = spring({
    frame: frame - OPEN_AT,
    fps: 60,
    config: { damping: 18, stiffness: 180, mass: 0.8 },
  });
  const open = Math.min(grow, 1);
  const settle = Math.max(grow, 1);
  const container = mixRect(BUTTON, SHEET_RECT, open);
  const barFade = ramp(frame, CLICK, CLICK + 16, EASE.ui);

  const lineOne = 1 - 0.68 * ramp(frame, 226, 240, EASE.ui);
  const lineTwo =
    1 - 0.68 * ramp(frame, 184, 198, EASE.ui) + 0.68 * ramp(frame, 226, 240, EASE.ui);

  const inputRing = follow(frame, IMPORT, [{ at: 250, to: CAPTURE, dur: 24 }], mixRect);

  return (
    <AbsoluteFill>
      <Window
        shot={home}
        x={WINDOW.x}
        y={WINDOW.y}
        scale={WINDOW.scale * (1 - 0.03 * windowFade)}
        opacity={1 - windowFade}
        blur={8 * windowFade}
      />

      <UiPanel
        crop={bar}
        {...barPlace}
        pad={lerp(0, 22, lift)}
        radius={lerp(0, 24, lift)}
        lift={lift}
        opacity={1 - barFade}
      >
        <div
          style={{
            position: "absolute",
            left: bar.at.referencePractice.x,
            top: bar.at.referencePractice.y,
            width: bar.at.referencePractice.w,
            height: bar.at.referencePractice.h,
            borderRadius: 11,
            background: `rgba(0, 0, 0, ${0.2 * press})`,
          }}
        />
      </UiPanel>

      {frame >= OPEN_AT ? (
        <div
          style={{
            position: "absolute",
            left: container.x,
            top: container.y,
            width: container.w,
            height: container.h,
            scale: String(settle),
            borderRadius: lerp(11, picker.radius * SHEET.scale + 2, open),
            overflow: "hidden",
            background: interpolateColors(open, [0, 0.4], ["#d6d3da", picker.bg]),
            boxShadow: `0 ${30 * open}px ${70 * open}px rgba(23, 29, 26, ${0.26 * open}), 0 2px 8px rgba(23, 29, 26, 0.12)`,
          }}
        >
          {/* maxWidth: Tailwind's preflight would shrink these to the growing container. */}
          <Img
            src={bar.src}
            style={{
              position: "absolute",
              left: BUTTON.x - container.x - bar.at.referencePractice.x,
              top: BUTTON.y - container.y - bar.at.referencePractice.y,
              width: bar.w,
              height: bar.h,
              maxWidth: "none",
              opacity: 1 - ramp(open, 0, 0.22, EASE.linear),
              filter: "brightness(0.82)",
            }}
          />
          <Img
            src={picker.src}
            style={{
              position: "absolute",
              left: SHEET_RECT.x - container.x,
              top: SHEET_RECT.y - container.y,
              width: SHEET_RECT.w,
              height: SHEET_RECT.h,
              maxWidth: "none",
              opacity: ramp(open, 0.22, 0.8, EASE.linear),
              scale: String(lerp(0.96, 1, open)),
            }}
          />
        </div>
      ) : null}

      <Kicker text="Reference practice" at={126} y={404} />
      <Phrase text="Import a clip" at={134} size={72} x={96} baseline={520} opacity={lineOne} />
      <Phrase
        text="Capture Mac audio"
        at={142}
        size={72}
        x={96}
        baseline={610}
        opacity={lineTwo}
      />

      <FocusRing rect={BUTTON} radius={11} opacity={pulse(frame, 96, CLICK - 2, 8, 6)} />
      <FocusRing rect={inputRing} radius={8} opacity={pulse(frame, 184, 330, 8, 10)} />
      <Cursor script={POINTER} />
    </AbsoluteFill>
  );
};
