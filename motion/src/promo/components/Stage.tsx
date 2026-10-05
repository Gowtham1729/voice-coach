import React from "react";
import { AbsoluteFill } from "remotion";
import { COLORS } from "../theme";

// Paper with a faint bright centre so dark product panels sit on a lit surface.
export const Paper: React.FC<{ children?: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill
    style={{
      backgroundColor: COLORS.paper,
      backgroundImage: `radial-gradient(ellipse 70% 60% at 50% 46%, ${COLORS.paperBright} 0%, rgba(251, 248, 239, 0) 100%)`,
      overflow: "hidden",
    }}
  >
    {children}
  </AbsoluteFill>
);

export const CobaltStage: React.FC<{ children?: React.ReactNode }> = ({
  children,
}) => (
  <AbsoluteFill
    style={{ backgroundColor: COLORS.cobalt, overflow: "hidden" }}
  >
    {children}
  </AbsoluteFill>
);
