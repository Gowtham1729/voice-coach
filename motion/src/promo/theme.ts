export const VIDEO = { width: 1920, height: 1080, fps: 60 } as const;

export const MARGIN = { side: 96, top: 72, bottom: 72 } as const;

export const COLORS = {
  paper: "#f4f1e9",
  paperBright: "#fbf8ef",
  ink: "#1f241f",
  inkSoft: "#4f514c",
  cobalt: "#2848e8",
  cobaltDeep: "#1736c8",
  cobaltPale: "#e8eeff",
  white: "#ffffff",
  // Annotation stroke on the dark product surfaces; brand cobalt alone is too dim there.
  ring: "#5c76ff",
} as const;

export const FONT = {
  display: "Space Grotesk",
  body: "DM Sans",
} as const;

export const STACK = {
  display: `"${FONT.display}", "Helvetica Neue", Arial, sans-serif`,
  body: `"${FONT.body}", "Helvetica Neue", Arial, sans-serif`,
} as const;

export type FontRole = keyof typeof STACK;

export const WEIGHT: Record<FontRole, number> = { display: 700, body: 400 };

// Vertical metrics (em) of the bundled fonts, used to place shapes on a text baseline.
// baseline: distance from the top of a line-height:1 box to the baseline.
export const METRICS: Record<FontRole, { baseline: number; dot: number; dotLift: number; dotLead: number }> = {
  display: { baseline: 0.846, dot: 0.19, dotLift: 0.08, dotLead: 0.055 },
  body: { baseline: 0.841, dot: 0.115, dotLift: 0.0525, dotLead: 0.0425 },
};

export const TRACKING = {
  opening: -0.045,
  chapter: -0.04,
  kicker: 0.15,
} as const;
