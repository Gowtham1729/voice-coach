// A silent, procedural WebGL sculpture. The image remains the fallback.
const vertexSource = `
  precision highp float;
  attribute vec2 a_surface;
  uniform float u_time;
  uniform float u_aspect;
  uniform vec2 u_tilt;
  uniform vec4 u_pulses[4];
  varying vec3 v_normal;
  varying vec3 v_position;
  varying float v_rib;

  vec3 surface(float u, float v) {
    float envelope = pow(max(sin(u * 3.141593), 0.0), 0.6);
    float phase = u * 13.8 - 0.9;
    float breath = sin(u_time * 0.65 + u * 5.0) * 0.055;
    float wave = 0.0;
    for (int i = 0; i < 4; i++) {
      float age = max(u_time - u_pulses[i].y, 0.0);
      float distance = abs(u - u_pulses[i].x) * 6.0;
      float front = distance - age * 2.3;
      wave += u_pulses[i].z * sin(front * 7.0)
        * exp(-front * front * 2.4 - age * 1.6);
    }
    wave /= 1.0 + abs(wave) * 1.3;
    float twist = phase + breath + wave * 0.4;
    float width = 0.52 * (0.15 + envelope * 0.85);
    float rib = cos(u * 1005.31);
    float thickness = 0.035 + 0.008 * rib;
    vec3 center = vec3((u - 0.5) * 6.0,
      sin(phase) * 0.55 * envelope + (breath + wave) * envelope,
      cos(phase) * 0.36 * envelope);
    vec3 across = vec3(0.0, cos(twist), sin(twist));
    vec3 edge = vec3(0.0, -sin(twist), cos(twist));
    return center + across * cos(v) * width + edge * sin(v) * thickness;
  }

  mat3 rotation() {
    float a = 0.48 + u_tilt.y;
    float b = -0.16 + u_tilt.x;
    float c = 0.23;
    mat3 x = mat3(1,0,0, 0,cos(a),sin(a), 0,-sin(a),cos(a));
    mat3 y = mat3(cos(b),0,-sin(b), 0,1,0, sin(b),0,cos(b));
    mat3 z = mat3(cos(c),sin(c),0, -sin(c),cos(c),0, 0,0,1);
    return z * y * x;
  }

  void main() {
    float u = a_surface.x;
    float v = a_surface.y;
    vec3 p = surface(u, v);
    vec3 tangent = surface(min(u + 0.0003, 1.0), v)
      - surface(max(u - 0.0003, 0.0), v);
    vec3 across = surface(u, v + 0.002) - surface(u, v - 0.002);
    mat3 turn = rotation();
    v_normal = normalize(turn * cross(tangent, across));
    v_position = turn * p;
    v_rib = u * 160.0;
    float depth = 7.5 - v_position.z;
    float focal = min(3.5, u_aspect * 2.15);
    gl_Position = vec4(v_position.x * focal / u_aspect,
      v_position.y * focal, depth * 0.5 - 1.0, depth);
  }
`;

const fragmentSource = `
  precision mediump float;
  varying vec3 v_normal;
  varying vec3 v_position;
  varying float v_rib;
  void main() {
    vec3 n = normalize(v_normal);
    if (!gl_FrontFacing) n = -n;
    vec3 light = normalize(vec3(-0.5, 0.9, 1.3));
    vec3 eye = normalize(vec3(0.0, 0.0, 7.5) - v_position);
    float diffuse = max(dot(n, light), 0.0);
    float sheen = pow(max(dot(n, normalize(light + eye)), 0.0), 42.0);
    float rim = pow(1.0 - abs(dot(n, eye)), 3.0);
    float rib = 0.88 + 0.12 * cos(v_rib * 6.283185);
    vec3 cobalt = vec3(0.075, 0.18, 0.86);
    vec3 color = cobalt * (0.38 + diffuse * 0.78) * rib;
    color += vec3(0.30, 0.43, 0.8) * sheen * 0.45;
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
  const length = 640;
  const sides = 20;
  const vertices = [];
  const indices = [];
  for (let x = 0; x <= length; x++) {
    for (let y = 0; y <= sides; y++) {
      vertices.push(x / length, (y / sides) * Math.PI * 2);
      if (x < length && y < sides) {
        const a = x * (sides + 1) + y;
        const b = a + sides + 1;
        indices.push(a, b, a + 1, a + 1, b, b + 1);
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
  // No GPU work at all for visitors who request reduced motion.
  if (reducedMotion.matches) {
    reducedMotion.addEventListener("change", initSoundRibbon, { once: true });
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
  const attribute = gl.getAttribLocation(program, "a_surface");
  gl.enableVertexAttribArray(attribute);
  gl.vertexAttribPointer(attribute, 2, gl.FLOAT, false, 0, 0);
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
  let lastPointerPulse = -1;
  let lastPointerX = 0.5;

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
    frame = requestAnimationFrame(animate);
  }

  function updatePlayback() {
    cancelAnimationFrame(frame);
    frame = 0;
    previous = 0;
    const still = reducedMotion.matches || lost;
    scene.classList.toggle("ribbon-ready", !still);
    canvas.hidden = still;
    fallback.setAttribute("aria-hidden", String(!still));
    if (!still && visible && !document.hidden && !paused) {
      frame = requestAnimationFrame(animate);
    }
  }

  function ripple(position, strength) {
    if (paused || reducedMotion.matches || lost) return;
    pulses.set([position, elapsed, strength, 0], pulseIndex * 4);
    pulseIndex = (pulseIndex + 1) % 4;
  }

  canvas.addEventListener("pointermove", (event) => {
    if (event.pointerType !== "mouse" || paused) return;
    const bounds = canvas.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width;
    const y = (event.clientY - bounds.top) / bounds.height;
    tilt.targetX = (x - 0.5) * 0.28;
    tilt.targetY = (y - 0.5) * 0.22;
    if (elapsed - lastPointerPulse > 0.15 && Math.abs(x - lastPointerX) > 0.025) {
      ripple(x, Math.min(Math.abs(x - lastPointerX) * 2, 0.16));
      lastPointerPulse = elapsed;
      lastPointerX = x;
    }
  });
  canvas.addEventListener("pointerleave", () => {
    tilt.targetX = 0;
    tilt.targetY = 0;
  });
  canvas.addEventListener("click", (event) => {
    const bounds = canvas.getBoundingClientRect();
    ripple((event.clientX - bounds.left) / bounds.width, 0.38);
  });
  canvas.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      if (!event.repeat) ripple(0.5, 0.38);
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
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    updatePlayback();
  }).observe(scene);
  new ResizeObserver(() => {
    if (!lost && !reducedMotion.matches) render();
  }).observe(scene);
  canvas.hidden = false;
  render();
  updatePlayback();
}
