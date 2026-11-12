// Draws the addon's few textures from simple shapes and writes them as
// 32-bit .tga files (for the game) and .png files (for preview/).
// Usage: node tools/textures.js
// Every size is a power of two, as WoW requires.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const ROOT = path.join(__dirname, "..");
const TGA_DIR = path.join(ROOT, "Media", "Textures");
const PNG_DIR = path.join(ROOT, "preview", "img");

// Colours come from UI/Theme.lua (gold, beard); keep them in step.
const GOLD = [255, 192, 0];
const BEARD = [240, 107, 176];
const WHITE = [255, 255, 255];

// ---- shape tests (coordinates in a 0..size box, y down) -------------------
function inPolygon(x, y, pts) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function distToSegment(x, y, [ax, ay], [bx, by]) {
  const dx = bx - ax, dy = by - ay;
  const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(x - (ax + t * dx), y - (ay + t * dy));
}
const poly = (pts, color) => ({ color, hit: (x, y) => inPolygon(x, y, pts) });
const circle = (cx, cy, r, color) => ({ color, hit: (x, y) => Math.hypot(x - cx, y - cy) <= r });
const ellipse = (cx, cy, rx, ry, color) => ({ color, hit: (x, y) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1 });
const ring = (cx, cy, r, w, color) => ({ color, hit: (x, y) => Math.abs(Math.hypot(x - cx, y - cy) - r) <= w / 2 });
const line = (a, b, w, color) => ({ color, hit: (x, y) => distToSegment(x, y, a, b) <= w / 2 });
const cut = (shape) => ({ cut: true, hit: shape.hit });

// Rasterise with 8x8 supersampling. Later shapes paint over earlier ones;
// a `cut` shape clears what is under it.
function render(size, shapes) {
  const px = Buffer.alloc(size * size * 4);
  const S = 8;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < S; sy++) {
        for (let sx = 0; sx < S; sx++) {
          const fx = x + (sx + 0.5) / S, fy = y + (sy + 0.5) / S;
          let c = null;
          for (const s of shapes) if (s.hit(fx, fy)) c = s.cut ? null : s.color;
          if (c) { r += c[0]; g += c[1]; b += c[2]; a += 1; }
        }
      }
      const i = (y * size + x) * 4;
      if (a) { px[i] = r / a; px[i + 1] = g / a; px[i + 2] = b / a; }
      px[i + 3] = Math.round((a / (S * S)) * 255);
    }
  }
  return px;
}

function writeTGA(file, size, rgba) {
  const head = Buffer.alloc(18);
  head[2] = 2;                       // uncompressed true-colour
  head.writeUInt16LE(size, 12);
  head.writeUInt16LE(size, 14);
  head[16] = 32;                     // bits per pixel
  head[17] = 0x28;                   // 8 alpha bits, top-left origin
  const body = Buffer.alloc(size * size * 4);
  for (let i = 0; i < size * size; i++) {
    body[i * 4] = rgba[i * 4 + 2];   // BGRA
    body[i * 4 + 1] = rgba[i * 4 + 1];
    body[i * 4 + 2] = rgba[i * 4];
    body[i * 4 + 3] = rgba[i * 4 + 3];
  }
  fs.writeFileSync(file, Buffer.concat([head, body]));
}

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function writePNG(file, size, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = 6;          // 8-bit RGBA
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) rgba.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0)),
  ]));
}

// ---- the textures -----------------------------------------------------------
// Crest: a short king. A three-point gold crown over a pink beard, drawn on a
// 64 box (no face, no fake mascot art).
const crest = [
  poly([[12, 30], [12, 12], [22, 21], [32, 8], [42, 21], [52, 12], [52, 30]], GOLD),
  circle(12, 11, 3, GOLD), circle(32, 7, 3, GOLD), circle(52, 11, 3, GOLD),
  // forked beard, then a moustache across its top
  poly([[11, 39], [53, 39], [51, 50], [40, 62], [32, 55], [24, 62], [13, 50]], BEARD),
  ellipse(21, 37, 12, 4.2, BEARD), ellipse(43, 37, 12, 4.2, BEARD),
  cut(ellipse(32, 41.5, 3.2, 2.2, WHITE)),                          // mouth
];

// Five-pointed star (favourites), centred in a 16 box.
const starPts = [];
for (let i = 0; i < 10; i++) {
  const r = i % 2 === 0 ? 7.5 : 3.2, a = -Math.PI / 2 + (i * Math.PI) / 5;
  starPts.push([8 + r * Math.cos(a), 8.6 + r * Math.sin(a)]);
}

