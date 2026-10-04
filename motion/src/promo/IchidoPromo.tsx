import { linearTiming, TransitionSeries } from "@remotion/transitions";
import React from "react";
import { AbsoluteFill, Freeze } from "remotion";
import { Guides } from "./components/Guides";
import { ScratchVo } from "./components/ScratchVo";
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

export type PromoProps = {
  guides: boolean;
  scratchVo: boolean;
};

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

export const IchidoPromo: React.FC<PromoProps> = ({ guides, scratchVo }) => (
  <AbsoluteFill>
    <Paper />
    <FontsGate>
      <Timeline />
      {scratchVo ? <ScratchVo /> : null}
      {guides ? <Guides /> : null}
    </FontsGate>
  </AbsoluteFill>
);

export const StyleFrame: React.FC<{ frame: number; guides: boolean }> = ({
  frame,
  guides,
}) => (
  <Freeze frame={frame}>
    <IchidoPromo guides={guides} scratchVo={false} />
  </Freeze>
);

const SCENES: Record<SegmentId, React.FC> = {
  opening: Opening,
  picker: Picker,
  listen: FrenchPractice,
  compare: Compare,
  recording: Recording,
  privacy: Privacy,
  cta: Cta,
};

// One scene on its own, for editing it in the Studio.
export const SceneOnly: React.FC<{ scene: SegmentId }> = ({ scene }) => {
  const Scene = SCENES[scene];
  return (
    <AbsoluteFill>
      <Paper />
      <FontsGate>
        <Scene />
      </FontsGate>
    </AbsoluteFill>
  );
};
