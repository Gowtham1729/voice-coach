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

function setup({ reduced = false, mobile = false, gpu = true, compile = true, hidden = false } = {}) {
  const frames = new Map();
  const values = {};
  let nextFrame = 0;
  let draws = 0;
  let contexts = 0;
  let intersect;
  let resize;
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
  const fallback = target();
  const motionToggle = target({ hidden: true, textContent: "Pause motion" });
  const classes = new Set();
  const scene = {
    clientWidth: hidden ? 0 : 600,
    clientHeight: hidden ? 0 : 450,
    classList: { toggle: (name, on) => on ? classes.add(name) : classes.delete(name) },
    querySelector: (selector) => ({
      canvas, ".sound-sculpture": fallback, ".ribbon-toggle": motionToggle,
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
    ResizeObserver: class {
      constructor(callback) { resize = callback; }
      observe() {}
    },
  });
  return {
    canvas, fallback, motionToggle, scene, media, phone, document, frames, values, classes,
    draws: () => draws, contexts: () => contexts,
    intersect: (visible) => intersect([{ isIntersecting: visible }]),
    resize: () => resize(),
    tick(time) {
      for (const [id, callback] of [...frames]) {
        frames.delete(id);
        callback(time);
      }
    },
  };
}

test("a hidden ribbon scene allocates no graphics context or animation loop", () => {
  const page = setup({ hidden: true });
  assert.equal(page.contexts(), 0);
  assert.equal(page.frames.size, 0);
  assert.equal(page.draws(), 0);
});

test("resizing does not draw while the ribbon is offscreen or the page is hidden", () => {
  const page = setup();
  const initialDraws = page.draws();
  page.intersect(false);
  page.resize();
  assert.equal(page.draws(), initialDraws);
  page.intersect(true);
  page.document.hidden = true;
  page.document.emit("visibilitychange");
  page.resize();
  assert.equal(page.draws(), initialDraws);
  assert.equal(page.frames.size, 0);
});

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
  const page = setup({ mobile: true, hidden: true });
  assert.equal(page.contexts(), 0);
  assert.equal(page.frames.size, 0);
  assert.equal(page.canvas.hidden, true);
  page.scene.clientWidth = 600;
  page.scene.clientHeight = 450;
  page.phone.matches = false;
  page.phone.emit("change");
  assert.equal(page.contexts(), 1);
  assert.equal(page.canvas.hidden, false);
  page.phone.matches = true;
  page.phone.emit("change");
  assert.equal(page.frames.size, 0);
  assert.equal(page.canvas.hidden, true);
  assert.equal(page.classes.has("ribbon-ready"), false);
  page.canvas.emit("click", { clientX: 200 });
  assert.equal(page.frames.size, 0);
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

test("left and right clicks excite different projected locations while the sculpture floats", () => {
  const page = setup();
  page.tick(100);
  page.canvas.emit("click", { clientX: 120, clientY: 340 });
  page.canvas.emit("click", { clientX: 470, clientY: 170 });
  page.canvas.emit("keydown", { key: "Enter", repeat: false, preventDefault() {} });
  page.canvas.emit("pointermove", { pointerType: "touch" });
  page.tick(116);
  const pulses = page.values["u_pulses[0]"];
  assert.ok(pulses[0] < 0.45, "left click starts on the left of the sculpture");
  assert.ok(pulses[4] > 0.55, "right click starts on the right of the sculpture");
  assert.equal(pulses[8], 0.5, "keyboard activation starts at the center");
  assert.ok(pulses.every(Number.isFinite));
  assert.deepEqual(page.values.u_tilt, [0, 0]);
  for (let time = 132; time < 2300; time += 16) page.tick(time);
  assert.equal(page.frames.size, 1, "gentle floating continues while visible");
  page.canvas.emit("pointermove", { pointerType: "mouse", clientX: 450, clientY: 200 });
  assert.equal(page.frames.size, 1, "pointer movement does not create a second animation loop");
  page.tick(2320);
  page.canvas.emit("webglcontextlost", { preventDefault() {} });
  assert.equal(page.canvas.hidden, true);
  assert.equal(page.frames.size, 0);
});

test("the motion control freezes the ribbon and resumes one loop", () => {
  const page = setup();
  assert.equal(page.motionToggle.hidden, false);
  page.motionToggle.emit("click");
  assert.equal(page.motionToggle.textContent, "Resume motion");
  assert.equal(page.frames.size, 0);
  assert.equal(page.canvas.hidden, false, "pause keeps the current sculpture visible");
  page.canvas.emit("keydown", { key: "Enter", preventDefault() {} });
  page.canvas.emit("pointermove", { pointerType: "mouse", clientX: 450, clientY: 200 });
  assert.equal(page.frames.size, 0, "input does not override the pause");
  page.motionToggle.emit("click");
  assert.equal(page.motionToggle.textContent, "Pause motion");
  assert.equal(page.frames.size, 1);
});
