import "./check-website.mjs";
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, extname, join, relative, resolve, sep } from "node:path";
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

// Hash a module only after the modules it imports are already renamed.
// Hashing every script in one pass leaves `sound-ribbon.js` renamed while
// `app.js` still imports the old name, so the built page never runs.
function fingerprintText(ext) {
  let pending = walk(output).filter((file) => extname(file) === ext);
  for (const file of pending) rewrite(file, replacements);
  let guard = pending.length + 1;
  while (pending.length) {
    if (guard-- < 0) {
      throw new Error(`Could not fingerprint ${ext} files: ${pending.map(relPosix).join(", ")}`);
    }
    const ready = pending.filter((file) => {
      const text = readFileSync(file, "utf8");
      return pending.every((other) => other === file || !text.includes(relPosix(other)));
    });
    const batch = ready.length ? ready : pending.slice(0, 1);
    for (const file of batch) {
      const [before, after] = hashFile(file);
      replacements.set(before, after);
    }
    pending = pending.filter((file) => !batch.includes(file));
    for (const file of pending) rewrite(file, replacements);
  }
}

fingerprintText(".css");
fingerprintText(".js");

for (const file of walk(output).filter((item) => extname(item) === ".html")) {
  rewrite(file, replacements);
}

const localUrl = /^(?:[a-z]+:|#|\/\/)/i;
const refPatterns = [
  /\b(?:src|href)=["']([^"']+)["']/g,
  /\bsrcset=["']([^"']+)["']/g,
  /\bfrom\s+["']([^"']+)["']/g,
  /\burl\(\s*["']([^"']+)["']/g,
  /["'](assets\/[^"'?#\s]+)["']/g,
];
for (const file of walk(output).filter((item) => textExtensions.has(extname(item)))) {
  const text = readFileSync(file, "utf8");
  const urls = [];
  for (const pattern of refPatterns) {
    for (const match of text.matchAll(pattern)) {
      if (pattern.source.includes("srcset")) {
        for (const part of match[1].split(",")) {
          const url = part.trim().split(/\s+/)[0];
          if (url) urls.push(url);
        }
      } else urls.push(match[1]);
    }
  }
  for (const url of urls) {
    if (localUrl.test(url)) continue;
    const path = url.split(/[?#]/, 1)[0];
    if (!path || path.endsWith("/")) continue;
    const target = resolve(dirname(file), path);
    const root = output.endsWith(sep) ? output : output + sep;
    if (!target.startsWith(root)) {
      throw new Error(`${relPosix(file)} points outside dist: ${url}`);
    }
    if (!existsSync(target)) {
      throw new Error(`${relPosix(file)} references missing ${url}`);
    }
  }
}

// Crawl and agent hints stay at the site root. Copy them after fingerprinting
// so they are published even if a later filter skips non-asset files.
for (const name of ["robots.txt", "sitemap.xml", "llms.txt"]) {
  const from = join(source, name);
  const to = join(output, name);
  if (!existsSync(from)) throw new Error(`website/${name} is required`);
  cpSync(from, to);
  if (!readFileSync(from).equals(readFileSync(to))) {
    throw new Error(`dist/${name} does not match website/${name}`);
  }
}

console.log(`Static website built in dist/ with ${replacements.size} fingerprinted assets.`);
