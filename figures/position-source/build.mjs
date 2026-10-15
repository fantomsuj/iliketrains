// "Where is this train?" -- an Anatomy figure explaining how the map places a train.
// A signal-box panel: three indicator lamps (GPS, stop predictions, timetable), a dial that
// reads the age of the last GPS report with a stop pin at the railroad's age limit, a shuttle
// that steps along under the lamps when the report goes stale, and a counter showing how far
// the train is assumed to have travelled since the report.
//
// The numbers mirror the server: Amtrak GPS is trusted for 15 min, MTA (LIRR, Metro-North)
// for 5 min (server/src/live/positioner.ts, server/src/adapters/gtfsrt.ts); past that the
// train is placed from live stop predictions, and NJ Transit without credentials is
// timetable-only. Distance since the report uses the server's default pace of 20 m/s.
//
// node build.mjs [--light]   writes position-source.html / position-source-light.html
// Query string on the page: ?op=amtrak|mta|njt&age=<seconds>&fix=gps|predicted|timetable
// pins the figure to one train's state (no tour).
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as k from "../../../../system/vendor/anatomy/kit/iso-kit.mjs";
import { kitScript } from "../../../../system/vendor/anatomy/scripts/inline-kit.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const theme = process.argv.includes("--light") ? "light" : "dark";

const WIDTH = 600;
const HEIGHT = 380;

// ---- the model (true numbers) ----
const OPERATORS = [
  { id: "amtrak", name: "Amtrak", limit: 15 },
  { id: "mta", name: "LIRR/Metro-North", limit: 5 },
  { id: "njt", name: "NJ Transit", limit: null },
];
const SCALE_MIN = 20;          // dial range, minutes
const PACE_MPH = 20 * 2.23694; // server DEFAULT_SPEED, 20 m/s

// ---- world layout (units ~ px, z up) ----
const PLATE = { x: -152, y: -72, w: 280, d: 130, r: 8 };
const PLATE_H = 12;
const FOOT_H = 5;

const CONSOLE = { x: -125, y: -64, w: 160, d: 38, r: 3 };
const CONSOLE_H = 18;
const LAMP_X = [-100, -50, 0];
const LAMP_Y = -50;
const BEZEL_R = 9.5;
const BEZEL_H = 2.5;
const JEWEL_R = 6.5;
const JEWEL_H = 3;
const JEWEL_Z = CONSOLE_H + BEZEL_H;
const JEWEL_TOP = JEWEL_Z + JEWEL_H;

const RAIL_FROM = -120;
const RAIL_TO = 22;
const RAIL_Y = [-14, 0];
const RAIL_H = 3;
const SHUTTLE = { x: -14, y: -18, w: 28, d: 24, r: 3 };
const SHUTTLE_TOP = 8;
const STRIP = { x: -106, y: -25, w: 112, d: 5, r: 1 };

const PED = { x: 58, y: -50, w: 50, d: 50, r: 4 };
const PED_H = 14;
const DIAL = [PED.x + PED.w / 2, PED.y + PED.d / 2];
const DIAL_R = 21;
const DIAL_H = 8;
const DIAL_TOP = PED_H + DIAL_H;
const ARC_FROM = (-150 * Math.PI) / 180;
const ARC_SPAN = (300 * Math.PI) / 180;
const PIN_R = 19.9;

const RX = { x: -142, y: 14, w: 46, d: 36, r: 3 };
const RX_H = 10;
const PATCH = { x: -132, y: 21, w: 26, d: 22, r: 2 };

const ODO = { x: 44, y: 16, w: 64, d: 28, r: 2.4 };
const ODO_H = 20;
const ODO_FRONT = ODO.y + ODO.d;
const ODO_SIDE = ODO.x + ODO.w;
const WINDOW = { x0: ODO.x + 14, x1: ODO.x + 44, z0: 6, z1: 15, r: 1.2, depth: 2 };

const P = k.fitProjection(
  [...k.boxCorners(PLATE, -PLATE_H - FOOT_H, 0), [LAMP_X[0], LAMP_Y - BEZEL_R, JEWEL_TOP], [DIAL[0], DIAL[1] - DIAL_R, DIAL_TOP + 3]],
  WIDTH,
  HEIGHT,
  { pad: 30, azimuth: 45 },
);

