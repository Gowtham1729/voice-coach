import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../website/", import.meta.url));
const args = process.argv.slice(2);
const port = args.includes("--port")
  ? Number(args[args.indexOf("--port") + 1])
  : 4173;
const host = args.includes("--host")
  ? args[args.indexOf("--host") + 1]
  : "127.0.0.1";
const types = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ttf": "font/ttf",
  ".mp4": "video/mp4",
  ".vtt": "text/vtt; charset=utf-8",
};

createServer(async (request, response) => {
  try {
    const url = new URL(request.url, "http://localhost");
    const requestedPath = decodeURIComponent(url.pathname);
    const path = resolve(
      root,
      `.${requestedPath === "/" ? "/index.html" : requestedPath}`,
    );
    if (!path.startsWith(root.endsWith(sep) ? root : root + sep)) {
      response.writeHead(403).end();
      return;
    }
    const info = await stat(path);
    if (!info.isFile()) {
      response.writeHead(404).end();
      return;
    }
    const headers = {
      "Content-Type": types[extname(path)] || "application/octet-stream",
      "Accept-Ranges": "bytes",
      "Cache-Control": "no-cache",
    };
    let start = 0;
    let end = info.size - 1;
    let status = 200;
    if (request.headers.range) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(request.headers.range);
      if (!match || (!match[1] && !match[2])) {
        response
          .writeHead(416, { "Content-Range": `bytes */${info.size}` })
          .end();
        return;
      }
      if (!match[1]) start = Math.max(0, info.size - Number(match[2]));
      else {
        start = Number(match[1]);
        if (match[2]) end = Math.min(end, Number(match[2]));
      }
      if (start > end || start >= info.size) {
        response
          .writeHead(416, { "Content-Range": `bytes */${info.size}` })
          .end();
        return;
      }
      status = 206;
      headers["Content-Range"] = `bytes ${start}-${end}/${info.size}`;
    }
    headers["Content-Length"] = end - start + 1;
    response.writeHead(status, headers);
    if (request.method === "HEAD") response.end();
    else createReadStream(path, { start, end }).pipe(response);
  } catch {
    response.writeHead(404).end("Not found");
  }
}).listen(port, host, () =>
  console.log(`Voice Coach website: http://${host}:${port}`),
);
