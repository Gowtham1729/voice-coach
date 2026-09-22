import "./check-website.mjs";
import { cpSync, mkdirSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";

const source = fileURLToPath(new URL("../website/", import.meta.url));
const output = fileURLToPath(new URL("../dist/", import.meta.url));

// Sites accepts conventional static output roots. Keep authoring in website/.
rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });
cpSync(source, output, { recursive: true });
console.log("Static website built in dist/.");