const at = (point) => k.iso(point, P);
const S = (paths, style) => k.solidSvg(paths, style);
const L = (d, style) => k.lineSvg(d, style);
const D = (points, style) => k.dotsSvg(points, style);
const byDepth = (points) => [...points].sort((a, b) => k.depthOf([a[0], a[1], 0], P) - k.depthOf([b[0], b[1], 0], P));
const planeOf = (y) => k.sideMatrix([0, y], 0, P, "left");
const flat = (x0, z0, x1, z1, r, steps = 6) => k.pathOf(k.roundedPlan({ x: x0, y: z0, w: x1 - x0, d: z1 - z0, r }, steps).map(([u, z]) => [u, -z]), true);
const angleOf = (minutes) => ARC_FROM + (Math.min(SCALE_MIN, Math.max(0, minutes)) / SCALE_MIN) * ARC_SPAN;
const onDial = (angle, radius) => [DIAL[0] + Math.sin(angle) * radius, DIAL[1] - Math.cos(angle) * radius];

function screws(plan, inset, z) {
  const points = k.corners(plan, inset);
  return L(points.map(([x, y]) => k.ring(x, y, 1.8, z, P, 14)).join(""), { tone: "lo" }) + D(points.map(([x, y]) => at([x, y, z])), { size: 0.45 });
}

function plate() {
  const out = [`<path class="iso-halo" d="${k.haloOf(PLATE, -PLATE_H - FOOT_H, PLATE_H, P)}"/>`];
  for (const [x, y] of byDepth(k.corners(PLATE, 22))) {
    out.push(S(k.cylinder(x, y, 7, -PLATE_H - FOOT_H, 1.6, P, 28), { tone: "lo" }));
    out.push(S(k.cylinder(x, y, 5.4, -PLATE_H - FOOT_H + 1.6, FOOT_H - 1.6, P, 28), { tone: "mid" }));
  }
  out.push(S(k.slabOf(PLATE, -PLATE_H, PLATE_H, P, 8, 1.6), { tone: "mid" }));
  out.push(L(k.planOutline(k.insetPlan(PLATE, 5), 0, P), { tone: "lo" }));
  out.push(screws(PLATE, 10, 0));
  // label plate at the front edge: the panel's makers' plate
  const label = { x: -66, y: PLATE.y + PLATE.d - 20, w: 52, d: 9, r: 1 };
  out.push(S(k.slabOf(label, 0, 0.8, P, 4), { tone: "lo", crease: "none" }));
  out.push(L(k.planOutline(k.insetPlan(label, 1.6), 0.8, P), { tone: "faint" }));
  [[label.x + 3, label.x + 34], [label.x + 3, label.x + 24], [label.x + 3, label.x + 18]].forEach(([x0, x1], i) => out.push(L(k.lineOnTop([x0 + 2, label.y + 3 + i * 1.6], [x1 + 2, label.y + 3 + i * 1.6], 0.8, P), { tone: "lo", free: true })));
  out.push(D([at([label.x + 2.6, label.y + label.d / 2, 0.8]), at([label.x + label.w - 2.6, label.y + label.d / 2, 0.8])], { size: 0.4 }));
  return out.join("");
}

function consoleBlock() {
  const out = [`<path class="iso-halo" d="${k.haloOf(k.insetPlan(CONSOLE, 2), 0, 0.1, P)}" style="filter:blur(4px)"/>`];
  const seam = L(k.sideSeam(CONSOLE, 4, P, 4), { tone: "faint" });
  out.push(S(k.slabOf(CONSOLE, 0, CONSOLE_H, P, 4, 0.8), { tone: "mid", inner: seam }));
  out.push(L(k.planOutline(k.insetPlan(CONSOLE, 3), CONSOLE_H, P, 4), { tone: "faint" }));
  out.push(screws(CONSOLE, 6, CONSOLE_H));
  // vent slots on the front face, closed outlines between the lamps' label plates
  out.push(`<g transform="${planeOf(CONSOLE.y + CONSOLE.d)}">${L([-116, -112, -108].map((x) => flat(x, 7, x + 1.6, 13, 0.8, 3)).join("") + [16, 20, 24].map((x) => flat(x, 7, x + 1.6, 13, 0.8, 3)).join(""), { tone: "lo" })}</g>`);
  for (const x of LAMP_X) {
    // label plate in front of each lamp: two rule lines stand for its engraved word
    const plan = { x: x - 9, y: -38, w: 18, d: 5.5, r: 1 };
    out.push(S(k.slabOf(plan, CONSOLE_H, 0.6, P, 3), { tone: "lo", crease: "none" }));
    out.push(L(k.lineOnTop([x - 6, -36.4], [x + 5, -36.4], CONSOLE_H + 0.6, P) + k.lineOnTop([x - 6, -34.6], [x + 1, -34.6], CONSOLE_H + 0.6, P), { tone: "lo", free: true }));
    // bezel and its screws
    out.push(S(k.cylinder(x, LAMP_Y, BEZEL_R, CONSOLE_H, BEZEL_H, P, 40, 0.5), { tone: "mid" }));
    out.push(L(k.ring(x, LAMP_Y, BEZEL_R - 1.2, JEWEL_Z, P, 40), { tone: "faint" }));
    const bolts = [45, 135, 225, 315].map((a) => [x + Math.sin((a * Math.PI) / 180) * 8.2, LAMP_Y - Math.cos((a * Math.PI) / 180) * 8.2]);
    out.push(D(bolts.map(([bx, by]) => at([bx, by, JEWEL_Z])), { size: 0.4 }));
  }
  return out.join("");
}