// v0.6.0 sidebar icons: white outlines on a 32 box (stroke 2.5), tinted in game.
const W2 = 2.5;
const box = (x0, y0, x1, y1) => [line([x0, y0], [x1, y0], W2, WHITE), line([x1, y0], [x1, y1], W2, WHITE),
  line([x1, y1], [x0, y1], W2, WHITE), line([x0, y1], [x0, y0], W2, WHITE)];
const arc = (cx, cy, r, from, to, w) => {
  const out = [];
  const n = 16;
  for (let i = 0; i < n; i++) {
    const a = from + ((to - from) * i) / n, b = from + ((to - from) * (i + 1)) / n;
    out.push(line([cx + r * Math.cos(a), cy + r * Math.sin(a)], [cx + r * Math.cos(b), cy + r * Math.sin(b)], w, WHITE));
  }
  return out;
};
const ICONS = {
  "icon-overview": [...box(5, 5, 14, 14), ...box(18, 5, 27, 14), ...box(5, 18, 14, 27), ...box(18, 18, 27, 27)],
  "icon-roster": [ring(12, 11, 4.5, W2, WHITE), ...arc(12, 27, 8.5, Math.PI, 2 * Math.PI, W2),
    ring(23, 12, 3.5, W2, WHITE), ...arc(23, 26, 6.5, 1.25 * Math.PI, 2 * Math.PI, W2)],
  "icon-character": [ring(16, 10, 5, W2, WHITE), ...arc(16, 28, 10, Math.PI, 2 * Math.PI, W2)],
  "icon-crafters": [ring(14, 14, 8, W2, WHITE), line([20, 20], [27, 27], 3, WHITE)],
  "icon-professions": [line([12, 5], [20, 5], W2, WHITE), line([13, 5], [13, 13], W2, WHITE), line([19, 5], [19, 13], W2, WHITE),
    line([13, 13], [6, 25], W2, WHITE), line([19, 13], [26, 25], W2, WHITE), line([6, 25], [8, 27], W2, WHITE),
    line([26, 25], [24, 27], W2, WHITE), line([8, 27], [24, 27], W2, WHITE), line([10, 20], [22, 20], W2, WHITE)],
  "icon-settings": [line([5, 10], [17, 10], W2, WHITE), line([24, 10], [27, 10], W2, WHITE), ring(20.5, 10, 3.2, W2, WHITE),
    line([5, 22], [8, 22], W2, WHITE), line([15, 22], [27, 22], W2, WHITE), ring(11.5, 22, 3.2, W2, WHITE)],
};

const TEXTURES = {
  ...Object.fromEntries(Object.entries(ICONS).map(([k, v]) => [k, [32, v]])),
  // A switch track: a pill across the middle of a 32 box (shown with texcoords 0.25-0.75 vertically).
  pill: [32, [circle(8, 16, 7.5, WHITE), circle(24, 16, 7.5, WHITE), poly([[8, 8.5], [24, 8.5], [24, 23.5], [8, 23.5]], WHITE)]],
  chevron: [16, [line([6, 4], [10.5, 8], 1.8, WHITE), line([10.5, 8], [6, 12], 1.8, WHITE)]],
  crest: [64, crest],
  // White glyphs, tinted in game with SetVertexColor.
  arrow: [16, [poly([[8, 4], [14, 12], [2, 12]], WHITE)]],
  close: [16, [line([4, 4], [12, 12], 2, WHITE), line([12, 4], [4, 12], 2, WHITE)]],
  dot: [16, [circle(8, 8, 6, WHITE)]],
  ring: [32, [ring(16, 16, 13, 2.5, WHITE)]],
  star: [16, [poly(starPts, WHITE)]],
};

fs.mkdirSync(TGA_DIR, { recursive: true });
fs.mkdirSync(PNG_DIR, { recursive: true });
// Large crest for the README banner only (PNG, not shipped to the game).
const scale = (s, k) => ({ ...s, hit: (x, y) => s.hit(x / k, y / k) });
{
  const k = 8, px = render(64 * k, crest.map((s) => scale(s, k)));
  writePNG(path.join(PNG_DIR, "crest-large.png"), 64 * k, px);
  console.log("wrote crest-large 512x512 (PNG only)");
}

for (const [name, [size, shapes]] of Object.entries(TEXTURES)) {
  const px = render(size, shapes);
  writeTGA(path.join(TGA_DIR, name + ".tga"), size, px);
  writePNG(path.join(PNG_DIR, name + ".png"), size, px);
  console.log("wrote", name, size + "x" + size);
}
