// A silent, procedural WebGL sculpture. The image remains the fallback.
const vertexSource = `
  precision highp float;
  attribute vec3 a_position;
  attribute vec3 a_normal;
  attribute float a_u;
  attribute float a_layer;
  uniform float u_time;
  uniform float u_aspect;
  uniform vec2 u_tilt;
  uniform vec4 u_pulses[4];
  varying vec3 v_normal;
  varying vec3 v_position;
  varying float v_layer;

  float displacement(float u) {
    float vibration = 0.0;
    for (int i = 0; i < 4; i++) {
      float age = max(u_time - u_pulses[i].y, 0.0);
      float pluck = u_pulses[i].x * 3.141593;
      float point = u * 3.141593;
      // Fixed-end normal modes: a fundamental and two quieter harmonics.
      float modes = sin(point) * sin(pluck) * sin(age * 36.0)
        + 0.30 * sin(point * 2.0) * sin(pluck * 2.0) * sin(age * 72.0)
        + 0.12 * sin(point * 3.0) * sin(pluck * 3.0) * sin(age * 108.0);
      vibration += u_pulses[i].z * modes * exp(-age * 4.5);
    }
    return vibration / (1.0 + abs(vibration) * 2.0);
  }

  mat3 rotation() {
    float a = 0.68 + u_tilt.y;
    float b = -0.22 + u_tilt.x;
    float c = 0.10;
    mat3 x = mat3(1,0,0, 0,cos(a),sin(a), 0,-sin(a),cos(a));
    mat3 y = mat3(cos(b),0,-sin(b), 0,1,0, sin(b),0,cos(b));
    mat3 z = mat3(cos(c),sin(c),0, -sin(c),cos(c),0, 0,0,1);
    return z * y * x;
  }

  void main() {
    vec3 p = a_position + vec3(0.0, displacement(a_u), 0.0);
    mat3 turn = rotation();
    v_normal = normalize(turn * a_normal);
    v_position = turn * p;
    v_layer = a_layer;
    float depth = 7.5 - v_position.z;
    float focal = min(3.5, u_aspect * 2.18);
    gl_Position = vec4(v_position.x * focal / u_aspect,
      v_position.y * focal, depth * 0.5 - 1.0, depth);
  }
`;

const fragmentSource = `
  precision mediump float;
  varying vec3 v_normal;
  varying vec3 v_position;
  varying float v_layer;
  void main() {
    vec3 n = normalize(v_normal);
    if (!gl_FrontFacing) n = -n;
    vec3 light = normalize(vec3(-0.5, 0.9, 1.3));
    vec3 eye = normalize(vec3(0.0, 0.0, 7.5) - v_position);
    float diffuse = max(dot(n, light), 0.0);
    float sheen = pow(max(dot(n, normalize(light + eye)), 0.0), 42.0);
    float rim = pow(1.0 - abs(dot(n, eye)), 3.0);
    float layerShade = 0.92 + 0.08 * v_layer;
    vec3 cobalt = vec3(0.035, 0.16, 0.88);
    vec3 color = cobalt * (0.43 + diffuse * 0.76) * layerShade;
    color += vec3(0.35, 0.48, 0.95) * sheen * 0.5;
    color += vec3(0.08, 0.14, 0.3) * rim;
    gl_FragColor = vec4(color, 1.0);
  }
`;

function makeProgram(gl) {
  const shaders = [];
  const program = gl.createProgram();
  try {
    for (const [type, source] of [
      [gl.VERTEX_SHADER, vertexSource],
      [gl.FRAGMENT_SHADER, fragmentSource],
    ]) {
      const shader = gl.createShader(type);
      shaders.push(shader);
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        throw new Error("Ribbon shader unavailable");
      }
      gl.attachShader(program, shader);
    }
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error("Ribbon renderer unavailable");
    }
    return program;
  } catch (error) {
    gl.deleteProgram(program);
    throw error;
  } finally {
    shaders.forEach((shader) => gl.deleteShader(shader));
  }
}