// One jewel per lamp, drawn twice: dark glass, and the lit version laid over it (opacity driven live).
function jewels() {
  return LAMP_X.map((x, index) => {
    const glass = k.cylinder(x, LAMP_Y, JEWEL_R, JEWEL_Z, JEWEL_H, P, 40, 0.6);
    const facets = L(k.ring(x, LAMP_Y, JEWEL_R - 2, JEWEL_TOP, P, 32) + k.ring(x, LAMP_Y, 1.6, JEWEL_TOP, P, 16), { tone: "faint" });
    const band = L(k.sideArc(x, LAMP_Y, JEWEL_R, JEWEL_Z + 1, P, 24), { tone: "faint" });
    return `<g data-lamp="${index}">${S(glass, { tone: "hi", crease: "lo", inner: band })}${facets}<g data-glow style="opacity:${index === 0 ? 1 : 0}"><path class="ps-glow" d="${k.haloOf({ x: x - BEZEL_R - 3, y: LAMP_Y - BEZEL_R - 3, w: (BEZEL_R + 3) * 2, d: (BEZEL_R + 3) * 2, r: BEZEL_R + 3 }, CONSOLE_H, 0.1, P)}"/><g class="ps-on">${S(glass, { tone: "hi", lit: true, inner: band })}</g>${L(k.ring(x, LAMP_Y, JEWEL_R - 2, JEWEL_TOP, P, 32), { tone: "faint" })}<path class="ps-core" d="${k.haloOf({ x: x - 2.2, y: LAMP_Y - 2.2, w: 4.4, d: 4.4, r: 2.2 }, JEWEL_TOP, 0.05, P)}"/></g></g>`;
  }).join("");
}

function railsAndStrip() {
  const out = [];
  out.push(S(k.slabOf(STRIP, 0, 0.6, P, 3), { tone: "lo", crease: "none" }));
  const ticks = k.topTicks(-100, 0, 5, 10, STRIP.y + 0.6, 0.6, [1.6, 3.4], P);
  out.push(L(ticks.minor, { tone: "lo" }), L(ticks.major, { tone: "mid" }));
  out.push(D([at([STRIP.x + 2.4, STRIP.y + 2.5, 0.6]), at([STRIP.x + STRIP.w - 2.4, STRIP.y + 2.5, 0.6])], { size: 0.4 }));
  for (const y of RAIL_Y) {
    out.push(S(k.slabOf({ x: RAIL_FROM, y, w: RAIL_TO - RAIL_FROM, d: 4, r: 1 }, 0, RAIL_H, P, 3, 0.4), { tone: "mid" }));
    out.push(D([RAIL_FROM + 5, (RAIL_FROM + RAIL_TO) / 2, RAIL_TO - 5].map((x) => at([x, y + 2, RAIL_H])), { size: 0.4 }));
  }
  return out.join("");
}

function endStop(x) {
  const plan = { x, y: -17, w: 5, d: 22, r: 1.2 };
  return S(k.slabOf(plan, 0, 7, P, 3, 0.5), { tone: "mid" }) + D([at([x + 2.5, -13, 7]), at([x + 2.5, 1, 7])], { size: 0.45 });
}

