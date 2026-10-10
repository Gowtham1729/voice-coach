import "./check-website.mjs";
import { createHash } from "node:crypto";
import { cpSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { extname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const source = fileURLToPath(new URL("../website/", import.meta.url));
const output = fileURLToPath(new URL("../dist/", import.meta.url));

// Firebase Hosting publishes dist/. Keep authoring in website/.
rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });
cpSync(source, output, { recursive: true });

const textExtensions = new Set([".html", ".css", ".js"]);
const hashedExtensions = new Set([
  ".js", ".css", ".svg", ".png", ".jpg", ".jpeg", ".webp", ".avif", ".gif",
  ".ico", ".woff2", ".ttf", ".mp4", ".vtt",
]);

function walk(dir) {
  const files = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...walk(full));
    else files.push(full);
  }
  return files;
}

function relPosix(file) {
  return relative(output, file).split(sep).join("/");
}

function rewrite(file, replacements) {
  const keys = [...replacements.keys()].sort((a, b) => b.length - a.length);
  let text = readFileSync(file, "utf8");
  for (const key of keys) {
    if (text.includes(key)) text = text.replaceAll(key, replacements.get(key));
  }
  writeFileSync(file, text);
}

function hashFile(file) {
  const before = relPosix(file);
  const ext = extname(file);
  const hash = createHash("sha256").update(readFileSync(file)).digest("hex").slice(0, 10);
  const next = file.slice(0, -ext.length) + `.${hash}${ext}`;
  renameSync(file, next);
  return [before, relPosix(next)];
}

const replacements = new Map();
for (const file of walk(output)) {
  const ext = extname(file);
  if (!hashedExtensions.has(ext) || textExtensions.has(ext)) continue;
  const [before, after] = hashFile(file);
  replacements.set(before, after);
}

for (const ext of [".css", ".js"]) {
  const files = walk(output).filter((file) => extname(file) === ext);
  for (const file of files) rewrite(file, replacements);
  for (const file of files) {
    const [before, after] = hashFile(file);
    replacements.set(before, after);
  }
}

for (const file of walk(output).filter((item) => extname(item) === ".html")) {
  rewrite(file, replacements);
}

console.log(`Static website built in dist/ with ${replacements.size} fingerprinted assets.`);
