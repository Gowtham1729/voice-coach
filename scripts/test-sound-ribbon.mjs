import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { test } from "node:test";

const source = readFileSync(new URL("../website/sound-ribbon.js", import.meta.url), "utf8")
  .replace("export function initSoundRibbon", "function initSoundRibbon");

function target(properties = {}) {
  const listeners = new Map();
  return Object.assign({
    dataset: {},
    attributes: {},
    addEventListener(type, callback, options = {}) {
      const entries = listeners.get(type) || [];
      entries.push({ callback, once: options.once });
      listeners.set(type, entries);
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

function setup({ reduced = false, gpu = true, compile = true } = {}) {
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
    uniform2f: (name, ...value) => { values[name] = value; },
    uniform4fv: (name, value) => { values[name] = [...value]; },
    drawElements: () => { draws++; },
  }, { get: (object, name) => object[name] || (() => ({})) });
  const canvas = target({
    hidden: true, clientWidth: 600, clientHeight: 450,
    getContext: () => { contexts++; return gpu ? gl : null; },
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 600, height: 450 }),
  });
  const pause = target();
  const fallback = target();
  const classes = new Set();
  const scene = {
    classList: { toggle: (name, on) => on ? classes.add(name) : classes.delete(name) },
    querySelector: (selector) => ({
      canvas, "[data-pause-ribbon]": pause, ".sound-sculpture": fallback,
    })[selector],
  };
  const media = target({ matches: reduced });
  const document = target({ hidden: false, querySelector: () => scene });
  runInNewContext(`${source}\ninitSoundRibbon();`, {
    document, matchMedia: () => media, devicePixelRatio: 3,
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
    canvas, pause, fallback, media, document, frames, values, classes,
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

test("pause, visibility, and motion preference stop work without duplicate animation loops", () => {
  const page = setup();
  page.tick(100);
  assert.equal(page.canvas.width, 1050, "pixel ratio is capped at 1.75");
  page.pause.emit("click");
  const pausedDraws = page.draws();
  page.tick(200);
  assert.equal(page.draws(), pausedDraws);
  assert.equal(page.frames.size, 0);
  assert.equal(page.pause.attributes["aria-label"], "Resume ribbon animation");
  page.pause.emit("click");
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

test("click and keyboard launch bounded waves; touch scrolling is not intercepted", () => {
  const page = setup();
  page.tick(100);
  page.canvas.emit("click", { clientX: 150 });
  page.canvas.emit("keydown", { key: "Enter", repeat: false, preventDefault() {} });
  page.canvas.emit("pointermove", { pointerType: "touch" });
  page.tick(116);
  const pulses = page.values["u_pulses[0]"];
  assert.equal(pulses[0], 0.25);
  assert.equal(pulses[4], 0.5);
  assert.ok(pulses.every(Number.isFinite));
  assert.deepEqual(page.values.u_tilt, [0, 0]);
  page.canvas.emit("webglcontextlost", { preventDefault() {} });
  assert.equal(page.canvas.hidden, true);
  assert.equal(page.frames.size, 0);
});
