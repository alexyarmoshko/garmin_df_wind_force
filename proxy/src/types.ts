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

/** Converted forecast entry returned to the watch. */
export interface ForecastEntry {
  time: string;
  wind_speed: number;
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