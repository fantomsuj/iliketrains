import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { distanceAt, smoothStep } from '../src/motion.ts';
import type { MotionPlan } from '../src/model.ts';

const vectors = JSON.parse(fs.readFileSync(new URL('./fixtures/motion-vectors.json', import.meta.url), 'utf8'));

for (const v of vectors.distance) {
  test(`distanceAt: ${v.name}`, () => {
    for (const [t, d] of v.samples) assert.ok(Math.abs(distanceAt(v.plan, t) - d) < 0.01, `t=${t}: got ${distanceAt(v.plan, t)}, want ${d}`);
  });
}
for (const v of vectors.smooth) {
  test(`smoothStep: ${v.name}`, () => {
    const r = smoothStep(v.displayed, v.target, v.dt);
    assert.ok(Math.abs(r.d - v.expect) < 0.01, `got ${r.d}, want ${v.expect}`);
    assert.equal(r.snapped, v.snapped);
  });
}

test('distanceAt never decreases over time and never exceeds maxD (randomised plans)', () => {
  let seed = 7;
  const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  for (let n = 0; n < 300; n++) {
    const stops = []; let d = rnd() * 2000, t = -60000 + rnd() * 120000;
    for (let i = 0; i < 1 + Math.floor(rnd() * 5); i++) { d += 500 + rnd() * 8000; t += rnd() * 400000 - 50000; stops.push({ d, arr: t, dep: t + rnd() * 60000 }); }
    const plan: MotionPlan = { d0: rnd() * 1000, t0: 0, fallbackSpeed: 1 + rnd() * 40, maxSpeed: 10 + rnd() * 70, stops, maxD: d };
    let prev = -Infinity;
    for (let s = -10000; s < 2_000_000; s += 997) {
      const x = distanceAt(plan, s);
      assert.ok(x >= prev - 1e-6, `plan ${n} went backward at t=${s}: ${prev} -> ${x}`);
      assert.ok(x <= plan.maxD + 1e-6);
      prev = x;
    }
  }
});

test('display loop: 60 fps easing toward a moving target is monotonic and converges', () => {
  // target advances at 30 m/s; a feed update at t=10 s pulls it 400 m back, then 600 m forward at 20 s
  let shown = 0;
  let prev = 0;
  for (let i = 0; i < 60 * 30; i++) {
    const t = i / 60;
    const target = 30 * t + (t >= 10 ? -400 : 0) + (t >= 20 ? 1000 : 0); // +1000 is under the 2 km snap threshold
    shown = smoothStep(shown, target, 1 / 60).d;
    assert.ok(shown >= prev - 1e-9, `moved backward at frame ${i}`);
    prev = shown;
  }
  assert.ok(Math.abs(shown - (30 * 30 + 600)) < 60, `converged to ${shown}`);
});
