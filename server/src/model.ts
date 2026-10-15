// Normalised train model. Every feed adapter produces RawTrain; the positioner turns it into TrainState.
import type { FeedId } from './routes.ts';

export type Operator = FeedId;
export type Source = 'live' | 'scheduled';

/** What an adapter knows about one stop of one trip. Times are epoch ms. */
export interface RawStop {
  stationId: string;            // feed-native station id (Amtrak code, GTFS parent stop id)
  name?: string;
  schArr?: number; schDep?: number;
  estArr?: number; estDep?: number; // live prediction, or actual time once passed
  departed: boolean;
  skipped?: boolean;
  track?: string;
}

/** The normalised record from the brief: tripId, operator, route, trainNumber, position or stop times, delay, source. */
export interface RawTrain {
  tripId: string;
  operator: Operator;
  /** Service day the trip belongs to, YYYYMMDD (local New York date of its scheduled start). */
  serviceDate?: string;
  route: string;                // route id (GTFS) or route name (Amtrak)
  routeName: string;
  trainNumber: string;
  headsign?: string;
  position?: { lat: number; lon: number; at: number; speedMps?: number };
  stops: RawStop[];
  delaySec: number | null;
  source: Source;
  updatedAt: number;
  cancelled?: boolean;
  /** How to find the route geometry: GTFS shape id + station list of the matching static trip. */
  shape?: { shapeId: string; stations: string[] };
  color?: string;
}

/** An upcoming stop as a motion anchor: reach distance d at arr, leave at dep (epoch ms). */
export interface PlanStop { d: number; arr: number; dep: number }

export interface MotionPlan {
  /** Distance along the shape at anchor time t0. */
  d0: number; t0: number;
  /** Speed to use when a predicted arrival is already in the past (m/s). */
  fallbackSpeed: number;
  /** Never move faster than this, even to make an optimistic predicted arrival (m/s). */
  maxSpeed: number;
  stops: PlanStop[];
  /** End of the line; the train never moves past this. */
  maxD: number;
}

export interface TrainStop {
  stationId: string; hubId: string; name: string; d: number;
  schArr: number | null; schDep: number | null; estArr: number | null; estDep: number | null;
  status: 'departed' | 'upcoming' | 'skipped'; track?: string;
}

export interface TrainState {
  id: string;                   // `${operator}:${tripId}`
  operator: Operator;
  tripId: string;
  serviceDate: string | null;
  trainNumber: string;
  route: string; routeName: string; headsign: string; color: string;
  shape: string | null;         // route geometry key, or null when unmatched (raw position only)
  distM: number;                // distance along shape at updatedAt
  lat: number; lon: number; bearing: number;
  speedMps: number;
  delaySec: number | null;
  source: Source;
  /** How the position was found: GPS report, live stop predictions, or the timetable alone. */
  fix: 'gps' | 'predicted' | 'timetable';
  status: 'scheduled' | 'enroute' | 'atStation' | 'completed' | 'cancelled';
  updatedAt: number;
  plan: MotionPlan | null;
  origin: string; destination: string;
  progress: number;             // 0..1 between origin and destination, by distance
  next: { stationId: string; name: string; eta: number | null } | null;
  stops: TrainStop[];
}

/** Compact form broadcast to map clients (stops omitted; fetch /api/trains/:id for those). */
export type TrainSummary = Omit<TrainState, 'stops'>;

export interface LiveEvent {
  id: number; at: number; trainId: string; operator: Operator;
  kind: 'departed' | 'arrived' | 'delay' | 'cancelled' | 'tracking';
  text: string;                 // "Acela 2153 departed NYP, 4 min late"
  delaySec: number | null;
}
