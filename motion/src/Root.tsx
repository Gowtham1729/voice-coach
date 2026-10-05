import "./index.css";
import { Composition, Folder } from "remotion";
import { MyComposition } from "./Composition";
import { IchidoPromo, SceneOnly, StyleFrame } from "./promo/IchidoPromo";
import { DURATION, SEGMENTS, START } from "./promo/timeline";

const STYLE_FRAMES = [
  { id: "StyleFrame-1-Hook", frame: START.opening + 110 },
  { id: "StyleFrame-2-Component", frame: START.picker + 206 },
  { id: "StyleFrame-3-Compare", frame: START.compare + 132 },
  { id: "StyleFrame-4-Closing", frame: START.cta + 150 },
  { id: "StyleFrame-5-Understand", frame: START.listen + 470 },
] as const;

const sceneId = (id: string) => `Scene-${id.charAt(0).toUpperCase()}${id.slice(1)}`;

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <MyComposition />
      <Folder name="Ichido-2026-10-04">
        <Composition
          id="IchidoPromo20261004"
          component={IchidoPromo}
          durationInFrames={DURATION}
          fps={60}
          width={1920}
          height={1080}
          defaultProps={{ guides: false, scratchVo: false, finalVo: true }}
        />
        <Composition
          id="IchidoPromo20261004-Animatic"
          component={IchidoPromo}
          durationInFrames={DURATION}
          fps={60}
          width={1920}
          height={1080}
          defaultProps={{ guides: true, scratchVo: true, finalVo: false }}
        />
        {/* Full-length on purpose: a <Still> clips every inner Sequence to one frame. */}
        <Folder name="Style-frames">
          {STYLE_FRAMES.map((still) => (
            <Composition
              key={still.id}
              id={still.id}
              component={StyleFrame}
              durationInFrames={DURATION}
              fps={60}
              width={1920}
              height={1080}
              defaultProps={{ frame: still.frame, guides: false }}
            />
          ))}
        </Folder>
        <Folder name="Scenes">
          {SEGMENTS.map((seg) => (
            <Composition
              key={seg.id}
              id={sceneId(seg.id)}
              component={SceneOnly}
              durationInFrames={seg.dur}
              fps={60}
              width={1920}
              height={1080}
              defaultProps={{ scene: seg.id }}
            />
          ))}
        </Folder>
      </Folder>
    </>
  );
};
