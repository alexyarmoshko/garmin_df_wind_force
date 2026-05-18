export interface Env {
  FORECAST_CACHE: KVNamespace;
  /** Declared list of accepted X-WF-AppID values. Currently unused at
   *  request time -- the encrypted-path filter relies on APP_AUTH_SECRET
   *  via the X-WF-App-Mac header. Kept so the Wrangler vars surface is
   *  ready for future multi-app-ID routing without a Worker type change. */
  APP_IDS: string[];
  APP_AUTH_SECRET: string;
  /** Optional. Set only during a rotation grace window so the Worker
   *  accepts requests signed with the previous secret while older watch
   *  builds catch up. Cleared via
   *  `make -C proxy secret-app-auth-prev-clear`. */
  APP_AUTH_SECRET_PREV?: string;
}

/** Raw forecast entry as parsed from Met Eireann XML (stored in KV cache). */
export interface RawForecastEntry {
  time: string;
  wind_mps: number;
  wind_deg: number;
  wind_beaufort: number;
  gust_mps: number;
}

/** Converted forecast entry returned to the watch.
 *  All speed values are rounded to integers — no fractional values are ever
 *  returned.  This is a design guarantee: smaller watch displays cannot
 *  accommodate decimal digits, and integer precision is sufficient for
 *  paddling water activities. */
export interface ForecastEntry {
  time: string;
  /** Wind speed as a rounded integer in the requested unit. */
  wind_speed: number;
  /** Gust speed as a rounded integer in the requested unit. */
  gust_speed: number;
  wind_dir: string;
}

export interface ForecastResponse {
  api_version: string;
  model_run: string;
  units: string;
  forecasts: ForecastEntry[];
}

export interface RawForecastResponse {
  model_run: string;
  forecasts: RawForecastEntry[];
}
