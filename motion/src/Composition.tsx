import { AbsoluteFill, Composition } from "remotion";

export const MyComposition = () => {
  return (
    <Composition
      id="MyComp"
      component={MyComponent}
      durationInFrames={150}
      fps={30}
      width={1920}
      height={1080}
    />
  );
};

const MyComponent: React.FC = () => {
  return <AbsoluteFill style={{ backgroundColor: "#f4f1e9" }} />;
};
