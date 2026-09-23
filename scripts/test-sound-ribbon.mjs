import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { test } from "node:test";

const source = readFileSync(new URL("../website/sound-ribbon.js", import.meta.url), "utf8")
  .replace("export function initSoundRibbon", "function initSoundRibbon");

function target(properties = {}) {
  const listeners = new Map();
  return Object.assign({
    attributes: {},
    addEventListener(type, callback, options = {}) {
      const entries = listeners.get(type) || [];
      entries.push({ callback, once: options.once });
      listeners.set(type, entries);
    },
    removeEventListener(type, callback) {
      listeners.set(type, (listeners.get(type) || []).filter((e) => e.callback !== callback));
    },
    emit(type, event = {}) {
      for (const entry of [...(listeners.get(type) || [])]) {
        if (entry.once) listeners.set(type, listeners.get(type).filter((e) => e !== entry));
        entry.callback(event);
      }
    },
    setAttribute(name, value) { this.attributes[name] = value; },
  }, properties);
}

function setup({ reduced = false, mobile = false, gpu = true, compile = true } = {}) {
  const frames = new Map();
  const values = {};
  let nextFrame = 0;
  let draws = 0;
  let contexts = 0;
  let intersect;
  const gl = new Proxy({
    getShaderParameter: () => compile,
    getProgramParameter: () => true,
    getUniformLocation: (_, name) => name,
    uniform1f: (name, value) => { values[name] = value; },
    drawElements: () => { draws++; },
  }, { get: (object, name) => object[name] || (() => ({})) });
  const canvas = target({
    hidden: true, clientWidth: 600, clientHeight: 450,
    getContext: () => { contexts++; return gpu ? gl : null; },
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 600, height: 450 }),
  });
  const fallback = target();
  const classes = new Set();
  const scene = {
    classList: { toggle: (name, on) => on ? classes.add(name) : classes.delete(name) },
    querySelector: (selector) => ({
      canvas, ".sound-sculpture": fallback,
    })[selector],
  };
  const media = target({ matches: reduced });
  const phone = target({ matches: mobile });
  const document = target({ hidden: false, querySelector: () => scene });
  runInNewContext(`${source}\ninitSoundRibbon();`, {
    document,
    matchMedia: (query) => query.includes("max-width") ? phone : media,
    devicePixelRatio: 3,
    requestAnimationFrame: (callback) => {
      frames.set(++nextFrame, callback);
      return nextFrame;
    },
    cancelAnimationFrame: (id) => frames.delete(id),
    IntersectionObserver: class {
      constructor(callback) { intersect = callback; }
      observe() {}
    },
    ResizeObserver: class { observe() {} },
  });
  return {
    canvas, fallback, media, phone, document, frames, values, classes,
    draws: () => draws, contexts: () => contexts,
    intersect: (visible) => intersect([{ isIntersecting: visible }]),
    tick(time) {
      for (const [id, callback] of [...frames]) {
        frames.delete(id);
        callback(time);
      }
    },
  };
}

test("reduced motion starts with the still image and never opens a GPU context", () => {
  const page = setup({ reduced: true });
  assert.equal(page.contexts(), 0);
  assert.equal(page.frames.size, 0);
  assert.equal(page.canvas.hidden, true);
  page.media.matches = false;
  page.media.emit("change");
  assert.equal(page.contexts(), 1);
  assert.equal(page.frames.size, 1);
});

test("missing WebGL or shader failure leaves the original image available", () => {
  for (const options of [{ gpu: false }, { compile: false }]) {
    const page = setup(options);
    assert.equal(page.canvas.hidden, true);
    assert.equal(page.classes.has("ribbon-ready"), false);
    assert.equal(page.frames.size, 0);
  }
});

test("mobile never starts the effect, including after crossing the desktop breakpoint", () => {
  const page = setup({ mobile: true });
  assert.equal(page.contexts(), 0);
  assert.equal(page.frames.size, 0);
  assert.equal(page.canvas.hidden, true);
  page.phone.matches = false;
  page.phone.emit("change");
  assert.equal(page.contexts(), 1);
  assert.equal(page.canvas.hidden, false);
  page.phone.matches = true;
  page.phone.emit("change");
  assert.equal(page.frames.size, 0);
  assert.equal(page.canvas.hidden, true);
  assert.equal(page.classes.has("ribbon-ready"), false);
});

test("visibility and motion preference stop work without duplicate animation loops", () => {
  const page = setup();
  page.tick(100);
  assert.equal(page.canvas.width, 1050, "pixel ratio is capped at 1.75");
  page.intersect(false);
  assert.equal(page.frames.size, 0);
  page.intersect(true);
  assert.equal(page.frames.size, 1);
  page.document.hidden = true;
  page.document.emit("visibilitychange");
  assert.equal(page.frames.size, 0);
  page.document.hidden = false;
  page.document.emit("visibilitychange");
  page.media.matches = true;
  page.media.emit("change");
  assert.equal(page.frames.size, 0);
  assert.equal(page.canvas.hidden, true);
  assert.equal(page.fallback.attributes["aria-hidden"], "false");
  page.media.matches = false;
  page.media.emit("change");
  assert.equal(page.frames.size, 1);
});

test("the ribbon floats continuously and falls back when its context is lost", () => {
  const page = setup();
  page.tick(100);
  page.tick(116);
  const firstTime = page.values.u_time;
  for (let time = 132; time < 2300; time += 16) page.tick(time);
  assert.equal(page.frames.size, 1, "gentle floating continues while visible");
  assert.ok(page.values.u_time > firstTime, "animation time advances");
  assert.ok(page.draws() > 2, "the sculpture redraws");
  page.tick(2320);
  page.canvas.emit("webglcontextlost", { preventDefault() {} });
  assert.equal(page.canvas.hidden, true);
  assert.equal(page.frames.size, 0);
});
