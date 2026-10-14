// Motion model shared with the iOS client (ios/TrainsCore/Sources/TrainsCore/Motion.swift).
// Both implementations are checked against test/fixtures/motion-vectors.json.
import type { MotionPlan } from './model.ts';

export const MIN_DWELL_MS = 30_000;

/**
 * Distance along the route at time t, dead-reckoned from the plan.
 * Between anchors the train moves at constant speed toward the next predicted arrival and
 * waits at each stop until its predicted departure. If a predicted arrival is already in the
 * past the train creeps on at the fallback speed, then dwells briefly before continuing.
 * The result never decreases with t and never passes maxD.
 */
export function distanceAt(plan: MotionPlan, t: number): number {
  let d = plan.d0, now = plan.t0;
  if (t <= now) return Math.min(d, plan.maxD);
  for (const s of plan.stops) {
    if (s.d < d) continue; // already past this stop
    // travel leg to the stop
    const overdue = s.arr <= now;
    const legEnd = overdue ? now + ((s.d - d) / Math.max(plan.fallbackSpeed, 0.1)) * 1000 : s.arr;
    if (t < legEnd) return Math.min(d + ((s.d - d) * (t - now)) / (legEnd - now), plan.maxD);
    d = s.d; now = legEnd;
    // dwell until the predicted departure; an overdue train also gets a minimum dwell
    const leave = Math.max(s.dep, overdue ? now + MIN_DWELL_MS : now);
    if (t < leave) return Math.min(d, plan.maxD);
    now = leave;
  }
  // beyond the last known stop: coast at fallback speed to the end of the line
  return Math.min(d + (plan.fallbackSpeed * (t - now)) / 1000, plan.maxD);
}

/**
 * Display smoother: eases the drawn position toward the dead-reckoned target without ever
 * moving backward. A large backward correction (bad data, rerouting) is applied as a snap so
 * the client can cross-fade instead of sliding the marker in reverse.
 */
export interface Smoothed { d: number; snapped: boolean }
export const SNAP_BACK_M = 3000, SNAP_FORWARD_M = 5000, EASE_TAU_S = 1.5;

export function smoothStep(displayed: number, target: number, dtS: number): Smoothed {
  const gap = target - displayed;
  if (gap < -SNAP_BACK_M || gap > SNAP_FORWARD_M) return { d: target, snapped: true };
  if (gap <= 0) return { d: displayed, snapped: false }; // hold; the target will catch up
  const k = 1 - Math.exp(-dtS / EASE_TAU_S);
  return { d: displayed + gap * k, snapped: false };
}
