// Live event ticker: departures, arrivals, delay jumps, cancellations ("Acela 2153 departed NYP, 4 min late").
import type { LiveEvent, TrainState } from '../model.ts';

const DELAY_STEP_S = 5 * 60;
const OPERATOR_NAME: Record<string, string> = { amtrak: 'Amtrak', lirr: 'LIRR', mnr: 'Metro-North', njt: 'NJ Transit' };

export function trainLabel(t: Pick<TrainState, 'operator' | 'routeName' | 'trainNumber'>): string {
  if (t.operator === 'amtrak') return `${t.routeName || 'Amtrak'} ${t.trainNumber}`;
  return `${OPERATOR_NAME[t.operator] ?? t.operator} ${t.trainNumber}`;
}

export function lateness(sec: number | null): string {
  if (sec === null) return '';
  const m = Math.round(sec / 60);
  if (m <= 1 && m >= -1) return 'on time';
  return m > 0 ? `${m} min late` : `${-m} min early`;
}

export class EventLog {
  private items: LiveEvent[] = [];
  private nextId = 1;
  private max: number;
  constructor(max = 300) { this.max = max; }

  recent(n: number): LiveEvent[] { return this.items.slice(-n).reverse(); }

  private add(e: Omit<LiveEvent, 'id'>): LiveEvent {
    const ev = { ...e, id: this.nextId++ };
    this.items.push(ev);
    if (this.items.length > this.max) this.items.shift();
    return ev;
  }

  /** Events implied by the change from `prev` to `next` for one train. */
  diff(prev: TrainState | undefined, next: TrainState, now: number, quiet: boolean): LiveEvent[] {
    const out: LiveEvent[] = [];
    const label = trainLabel(next);
    const base = { trainId: next.id, operator: next.operator };
    if (!prev) {
      if (!quiet && next.source === 'live' && next.status === 'enroute') out.push(this.add({ ...base, at: now, kind: 'tracking', delaySec: next.delaySec, text: `${label} to ${next.destination} is now tracking` }));
      return out;
    }
    if (next.status === 'cancelled' && prev.status !== 'cancelled') {
      out.push(this.add({ ...base, at: now, kind: 'cancelled', delaySec: null, text: `${label} to ${next.destination} cancelled` }));
      return out;
    }
    const prevStatus = new Map(prev.stops.map((s) => [s.stationId, s.status]));
    const lastIdx = next.stops.length - 1;
    next.stops.forEach((s, i) => {
      if (s.status !== 'departed' || prevStatus.get(s.stationId) !== 'upcoming') return;
      const late = s.estDep !== null && s.schDep !== null ? Math.round((s.estDep - s.schDep) / 1000) : null;
      const where = next.operator === 'amtrak' ? s.stationId : s.name;
      if (i === lastIdx) out.push(this.add({ ...base, at: s.estArr ?? now, kind: 'arrived', delaySec: late, text: `${label} arrived ${where}${late !== null ? ', ' + lateness(late) : ''}` }));
      else out.push(this.add({ ...base, at: s.estDep ?? now, kind: 'departed', delaySec: late, text: `${label} departed ${where}${late !== null ? ', ' + lateness(late) : ''}` }));
    });
    if (next.delaySec !== null && prev.delaySec !== null &&
        Math.floor(next.delaySec / DELAY_STEP_S) > Math.floor(Math.max(0, prev.delaySec) / DELAY_STEP_S) && next.delaySec >= DELAY_STEP_S) {
      out.push(this.add({ ...base, at: now, kind: 'delay', delaySec: next.delaySec, text: `${label} now ${lateness(next.delaySec)}${next.next ? ' approaching ' + next.next.name : ''}` }));
    }
    return out;
  }
}