function shuttle() {
  const out = [`<path class="iso-halo" d="${k.haloOf(k.insetPlan(SHUTTLE, 3), RAIL_H, 0.1, P)}" style="filter:blur(3px)"/>`];
  out.push(S(k.slabOf(SHUTTLE, RAIL_H, SHUTTLE_TOP - RAIL_H, P, 4, 0.6), { tone: "mid" }));
  out.push(L(k.planOutline(k.insetPlan(SHUTTLE, 3), SHUTTLE_TOP, P, 3), { tone: "faint" }));
  out.push(D(k.corners(SHUTTLE, 5.5).map(([x, y]) => at([x, y, SHUTTLE_TOP])), { size: 0.45 }));
  // pointer blade reaching back over the index strip
  out.push(S(k.slabOf({ x: -1.6, y: -24, w: 3.2, d: 10, r: 0.8 }, SHUTTLE_TOP, 1.2, P, 2), { tone: "hi", crease: "lo" }));
  out.push(L(k.lineOnTop([0, -23], [0, -15.4], SHUTTLE_TOP + 1.2, P), { tone: "lo" }));
  // knurled pull on the front face
  out.push(S(k.slabOf({ x: -2, y: SHUTTLE.y + SHUTTLE.d - 1, w: 4, d: 4, r: 1 }, RAIL_H + 1, 2.6, P, 2), { tone: "mid", crease: "none" }));
  out.push(S(k.cylinder(0, SHUTTLE.y + SHUTTLE.d + 4, 3, RAIL_H, 5, P, 20), { tone: "mid" }));
  out.push(L(k.knurl(0, SHUTTLE.y + SHUTTLE.d + 4, 3, RAIL_H, RAIL_H + 5, 18, P), { tone: "lo" }));
  return out.join("");
}

function receiver() {
  const out = [`<path class="iso-halo" d="${k.haloOf(k.insetPlan(RX, 2), 0, 0.1, P)}" style="filter:blur(4px)"/>`];
  out.push(S(k.slabOf(RX, 0, RX_H, P, 4, 0.8), { tone: "mid", inner: L(k.sideSeam(RX, 3, P, 4), { tone: "faint" }) }));
  out.push(screws(RX, 4.5, RX_H));
  out.push(S(k.slabOf(PATCH, RX_H, 1.6, P, 3, 0.4), { tone: "hi", crease: "lo" }));
  out.push(L(k.planOutline(k.insetPlan(PATCH, 2.4), RX_H + 1.6, P, 3), { tone: "faint" }));
  const grid = k.dotGrid(PATCH.x + 5, PATCH.y + 4.5, 5, 4, 4, RX_H + 1.6, P);
  out.push(`<g data-part="patch">${D(grid, { size: 0.5, tone: "lo" })}</g>`);
  out.push(`<g data-part="flash" style="opacity:0">${L(k.planOutline(k.insetPlan(PATCH, 2.4), RX_H + 1.6, P, 3), { tone: "lit" })}${D(grid, { size: 0.6, tone: "hi" })}</g>`);
  // status window on the front face, a closed slot
  out.push(`<g transform="${planeOf(RX.y + RX.d)}">${L(flat(-134, 3.5, -104, 6.5, 1.2, 3), { tone: "lo" })}</g>`);
  return out.join("");
}

function pedestal() {
  const out = [`<path class="iso-halo" d="${k.haloOf(k.insetPlan(PED, 2), 0, 0.1, P)}" style="filter:blur(4px)"/>`];
  out.push(S(k.slabOf(PED, 0, PED_H, P, 4, 0.8), { tone: "mid", inner: L(k.sideSeam(PED, 4, P, 4), { tone: "faint" }) }));
  out.push(screws(PED, 5, PED_H));
  const [x, y] = DIAL;
  out.push(S(k.cylinder(x, y, DIAL_R, PED_H, DIAL_H, P, 64, 0.8), { tone: "hi", crease: "lo" }));
  out.push(L(k.knurl(x, y, DIAL_R, DIAL_TOP - 3.2, DIAL_TOP, 84, P, 0.3), { tone: "lo" }));
  out.push(L(k.sideArc(x, y, DIAL_R, DIAL_TOP - 3.2, P, 40), { tone: "faint" }));
  out.push(L(k.ring(x, y, DIAL_R - 2.2, DIAL_TOP, P, 64), { tone: "lo" }));
  const ticks = k.radialTicks(x, y, DIAL_R - 3, SCALE_MIN, 5, DIAL_TOP, [1.3, 2.8], P, ARC_FROM, ARC_SPAN);
  out.push(L(ticks.minor, { tone: "lo" }), L(ticks.major, { tone: "mid" }));
  out.push(k.faceTextSvg(k.topMatrix([x, y + 9.5], DIAL_TOP, P, "x"), "min", { size: 2.6, tone: "lo", anchor: "middle" }));
  // limit stop pins, one per railroad with a limit, only the active one shown
  OPERATORS.forEach((op, index) => {
    if (op.limit === null) return;
    const [px, py] = onDial(angleOf(op.limit), PIN_R);
    out.push(`<g data-pin="${index}" style="opacity:${index === 0 ? 1 : 0}">${S(k.cylinder(px, py, 1.15, DIAL_TOP, 2.6, P, 16), { tone: "hi", crease: "lo" })}</g>`);
  });
  // crown on the +x side
  out.push(S(k.slabOf({ x: x + DIAL_R - 1, y: y - 2.4, w: 4.5, d: 4.8, r: 1.2 }, PED_H + 2, 4, P, 3), { tone: "mid" }));
  out.push(S(k.slabOf({ x: x + DIAL_R + 3.2, y: y - 3.2, w: 2.4, d: 6.4, r: 1.1 }, PED_H + 1.2, 5.6, P, 3), { tone: "mid" }));
  return out.join("");
}

