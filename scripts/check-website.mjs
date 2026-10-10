import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const root = fileURLToPath(new URL("../website/", import.meta.url));
const publicOrigin = "https://ichido.app";
assert.equal(
  existsSync(fileURLToPath(new URL("../.openai/hosting.json", import.meta.url))),
  false,
  "ChatGPT Sites hosting config must stay deleted",
);
const firebase = JSON.parse(
  readFileSync(new URL("../firebase.json", import.meta.url), "utf8"),
);
assert.deepEqual(
  Object.keys(firebase),
  ["hosting"],
  "Firebase config must be Hosting only",
);
assert.equal(firebase.hosting.public, "dist", "Firebase Hosting publishes dist/");
assert.equal(
  firebase.hosting.site,
  "ichido-511210",
  "Firebase Hosting site is ichido-511210",
);
const firebaseRc = JSON.parse(
  readFileSync(new URL("../.firebaserc", import.meta.url), "utf8"),
);
assert.equal(
  firebaseRc.projects.default,
  "ichido-511210",
  "Firebase project is ichido-511210",
);
const html = readFileSync(resolve(root, "index.html"), "utf8");
assert.ok(
  html.includes('href="https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip"'),
  "Website download must follow GitHub's latest release",
);
assert.ok(
  html.includes(`href="${publicOrigin}/"`),
  "Canonical URL is https://ichido.app/",
);
assert.ok(
  html.includes(`content="${publicOrigin}/"`),
  "Open Graph URL is https://ichido.app/",
);
assert.ok(
  html.includes(`content="${publicOrigin}/assets/ichido-share.jpg"`),
  "Share image URL is on https://ichido.app",
);
assert.equal(
  /noindex|nofollow/i.test(html),
  false,
  "Promo page must stay indexable",
);
assert.match(
  html,
  /<title>Ichido \| Private speaking practice for Mac<\/title>/,
  "Title tells a search result this is private speaking practice for Mac",
);
assert.ok(
  html.includes(
    'content="Ichido is a private Mac app for speaking practice. Practice a language, rehearse a talk, and hear yourself back."',
  ),
  "Meta description uses the page language for language practice and rehearsing a talk",
);
const robots = readFileSync(resolve(root, "robots.txt"), "utf8");
assert.match(robots, /^User-agent:\s*\*\s*$/m, "robots.txt allows every crawler");
assert.match(robots, /^Allow:\s*\/\s*$/m, "robots.txt allows the site");
assert.equal(/^\s*Disallow:/m.test(robots), false, "robots.txt must not disallow paths");
assert.match(
  robots,
  new RegExp(`^Sitemap:\\s*${publicOrigin}/sitemap\\.xml\\s*$`, "m"),
  "robots.txt points at the sitemap",
);
const sitemap = readFileSync(resolve(root, "sitemap.xml"), "utf8");
const locations = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);
assert.deepEqual(locations, [`${publicOrigin}/`], "Sitemap lists only https://ichido.app/");
const jsonLdMatch = html.match(
  /<script type="application\/ld\+json">([\s\S]*?)<\/script>/,
);
assert.ok(jsonLdMatch, "Software JSON-LD is present");
const software = JSON.parse(jsonLdMatch[1]);
assert.equal(software["@context"], "https://schema.org");
assert.equal(software["@type"], "SoftwareApplication");
assert.equal(software.name, "Ichido");
assert.equal(software.url, `${publicOrigin}/`);
assert.match(software.operatingSystem, /^macOS$/);
assert.equal(
  software.description,
  "Ichido is a private Mac app for speaking practice. Practice a language, rehearse a talk, and hear yourself back. Free early access.",
);
assert.equal(software.isAccessibleForFree, true);
assert.equal(software.aggregateRating, undefined, "Do not invent ratings");
assert.equal(software.review, undefined, "Do not invent reviews");
assert.equal(software.offers, undefined, "Do not invent offers");
assert.equal(
  /chatgpt\.site|openai\.com\/hosting|ichido-511210\.web\.app|firebaseapp\.com|www\.ichido\.app/i.test(html),
  false,
  "Promo page uses the apex public URL, not a former host",
);
assert.ok(
  !/releases\/(?:tag|download)\/v\d/.test(html),
  "Website links must not pin an old release",
);
const css = readFileSync(resolve(root, "styles.css"), "utf8");
const modules = readdirSync(root).filter((file) => file.endsWith(".js"));
const js = modules.map((file) => readFileSync(resolve(root, file), "utf8")).join("\n");
const appModule = readFileSync(resolve(root, "app.js"), "utf8");
for (const [asset, source] of [["styles.css", html], ["app.js", html], ["./sound-ribbon.js", appModule]]) {
  const version = createHash("sha256")
    .update(readFileSync(resolve(root, asset)))
    .digest("hex")
    .slice(0, 12);
  assert.ok(source.includes(`"${asset}?v=${version}"`), `Refresh the content version for ${asset}`);
}
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
assert.equal(new Set(ids).size, ids.length, "HTML IDs must be unique");
const srcsetUrls = [...html.matchAll(/\b(?:srcset|imagesrcset)="([^"]+)"/g)]
  .flatMap((match) => match[1].split(","))
  .map((part) => part.trim().split(/\s+/)[0])
  .filter((url) => url && !url.startsWith("data:"));
const urls = new Set([
  ...[...html.matchAll(/\b(?:src|href|poster)="([^"]+)"/g)].map(
    (match) => match[1],
  ),
  ...srcsetUrls,
  ...[...css.matchAll(/url\(['"]?([^'"\)]+)['"]?\)/g)].map((match) => match[1]),
  ...[...js.matchAll(/['"](assets\/[^'"\s]+)['"]/g)].map((match) => match[1]),
  ...[...js.matchAll(/\bfrom ["']\.\/([^"']+)["']/g)].map((match) => match[1]),
]);
for (const url of urls) {
  if (url === "#" || url.startsWith("https://")) continue;
  if (url.startsWith("#"))
    assert.ok(ids.includes(url.slice(1)), `Missing anchor: ${url}`);
  else {
    const localPath = url.split(/[?#]/, 1)[0];
    assert.ok(existsSync(resolve(root, localPath)), `Missing local asset: ${url}`);
  }
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
  !/getUserMedia|MediaRecorder|sendBeacon|AudioContext|gtag\(|googletagmanager|google-analytics/.test(js + html),
  "Marketing page must not capture audio or load analytics",
);
for (const module of modules) {
  execFileSync(process.execPath, ["--check", resolve(root, module)], {
    stdio: "inherit",
  });
}
console.log(
  `Website verified: ${urls.size} references, ${ids.length} unique IDs, valid ARIA targets, JavaScript syntax, and no external scripts.`,
);
