// The Ink: one fixed WebGL1 canvas behind the whole site, seen at full strength
// through the NAIR window and dimmed behind every other section. Desktop cursors stir
// it. It pauses when the tab is hidden and holds a single frame under reduced motion.
(function () {
  const canvas = document.getElementById('gl');
  if (!canvas) return;
  const gl = canvas.getContext('webgl', { antialias: false, premultipliedAlpha: false });
  if (!gl) { document.documentElement.classList.add('no-gl'); return; }
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const FRAG = `
precision highp float;
uniform vec2 u_res;
uniform float u_time;
uniform vec2 u_mouse;
uniform vec2 u_mvel;
uniform float u_stir;
float hash3(vec3 p){ p = fract(p*0.3183099 + 0.1); p *= 17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
float noise(vec3 x){
  vec3 i = floor(x), f = fract(x); f = f*f*(3.0-2.0*f);
  return mix(mix(mix(hash3(i+vec3(0,0,0)),hash3(i+vec3(1,0,0)),f.x),
                 mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),
             mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),
                 mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float fbm(vec3 p){
  float a = 0.5, s = 0.0;
  for (int i = 0; i < 5; i++){ s += a*noise(p); p = p*2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; }
  return s;
}
void main(){
  vec2 p = (gl_FragCoord.xy - 0.5*u_res) / u_res.y * 1.5;
  vec2 m = (u_mouse - 0.5*u_res) / u_res.y * 1.5;
  vec2 d = p - m;
  float fall = exp(-dot(d, d) * 7.0) * u_stir;
  float ang = fall * 1.5;
  float cs = cos(ang), sn = sin(ang);
  p = m + mat2(cs, -sn, sn, cs) * d - u_mvel * fall;
  float t = u_time * 0.06;
  vec2 q = vec2(fbm(vec3(p, t)), fbm(vec3(p + vec2(5.2, 1.3), t)));
  vec2 r = vec2(fbm(vec3(p + 3.5*q + vec2(1.7, 9.2), t*1.4)), fbm(vec3(p + 3.5*q + vec2(8.3, 2.8), t*1.4)));
  float f = smoothstep(0.28, 0.72, fbm(vec3(p + 3.5*r, t*0.8)));
  float g = smoothstep(0.3, 0.7, r.y);
  vec3 col = mix(vec3(0.06, 0.015, 0.08), vec3(0.70, 0.08, 0.30), smoothstep(0.05, 0.55, f));
  col = mix(col, vec3(1.0, 0.42, 0.10), smoothstep(0.40, 0.85, f));
  col = mix(col, vec3(1.0, 0.86, 0.62), smoothstep(0.82, 1.0, f) * 0.75);
  col = mix(col, vec3(0.20, 0.85, 0.90), g * (1.0 - smoothstep(0.15, 0.55, f)) * 0.8);
  col *= 0.75 + 0.5*smoothstep(0.2, 0.9, length(q));
  col *= 1.0 + 0.12*fall;
  col += (hash3(vec3(gl_FragCoord.xy, floor(u_time*24.0))) - 0.5) * 0.035;
  gl_FragColor = vec4(col, 1.0);
}`;

  function compile(type, src) {
    const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }
  const prog = gl.createProgram();
  gl.attachShader(prog, compile(gl.VERTEX_SHADER, 'attribute vec2 a; void main(){ gl_Position = vec4(a, 0.0, 1.0); }'));
  gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, FRAG));
  gl.linkProgram(prog);
  gl.useProgram(prog);
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const aLoc = gl.getAttribLocation(prog, 'a');
  gl.enableVertexAttribArray(aLoc);
  gl.vertexAttribPointer(aLoc, 2, gl.FLOAT, false, 0, 0);
  const U = n => gl.getUniformLocation(prog, n);
  const uRes = U('u_res'), uTime = U('u_time'), uMouse = U('u_mouse'), uVel = U('u_mvel'), uStir = U('u_stir');

  // The fbm stack is heavy, so it renders at half resolution and CSS scales it up.
  function resize() {
    const s = 0.5 * Math.min(window.devicePixelRatio || 1, 1.5);
    const w = Math.max(1, Math.round(innerWidth * s)), h = Math.max(1, Math.round(innerHeight * s));
    if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
    gl.viewport(0, 0, w, h);
  }

  // Cursor stirring, desktop only.
  const mouse = { tx: 0, ty: 0, x: 0, y: 0, vx: 0, vy: 0, stir: 0, seen: false };
  if (!reduced && matchMedia('(hover: hover) and (pointer: fine)').matches) {
    addEventListener('pointermove', e => {
      if (!mouse.seen) { mouse.x = e.clientX; mouse.y = e.clientY; mouse.seen = true; }
      mouse.tx = e.clientX; mouse.ty = e.clientY;
    }, { passive: true });
  }

  const start = performance.now();
  function draw(now) {
    resize();
    if (mouse.seen) {
      const px = mouse.x, py = mouse.y;
      mouse.x += (mouse.tx - mouse.x) * 0.18;
      mouse.y += (mouse.ty - mouse.y) * 0.18;
      const dx = mouse.x - px, dy = mouse.y - py;
      mouse.vx = mouse.vx * 0.85 + dx * 0.15;
      mouse.vy = mouse.vy * 0.85 + dy * 0.15;
      mouse.stir = Math.min(1, mouse.stir * 0.965 + Math.hypot(dx, dy) * 0.006);
    }
    const sx = canvas.width / innerWidth, sy = canvas.height / innerHeight;
    const k = 1.5 / canvas.height * 8;
    let vx = mouse.vx * sx * k, vy = -mouse.vy * sy * k;
    const vl = Math.hypot(vx, vy); if (vl > 0.6) { vx *= 0.6 / vl; vy *= 0.6 / vl; }
    gl.uniform2f(uRes, canvas.width, canvas.height);
    gl.uniform1f(uTime, reduced ? 12 : (now - start) / 1000 + 12);
    gl.uniform2f(uMouse, mouse.x * sx, (innerHeight - mouse.y) * sy);
    gl.uniform2f(uVel, vx, vy);
    gl.uniform1f(uStir, mouse.stir);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  // The canvas is the whole site's background, so it runs while the tab is visible.
  let raf = 0;
  function loop(now) { draw(now); raf = requestAnimationFrame(loop); }
  function run() { cancelAnimationFrame(raf); if (reduced) { draw(performance.now()); return; } if (!document.hidden) raf = requestAnimationFrame(loop); }
  document.addEventListener('visibilitychange', run);
  addEventListener('resize', () => draw(performance.now()));
  (document.fonts ? document.fonts.load("100px 'Sunset Script'") : Promise.resolve()).finally(run);
})();