const needleAt = (minutes) => {
  const angle = ARC_FROM + (Math.min(SCALE_MIN, Math.max(0, minutes)) / SCALE_MIN) * ARC_SPAN;
  const [x, y] = DIAL;
  return lineOnTop([x - Math.sin(angle) * 3.4, y + Math.cos(angle) * 3.4], [x + Math.sin(angle) * (DIAL_R - 4.5), y - Math.cos(angle) * (DIAL_R - 4.5)], DIAL_TOP + 0.2, P);
};
const lineOnTop = (a, b, z, proj) => k.lineOnTop(a, b, z, proj);

function odometer() {
  const out = [`<path class="iso-halo" d="${k.haloOf(k.insetPlan(ODO, 2), 0, 0.1, P)}" style="filter:blur(4px)"/>`];
  out.push(S(k.slabOf(ODO, 0, ODO_H, P, 4, 0.8), { tone: "mid", inner: L(k.sideSeam(ODO, 5, P, 4), { tone: "faint" }) }));
  out.push(L(k.planOutline(k.insetPlan(ODO, 3), ODO_H, P, 4), { tone: "faint" }));
  out.push(screws(ODO, 5, ODO_H));
  // reset knob on top
  const knob = [ODO.x + 50, ODO.y + 15];
  out.push(S(k.cylinder(knob[0], knob[1], 4.6, ODO_H, 4, P, 28), { tone: "mid" }));
  out.push(L(k.knurl(knob[0], knob[1], 4.6, ODO_H, ODO_H + 4, 28, P), { tone: "lo" }));
  out.push(L(k.lineOnTop([knob[0] - 2, knob[1]], [knob[0] + 3.6, knob[1]], ODO_H + 4, P), { tone: "hi" }));
  // vents on the +x face
  const sideSlot = (y, z0, z1) => k.pathOf(k.roundedPlan({ x: y - 0.8, y: z0, w: 1.6, d: z1 - z0, r: 0.8 }, 4).map(([u, z]) => at([ODO_SIDE, u, z])), true);
  out.push(L([22, 26, 30, 34, 38].map((y) => sideSlot(y, 5, 15)).join(""), { tone: "lo" }));
  // the counter window, recessed into the front face
  const ring = k.roundedPlan({ x: WINDOW.x0, y: WINDOW.z0, w: WINDOW.x1 - WINDOW.x0, d: WINDOW.z1 - WINDOW.z0, r: WINDOW.r }, 6);
  const { sinA } = k.cameraOf(P);
  const tops = [];
  const sides = [[], [], [], []];
  const cx = (WINDOW.x0 + WINDOW.x1) / 2;
  const cz = (WINDOW.z0 + WINDOW.z1) / 2;
  ring.forEach(([ax, az], index) => {
    const [bx, bz] = ring[(index + 1) % ring.length];
    const length = Math.hypot(bx - ax, bz - az) || 1;
    let [nx, nz] = [(bz - az) / length, -(bx - ax) / length];
    if (nx * (cx - (ax + bx) / 2) + nz * (cz - (az + bz) / 2) < 0) [nx, nz] = [-nx, -nz];
    if (nx <= 0 && nz <= 0) return;
    const quad = k.pathOf([at([ax, ODO_FRONT, az]), at([bx, ODO_FRONT, bz]), at([bx, ODO_FRONT - WINDOW.depth, bz]), at([ax, ODO_FRONT - WINDOW.depth, az])], true);
    if (nz >= nx) tops.push(quad);
    else sides[Math.min(3, Math.max(0, Math.floor(((nx * -sinA + 1) / 2) * 4)))].push(quad);
  });
  const shape = flat(WINDOW.x0, WINDOW.z0, WINDOW.x1, WINDOW.z1, WINDOW.r);
  out.push(
    `<clipPath id="ps-window"><path transform="${planeOf(ODO_FRONT)}" d="${shape}"/></clipPath>`,
    `<g clip-path="url(#ps-window)">`,
    `<path class="iso-top" d="${tops.join("")}"/>`,
    ...sides.map((d, shade) => (d.length ? `<path class="iso-shade" data-shade="${shade}" d="${d.join("")}"/>` : "")),
    `<g transform="${planeOf(ODO_FRONT - WINDOW.depth)}"><path class="ps-well" d="${shape}"/>`,
    // drum seams between the four digit wheels
    L([WINDOW.x0 + 7.5, WINDOW.x0 + 15, WINDOW.x0 + 22.5].map((x) => `M${x} ${-WINDOW.z0}V${-WINDOW.z1}`).join(""), { tone: "faint" }),
    `<text class="ps-digits" data-part="digits" x="${cx}" y="${-(WINDOW.z0 + 2.4)}" font-size="6.4" text-anchor="middle" textLength="27" lengthAdjust="spacing">00.0</text>`,
    `<path class="iso-line" data-tone="faint" d="${shape}"/></g>`,
    `</g>`,
    `<g transform="${planeOf(ODO_FRONT)}"><path class="iso-line" data-tone="lo" d="${shape}"/></g>`,
  );
  return out.join("");
}

