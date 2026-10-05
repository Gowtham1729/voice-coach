import { loadFont } from "@remotion/fonts";
import React, { useEffect, useState } from "react";
import { cancelRender, continueRender, delayRender, staticFile } from "remotion";
import { FONT } from "./theme";

let loaded = false;
let loading: Promise<void> | null = null;

const loadPromoFonts = (): Promise<void> => {
  if (loading) {
    return loading;
  }
  loading = Promise.all([
    loadFont({
      family: FONT.display,
      url: staticFile("promo-2026-10-04/fonts/space-grotesk-bold.ttf"),
      weight: "700",
    }),
    loadFont({
      family: FONT.body,
      url: staticFile("promo-2026-10-04/fonts/dm-sans.ttf"),
      weight: "400",
    }),
  ]).then(() => {
    loaded = true;
  });
  return loading;
};

// measureText() caches its first answer, so nothing that measures type may
// render until both faces exist.
export const FontsGate: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const [ready, setReady] = useState(loaded);
  const [handle] = useState(() =>
    loaded ? null : delayRender("Loading promo fonts"),
  );

  useEffect(() => {
    if (ready) {
      if (handle !== null) {
        continueRender(handle);
      }
      return;
    }
    loadPromoFonts()
      .then(() => setReady(true))
      .catch((err) => cancelRender(err));
  }, [ready, handle]);

  return ready ? <>{children}</> : null;
};
