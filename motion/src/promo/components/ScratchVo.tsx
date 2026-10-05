import { Audio } from "@remotion/media";
import React from "react";
import { Sequence, staticFile } from "remotion";
import { VO, voFrames } from "../timeline";

// Finished soundtrack: voice plus Calculated Grace. Rebuild with scripts/mix-score.py.
export const FinalVo: React.FC = () => (
  <Audio src={staticFile("promo-2026-10-04/vo/ichido-promo-mix.wav")} />
);

// Pacing guide only; files come from scripts/make-scratch-vo.sh and stay untracked.
export const ScratchVo: React.FC = () => (
  <>
    {VO.map((line) => (
      <Sequence
        key={line.id}
        name={`Scratch ${line.id}`}
        from={line.at}
        durationInFrames={voFrames(line.dur) + 2}
        layout="none"
      >
        <Audio src={staticFile(`promo-2026-10-04/scratch-vo/${line.id}.wav`)} />
      </Sequence>
    ))}
  </>
);