const svg = k.figureSvg({
  width: WIDTH,
  height: HEIGHT,
  label:
    "A signal-box panel that shows how a train is placed on the map. Three indicator lamps stand for GPS, stop predictions and the timetable. A dial reads how old the last GPS report is, with a stop pin at the railroad's limit: 15 minutes for Amtrak, 5 for LIRR and Metro-North. A shuttle under the lamps steps from GPS to stop predictions when the needle passes the pin, and a counter shows how far the train is assumed to have moved since the report.",
  body: [
    plate(),
    consoleBlock(),
    jewels(),
    railsAndStrip(),
    endStop(RAIL_FROM - 5),
    `<g data-part="shuttle" transform="${k.translateAlong(P, [LAMP_X[0], 0, 0])}">${shuttle()}</g>`,
    endStop(RAIL_TO),
    receiver(),
    pedestal(),
    `<path data-part="needle" class="iso-line" data-tone="lit" data-free="start" d="${needleAt(0)}" style="stroke-width:1.1"/>`,
    `<g>${L(k.ring(DIAL[0], DIAL[1], 1.6, DIAL_TOP + 0.2, P, 16), { tone: "mid" })}</g>`,
    odometer(),
  ],
});

const live = `
const P = ${JSON.stringify(P)};
const OPERATORS = ${JSON.stringify(OPERATORS)};
const LAMP_X = ${JSON.stringify(LAMP_X)};
const DIAL = ${JSON.stringify(DIAL)};
const DIAL_R = ${DIAL_R}, DIAL_TOP = ${DIAL_TOP}, SCALE_MIN = ${SCALE_MIN}, ARC_FROM = ${ARC_FROM}, ARC_SPAN = ${ARC_SPAN}, PACE_MPH = ${PACE_MPH};
const needleAt = ${needleAt.toString()};
const stage = document.querySelector(".iso-stage");
const svg = stage.querySelector("svg");
const shuttle = svg.querySelector('[data-part="shuttle"]');
const needle = svg.querySelector('[data-part="needle"]');
const digits = svg.querySelector('[data-part="digits"]');
const flash = svg.querySelector('[data-part="flash"]');
const glows = [...svg.querySelectorAll("[data-lamp] [data-glow]")];
const pins = OPERATORS.map((_, i) => svg.querySelector('[data-pin="' + i + '"]'));
const readout = document.querySelector("[data-readout]");
const still = matchMedia("(prefers-reduced-motion: reduce)");
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const ease = (v, to, dt, tau) => (still.matches ? to : v + (to - v) * (1 - Math.exp(-dt / tau)));

// model: which source places the train, from the railroad and the age of its last GPS report
const sourceOf = (op, age) => (op.limit === null ? 2 : age < op.limit ? 0 : 1);
const SOURCE_WORD = ["GPS", "stop predictions", "timetable"];

let opIndex = 0, age = 0, targetAge = 0, glow = [1, 0, 0], pinLevel = [1, 0, 0];
let shuttleX = LAMP_X[0], flashLevel = 0;
const needleState = { at: 0, rate: 0 };

// optional pin to one train: ?op=amtrak|mta|njt&age=<seconds>&fix=gps|predicted|timetable
const params = new URLSearchParams(location.search);
const pinned = params.has("op");
if (pinned) {
  opIndex = Math.max(0, OPERATORS.findIndex((o) => o.id === params.get("op")));
  targetAge = age = needleState.at = clamp(Number(params.get("age") || 0) / 60, 0, SCALE_MIN);
}

// tour: each railroad's report ages past its limit, then a fresh report arrives
const TOUR = [
  { op: 0, ramp: 9, to: 18.5 }, { op: 0, ramp: 0.01, to: 0, fix: true },
  { op: 1, ramp: 6.5, to: 9 }, { op: 1, ramp: 0.01, to: 0, fix: true },
  { op: 2, ramp: 4.5, to: SCALE_MIN },
  { op: 0, ramp: 0.01, to: 0, fix: true },
];
let touring = !still.matches && !pinned, clock = 0, leg = 0, legFrom = 0;
function tourStep(dt) {
  clock += dt;
  const step = TOUR[leg];
  const share = clamp(clock / step.ramp, 0, 1);
  opIndex = step.op;
  targetAge = legFrom + (step.to - legFrom) * share;
  if (clock >= step.ramp + (step.fix ? 1.4 : 0.9)) {
    clock = 0; legFrom = step.to; leg = (leg + 1) % TOUR.length;
    if (TOUR[leg].fix) newReport();
  }
}
function newReport() { flashLevel = 1; targetAge = 0; }

function shownSource() {
  const op = OPERATORS[opIndex];
  if (pinned && params.has("fix")) return Math.max(0, ["gps", "predicted", "timetable"].indexOf(params.get("fix")));
  return sourceOf(op, needleState.at);
}

let lastText = "";
function draw() {
  const op = OPERATORS[opIndex];
  shuttle.setAttribute("transform", translateAlong(P, [shuttleX, 0, 0]));
  needle.setAttribute("d", needleAt(op.limit === null ? SCALE_MIN : needleState.at));
  glows.forEach((g, i) => (g.style.opacity = glow[i].toFixed(3)));
  pins.forEach((p, i) => p && (p.style.opacity = pinLevel[i].toFixed(3)));
  flash.style.opacity = flashLevel.toFixed(3);
  const src = shownSource();
  const minutes = Math.floor(needleState.at + 1e-6);
  const miles = (needleState.at / 60) * PACE_MPH;
  const counter = src === 0 ? (miles < 10 ? "0" : "") + miles.toFixed(1) : "--.-";
  if (digits.textContent !== counter) digits.textContent = counter;
  let text;
  if (op.limit === null) text = op.name + " · no live feed · timetable";
  else if (src === 0) text = op.name + " · GPS " + minutes + " min old · +" + miles.toFixed(1) + " mi";
  else if (src === 1) text = op.name + " · GPS over " + op.limit + " min · stop times";
  else text = op.name + " · timetable";
  if (text !== lastText) { readout.textContent = text; lastText = text; }
}

function describe() {
  const op = OPERATORS[opIndex];
  stage.setAttribute("aria-valuetext", op.name + ", GPS report " + Math.round(targetAge) + " minutes old, placed by " + SOURCE_WORD[sourceOf(op, targetAge)]);
  stage.setAttribute("aria-valuenow", String(Math.round(targetAge)));
}

let frame = 0, last = 0, visible = false, idleTimer = 0;
function tick(now) {
  const dt = last ? Math.min((now - last) / 1000, 1 / 30) : 1 / 60;
  last = now;
  if (touring) tourStep(dt);
  const op = OPERATORS[opIndex];
  // needle: a fresh report snaps it back on a stiff spring; ageing follows smoothly
  const calm = still.matches;
  if (calm) { needleState.at = targetAge; needleState.rate = 0; }
  else for (let i = 0; i < 4; i++) { needleState.rate += ((targetAge - needleState.at) * 260 - needleState.rate * 24) * dt / 4; needleState.at += needleState.rate * dt / 4; }
  if (Math.abs(targetAge - needleState.at) < 0.002 && Math.abs(needleState.rate) < 0.002) { needleState.at = targetAge; needleState.rate = 0; }
  const src = shownSource();
  shuttleX = ease(shuttleX, LAMP_X[src], dt, 0.22);
  if (Math.abs(shuttleX - LAMP_X[src]) < 0.01) shuttleX = LAMP_X[src];
  // a lamp lights once the shuttle is under it
  glow = glow.map((g, i) => ease(g, Math.abs(shuttleX - LAMP_X[i]) < 6 ? 1 : 0, dt, 0.12));
  pinLevel = pinLevel.map((p, i) => ease(p, i === opIndex ? 1 : 0, dt, 0.25));
  flashLevel = calm ? 0 : flashLevel * Math.exp(-dt / 0.45);
  if (flashLevel < 0.004) flashLevel = 0;
  draw();
  const settled = !touring && needleState.rate === 0 && needleState.at === targetAge && shuttleX === LAMP_X[src] && flashLevel === 0
    && glow.every((g, i) => Math.abs(g - (i === src ? 1 : 0)) < 0.002) && pinLevel.every((p, i) => Math.abs(p - (i === opIndex ? 1 : 0)) < 0.002);
  frame = visible && !settled ? requestAnimationFrame(tick) : 0;
}
const run = () => { if (!frame && visible) { last = 0; frame = requestAnimationFrame(tick); } };
const hold = () => {
  touring = false; clearTimeout(idleTimer);
  if (!pinned) idleTimer = setTimeout(() => { touring = !still.matches; clock = 0; leg = 0; legFrom = targetAge; run(); }, 3600);
  describe(); run();
};
new IntersectionObserver((entries) => { visible = entries[entries.length - 1].isIntersecting; if (visible) run(); }, { rootMargin: "120px 0px" }).observe(stage);
stage.addEventListener("pointermove", (event) => {
  if (event.pointerType === "touch") return;
  const box = svg.getBoundingClientRect();
  targetAge = clamp(((event.clientX - box.left) / box.width - 0.15) / 0.7, 0, 1) * SCALE_MIN;
  hold();
});
stage.addEventListener("click", () => { opIndex = (opIndex + 1) % OPERATORS.length; hold(); });
stage.addEventListener("keydown", (event) => {
  const step = event.shiftKey ? 5 : 1;
  if (event.key === "ArrowRight" || event.key === "ArrowUp") targetAge = clamp(Math.round(targetAge) + step, 0, SCALE_MIN);
  else if (event.key === "ArrowLeft" || event.key === "ArrowDown") targetAge = clamp(Math.round(targetAge) - step, 0, SCALE_MIN);
  else if (event.key === "Home" || event.key === " ") { newReport(); }
  else if (event.key === "End") targetAge = SCALE_MIN;
  else if (event.key === "Enter") opIndex = (opIndex + 1) % OPERATORS.length;
  else return;
  event.preventDefault();
  hold();
});
glow = [0, 1, 2].map((i) => (i === shownSource() ? 1 : 0));
pinLevel = [0, 1, 2].map((i) => (i === opIndex ? 1 : 0));
shuttleX = LAMP_X[shownSource()];
draw(); describe();
`;