function makeMesh(gl) {
  const length = 220;
  const sides = 12;
  const layers = 18;
  const vertices = [];
  const indices = [];

  function centerline(u) {
    const envelope = Math.max(Math.sin(u * Math.PI), 0) ** 1.6;
    const sine = Math.sin(u * 26.4 - 3.7);
    const roundedWave = Math.sign(sine) * Math.abs(sine) ** 0.75;
    return [(u - 0.5) * 6.0,
      roundedWave * envelope * (0.28 + 1.4 * u) + 2.0 * (u - 0.5),
      Math.sin(u * Math.PI * 2) * 0.08];
  }

  function subtract(a, b) { return a.map((value, i) => value - b[i]); }
  function normalize(v) {
    const length = Math.hypot(...v) || 1;
    return v.map((value) => value / length);
  }
  const rings = Array.from({ length: length + 1 }, (_, x) => {
    const u = x / length;
    const taper = Math.max(Math.sin(u * Math.PI), 0) ** 0.65;
    const tangent = normalize(subtract(
      centerline(Math.min(u + 0.0005, 1)), centerline(Math.max(u - 0.0005, 0)),
    ));
    return { u, center: centerline(u), up: normalize([-tangent[1], tangent[0], 0]),
      width: 0.85 * taper + 0.004, thickness: 0.012 * taper + 0.001 };
  });

  // Bake the layered silhouette and its normals once, not on every GPU frame.
  for (let layer = 0; layer < layers; layer++) {
    const offset = vertices.length / 8;
    const depth = layer / (layers - 1) * 2 - 1;
    for (let x = 0; x <= length; x++) {
      const { u, center, up, width, thickness } = rings[x];
      for (let y = 0; y <= sides; y++) {
        const angle = y / sides * Math.PI * 2;
        const sine = Math.sin(angle);
        const cosine = Math.cos(angle);
        const position = [center[0] + up[0] * sine * thickness,
          center[1] + up[1] * sine * thickness,
          center[2] + depth * width + cosine * width * 0.048];
        const normal = normalize([up[0] * sine / thickness,
          up[1] * sine / thickness, cosine / (width * 0.048)]);
        vertices.push(...position, ...normal, u, depth);
        if (x < length && y < sides) {
          const a = offset + x * (sides + 1) + y;
          const b = a + sides + 1;
          indices.push(a, b, a + 1, a + 1, b, b + 1);
        }
      }
    }
  }
  const vertexBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vertices), gl.STATIC_DRAW);
  const indexBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(indices), gl.STATIC_DRAW);
  return indices.length;
}

