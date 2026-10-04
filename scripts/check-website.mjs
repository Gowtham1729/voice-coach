import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
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
assert.ok(
  html.includes('href="https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip"'),
  "Website download must follow GitHub's latest release",
);
assert.ok(
  !/releases\/(?:tag|download)\/v\d/.test(html),
  "Website links must not pin an old release",
);
const css = readFileSync(resolve(root, "styles.css"), "utf8");
const modules = readdirSync(root).filter((file) => file.endsWith(".js"));
const js = modules.map((file) => readFileSync(resolve(root, file), "utf8")).join("\n");
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
assert.equal(new Set(ids).size, ids.length, "HTML IDs must be unique");
const urls = new Set([
  ...[...html.matchAll(/\b(?:src|href|poster)="([^"]+)"/g)].map(
    (match) => match[1],
  ),
  ...[...css.matchAll(/url\(['"]?([^'"\)]+)['"]?\)/g)].map((match) => match[1]),
  ...[...js.matchAll(/['"](assets\/[^'"\s]+)['"]/g)].map((match) => match[1]),
  ...[...js.matchAll(/\bfrom ["']\.\/([^"']+)["']/g)].map((match) => match[1]),
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
  !/getUserMedia|MediaRecorder|sendBeacon|AudioContext/.test(js),
  "Marketing page must not capture or synthesize audio, or send analytics",
);
assert.ok(!html.includes("—"), "Landing-page strings must not use em dashes");
assert.ok(!js.includes("—"), "Interactive strings must not use em dashes");
for (const requiredCopy of [
  "Your private speaking room for Mac",
  "Record with your mic", "Capture Mac audio", "Import a file",
  "Choose Capture Mac audio to use it as a reference.",
  "When enough words reliably match, two measured practice targets",
  "AI can be wrong.",
  "Words can’t hear or evaluate your audio.",
  "Free while in early access. No account required.",
  "System audio access is needed when you capture Mac audio.",
  "Real app captures", "Earlier Voice Coach footage.",
]) {
  assert.ok(normalizedHtml.includes(requiredCopy), `Missing product boundary: ${requiredCopy}`);
}
assert.ok(!/confidence score|personality score/.test(html), "No unsupported subjective scores");
assert.equal((html.match(/\brole="tab"/g) || []).length, 3, "The reference loop has three accessible tabs");
assert.equal((html.match(/practise/gi) || []).length, 0, "Website copy uses practice, not practise");
assert.ok(html.includes(">A real practice session<"), "Practice-session heading is sentence case");
assert.ok(!html.includes("A REAL PRACTICE SESSION"), "Practice-session heading is not shouted");
assert.ok(!html.includes("YOUR VOICE BELONGS TO YOU"), "The privacy sign-off line is removed");
assert.ok(
  html.includes("Version 0.0.3 · Early access · macOS 26+"),
  "Download line stays Version 0.0.3",
);
assert.ok(
  html.includes("Record a take. Try again, or practice against a reference."),
  "Hero subhead is the agreed short line",
);
assert.ok(
  !html.includes("Record a take, then try another take, or practice against a reference."),
  "Hero subhead is not the longer alternate",
);
assert.ok(
  html.includes(
    'content="Ichido is your private speaking room for Mac. Record a take, practice with a reference, and try again."',
  ),
  "Meta description matches the brief",
);
assert.ok(!html.includes('data-insight="understand"'), "Understand is not a numbered demo step");
for (const nav of html.matchAll(/<nav\b[^>]*>[\s\S]*?<\/nav>/g)) {
  assert.ok(!/>Words</.test(nav[0]), "Words is not a navigation item");
}
assert.ok(html.includes('id="screenshot-dialog"'), "Real screenshots can be viewed at a readable size");
for (const module of modules) {
  execFileSync(process.execPath, ["--check", resolve(root, module)], {
    stdio: "inherit",
  });
}
console.log(
  `Website verified: ${urls.size} references, ${ids.length} unique IDs, valid ARIA targets, JavaScript syntax, and no external scripts.`,
);