const css = `
.ps-well{fill:var(--anatomy-shade-0)}
.iso .ps-on>.iso-solid>.iso-top,.iso .ps-on>.iso-solid>.iso-shade,.iso .ps-on>.iso-solid>.iso-fill{fill:var(--anatomy-strong)}
.iso .ps-on>.iso-solid>.iso-edge,.iso .ps-on>.iso-solid>.iso-crease{stroke:var(--anatomy-strong)}
.ps-core{fill:var(--anatomy-card);filter:blur(1.2px)}
.ps-glow{fill:var(--anatomy-strong);opacity:.22;filter:blur(4px)}
.ps-digits{fill:var(--anatomy-hi);font-family:ui-monospace,"SF Mono",Menlo,monospace;font-weight:600;letter-spacing:.2px}
.iso-stage{cursor:pointer;touch-action:pan-y}
`;

const body = k.plateHtml({
  fig: "Fig 1",
  title: "Where is this train?",
  hint: "Hover: report age · click: railroad",
  readout: "Amtrak · GPS 0 min old · +0.0 mi",
  keys: [
    { mark: "lit", label: "Lit lamp: what places the train now (GPS, stop predictions, timetable)" },
    { mark: "raised", label: "Stop pin: how old a GPS report may get before it is dropped" },
  ],
  caption:
    "The dial reads the age of the train's last GPS report. While it is under the railroad's limit (Amtrak 15 min, LIRR and Metro-North 5 min) the map starts from that report and moves the train on at its pace; the counter shows how far that is. Past the pin the report is dropped and the train is placed from live stop predictions. NJ Transit shares no live positions without a developer account, so its trains run on the timetable.",
  body: `<div class="iso-stage" tabindex="0" role="slider" aria-label="GPS report age: arrow keys change the age, Enter switches railroad, Space delivers a new report" aria-valuemin="0" aria-valuemax="${SCALE_MIN}" aria-valuenow="0">${svg}</div>`,
});

const name = theme === "light" ? "position-source-light.html" : "position-source.html";
writeFileSync(join(HERE, name), k.pageHtml({ title: "Where is this train?", theme, body: `<style>${css}</style>${body}`, script: kitScript() + live }));
console.log("wrote", name);