export function initSoundRibbon() {
  const scene = document.querySelector(".hero-art");
  const canvas = scene.querySelector("canvas");
  const pause = scene.querySelector("[data-pause-ribbon]");
  const fallback = scene.querySelector(".sound-sculpture");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const mobile = matchMedia("(max-width: 780px)");
  // Keep the original art on phones, without creating a graphics context.
  if (reducedMotion.matches || mobile.matches) {
    function startWhenEligible() {
      if (reducedMotion.matches || mobile.matches) return;
      reducedMotion.removeEventListener("change", startWhenEligible);
      mobile.removeEventListener("change", startWhenEligible);
      initSoundRibbon();
    }
    reducedMotion.addEventListener("change", startWhenEligible);
    mobile.addEventListener("change", startWhenEligible);
    return;
  }
  let gl;
  let program;
  try {
    gl = canvas.getContext("webgl", {
      alpha: true, antialias: true, powerPreference: "low-power",
    });
    if (!gl) return;
    program = makeProgram(gl);
  } catch {
    return;
  }
  gl.useProgram(program);
  const indexCount = makeMesh(gl);
  for (const [name, size, offset] of [
    ["position", 3, 0], ["normal", 3, 3], ["u", 1, 6], ["layer", 1, 7],
  ]) {
    const attribute = gl.getAttribLocation(program, `a_${name}`);
    gl.enableVertexAttribArray(attribute);
    gl.vertexAttribPointer(attribute, size, gl.FLOAT, false, 32, offset * 4);
  }
  gl.enable(gl.DEPTH_TEST);
  gl.clearColor(0, 0, 0, 0);
  const uniforms = Object.fromEntries(
    ["time", "aspect", "tilt", "pulses[0]"].map((name) => [name,
      gl.getUniformLocation(program, `u_${name}`)]),
  );

  const pulses = new Float32Array(16);
  const tilt = { x: 0, y: 0, vx: 0, vy: 0, targetX: 0, targetY: 0 };
  let pulseIndex = 0;
  let elapsed = 0;
  let previous = 0;
  let frame = 0;
  let visible = true;
  let paused = false;
  let lost = false;
  let lastPluck = -10;

  function render() {
    const ratio = Math.min(devicePixelRatio || 1, 1.75);
    const width = Math.max(1, Math.round(canvas.clientWidth * ratio));
    const height = Math.max(1, Math.round(canvas.clientHeight * ratio));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
      gl.viewport(0, 0, width, height);
    }
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.uniform1f(uniforms.time, elapsed);
    gl.uniform1f(uniforms.aspect, width / height);
    gl.uniform2f(uniforms.tilt, tilt.x, tilt.y);
    gl.uniform4fv(uniforms["pulses[0]"], pulses);
    gl.drawElements(gl.TRIANGLES, indexCount, gl.UNSIGNED_SHORT, 0);
  }

  function animate(now) {
    frame = 0;
    const dt = previous ? Math.min((now - previous) / 1000, 0.032) : 0;
    previous = now;
    elapsed += dt;
    // Damped springs: the camera follows, then settles without a snap.
    for (const axis of ["x", "y"]) {
      const target = axis === "x" ? tilt.targetX : tilt.targetY;
      const velocity = `v${axis}`;
      tilt[velocity] += ((target - tilt[axis]) * 38 - tilt[velocity] * 12) * dt;
      tilt[axis] += tilt[velocity] * dt;
    }
    render();
    const settling = Math.abs(tilt.x - tilt.targetX) + Math.abs(tilt.y - tilt.targetY)
      + Math.abs(tilt.vx) + Math.abs(tilt.vy) > 0.0001;
    if (settling || elapsed - lastPluck < 1.8) {
      frame = requestAnimationFrame(animate);
    } else previous = 0;
  }

  function updatePlayback() {
    cancelAnimationFrame(frame);
    frame = 0;
    previous = 0;
    const still = reducedMotion.matches || mobile.matches || lost;
    scene.classList.toggle("ribbon-ready", !still);
    canvas.hidden = still;
    fallback.setAttribute("aria-hidden", String(!still));
    if (!still && visible && !document.hidden && !paused) {
      frame = requestAnimationFrame(animate);
    }
  }

  function wake() {
    if (!frame && !paused && !reducedMotion.matches && !mobile.matches
        && !lost && visible && !document.hidden) {
      frame = requestAnimationFrame(animate);
    }
  }

  function pluck(position) {
    if (paused || reducedMotion.matches || mobile.matches || lost) return;
    const strength = 0.12;
    pulses.set([position, elapsed, strength, 0], pulseIndex * 4);
    pulseIndex = (pulseIndex + 1) % 4;
    lastPluck = elapsed;
    wake();
  }

  canvas.addEventListener("pointermove", (event) => {
    if (event.pointerType !== "mouse" || paused || mobile.matches) return;
    const bounds = canvas.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width;
    const y = (event.clientY - bounds.top) / bounds.height;
    tilt.targetX = (x - 0.5) * 0.18;
    tilt.targetY = (y - 0.5) * 0.14;
    wake();
  });
  canvas.addEventListener("pointerleave", () => {
    tilt.targetX = 0;
    tilt.targetY = 0;
    wake();
  });
  canvas.addEventListener("click", (event) => {
    const bounds = canvas.getBoundingClientRect();
    pluck((event.clientX - bounds.left) / bounds.width);
  });
  canvas.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      if (!event.repeat) pluck(0.5);
    }
  });
  pause.addEventListener("click", () => {
    paused = !paused;
    pause.setAttribute("aria-label", paused ? "Resume ribbon animation" : "Pause ribbon animation");
    pause.dataset.paused = String(paused);
    canvas.setAttribute("aria-disabled", String(paused));
    updatePlayback();
  });
  canvas.addEventListener("webglcontextlost", (event) => {
    event.preventDefault();
    lost = true;
    updatePlayback();
  });
  document.addEventListener("visibilitychange", updatePlayback);
  reducedMotion.addEventListener("change", updatePlayback);
  mobile.addEventListener("change", updatePlayback);
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    updatePlayback();
  }).observe(scene);
  new ResizeObserver(() => {
    if (!lost && !reducedMotion.matches && !mobile.matches) render();
  }).observe(scene);
  canvas.hidden = false;
  render();
  updatePlayback();
}
