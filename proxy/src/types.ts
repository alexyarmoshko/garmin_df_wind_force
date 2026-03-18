export interface Env {
  FORECAST_CACHE: KVNamespace;
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