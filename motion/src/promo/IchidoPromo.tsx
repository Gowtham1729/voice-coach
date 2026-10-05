import { Audio } from "@remotion/media";
import { linearTiming, TransitionSeries } from "@remotion/transitions";
import React from "react";
import { AbsoluteFill, staticFile } from "remotion";
import { Paper } from "./components/Stage";
import { FontsGate } from "./fonts";
import { ctaLockup, recordingPeriod } from "./layout";
import { EASE } from "./motion";
import { iris, push } from "./presentations";
import { Compare } from "./scenes/Compare";
import { Cta } from "./scenes/Cta";
import { FrenchPractice } from "./scenes/FrenchPractice";
import { Opening } from "./scenes/Opening";
import { Picker } from "./scenes/Picker";
import { Privacy } from "./scenes/Privacy";
import { Recording } from "./scenes/Recording";
import { SEGMENTS, type SegmentId } from "./timeline";

const dur = (id: SegmentId) => {
  const seg = SEGMENTS.find((s) => s.id === id);
  if (!seg) {
    throw new Error(`Unknown segment ${id}`);
  }
  return seg;
};

// Irises run on a linear clock: their radius already grows geometrically.
const timing = (id: SegmentId, easing = EASE.inOut) =>
  linearTiming({ durationInFrames: dur(id).enter, easing });

const Timeline: React.FC = () => {
  const flood = recordingPeriod();
  const close = ctaLockup();
  return (
    <TransitionSeries>
      <TransitionSeries.Sequence name="Opening" durationInFrames={dur("opening").dur}>
        <Opening />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={push({ direction: "up", blur: 12 })}
        timing={timing("picker")}
      />
      <TransitionSeries.Sequence name="Picker" durationInFrames={dur("picker").dur}>
        <Picker />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={push()} timing={timing("listen")} />
      <TransitionSeries.Sequence name="Listen, understand, repeat" durationInFrames={dur("listen").dur}>
        <FrenchPractice />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={push()} timing={timing("compare")} />
      <TransitionSeries.Sequence name="Compare" durationInFrames={dur("compare").dur}>
        <Compare />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={push()} timing={timing("recording")} />
      <TransitionSeries.Sequence name="Recording" durationInFrames={dur("recording").dur}>
        <Recording />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={iris({ x: flood.at.x, y: flood.at.y, radius: flood.radius, mode: "open" })}
        timing={timing("privacy", EASE.linear)}
      />
      <TransitionSeries.Sequence name="Privacy" durationInFrames={dur("privacy").dur}>
        <Privacy />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition
        presentation={iris({ x: close.dot.x, y: close.dot.y, radius: close.dotRadius, mode: "close" })}
        timing={timing("cta", EASE.linear)}
      />
      <TransitionSeries.Sequence name="Get Ichido" durationInFrames={dur("cta").dur}>
        <Cta />
      </TransitionSeries.Sequence>
    </TransitionSeries>
  );
};

export const IchidoPromo: React.FC = () => (
  <AbsoluteFill>
    <Paper />
    <FontsGate>
      <Timeline />
      <Audio src={staticFile("promo-2026-10-04/vo/ichido-promo-mix.wav")} />
    </FontsGate>
  </AbsoluteFill>
);
