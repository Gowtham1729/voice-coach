import "./index.css";
import { Composition, Folder } from "remotion";
import { MyComposition } from "./Composition";
import { IchidoPromo } from "./promo/IchidoPromo";
import { DURATION } from "./promo/timeline";

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
        />
      </Folder>
    </>
  );
};
