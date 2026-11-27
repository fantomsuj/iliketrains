// Pluggable feed adapters. Adding a region or operator = one more FeedAdapter.
import type { RawTrain } from '../model.ts';
import type { Clock, Fetcher } from '../live/fetcher.ts';

export interface AdapterContext { fetcher: Fetcher; clock: Clock }

export interface FeedAdapter {
  readonly id: string;
  /** Human label for health output. */
  readonly label: string;
  /** False when the adapter cannot run (e.g. missing API key); the engine skips it. */
  readonly enabled: boolean;
  readonly disabledReason?: string;
  poll(ctx: AdapterContext): Promise<RawTrain[]>;
}
