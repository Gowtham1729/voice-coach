import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const root = fileURLToPath(new URL("../website/", import.meta.url));
const hosting = JSON.parse(
  readFileSync(new URL("../.openai/hosting.json", import.meta.url), "utf8"),
);
assert.equal(
  hosting.static.directory,
  "dist",
  "Sites static output must use the supported dist root",
);
const html = readFileSync(resolve(root, "index.html"), "utf8");
const normalizedHtml = html.replace(/\s+/g, " ");
const css = readFileSync(resolve(root, "styles.css"), "utf8");
const js = readFileSync(resolve(root, "app.js"), "utf8");
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
assert.equal(new Set(ids).size, ids.length, "HTML IDs must be unique");
const urls = new Set([
  ...[...html.matchAll(/\b(?:src|href|poster)="([^"]+)"/g)].map(
    (match) => match[1],
  ),
  ...[...css.matchAll(/url\(['"]?([^'"\)]+)['"]?\)/g)].map((match) => match[1]),
  ...[...js.matchAll(/['"](assets\/[^'"\s]+)['"]/g)].map((match) => match[1]),
]);
for (const url of urls) {
  if (url === "#" || url.startsWith("https://")) continue;
  if (url.startsWith("#"))
    assert.ok(ids.includes(url.slice(1)), `Missing anchor: ${url}`);
  else assert.ok(existsSync(resolve(root, url)), `Missing local asset: ${url}`);
}
for (const match of html.matchAll(
  /\baria-(?:controls|labelledby)="([^"]+)"/g,
)) {
  for (const id of match[1].split(" "))
    assert.ok(ids.includes(id), `Missing ARIA target: ${id}`);
}
assert.ok(
  !/<script[^>]+src="https?:/i.test(html),
  "No external script dependency",
);
assert.ok(
  !/getUserMedia|MediaRecorder|sendBeacon/.test(js),
  "Marketing page must not record audio or send analytics",
);
assert.ok(!html.includes("—"), "Landing-page strings must not use em dashes");
assert.ok(!js.includes("—"), "Interactive strings must not use em dashes");
for (const requiredCopy of [
  "Practice how you sound,",
  "Record with your mic",
  "Capture Mac audio",
  "Import a file",
  "There’s no YouTube URL import.",
  "Your pauses averaged longer than this take needs,",
  "No account, no upload, no cloud processing.",
  "Free while in early access. No account required.",
  "Is this an AI speech coach?",
  "No. It’s a private practice studio. Core Insights use acoustic rules (pauses and pitch). The practice loop does not require sending your voice to a cloud AI service.",
  "System audio access is needed when you capture Mac audio.",
  "Your pitch stayed in a narrow range, the line sounds flat.",
  "On the next take, vary pitch more on the key words.",
]) {
  assert.ok(
    normalizedHtml.includes(requiredCopy),
    `Missing required v2 copy: ${requiredCopy}`,
  );
}
assert.equal(
  html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/)[1]
    .replace(/<[^>]+>/g, "")
    .replace(/\s+/g, " ")
    .trim(),
  "Practice how you sound, privately, on your Mac.",
  "Keep the complete frozen headline at every viewport",
);
assert.ok(
  !html.includes("Free while in early access ·") &&
    !html.includes("needed only when you capture Mac audio for Mimic"),
  "Do not restore the superseded commercial or Mimic-only permission copy",
);
for (const bannedClaim of [
  "YouTube URL importer",
  "confidence score",
  "personality score",
  "accent grade",
]) {
  assert.ok(!html.includes(bannedClaim), `Unsupported claim found: ${bannedClaim}`);
}
execFileSync(process.execPath, ["--check", resolve(root, "app.js")], {
  stdio: "inherit",
});
console.log(
  `Website verified: ${urls.size} references, ${ids.length} unique IDs, valid ARIA targets, JavaScript syntax, and no external scripts.`,
);
