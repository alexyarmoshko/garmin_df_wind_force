export interface Env {
  FORECAST_CACHE: KVNamespace;
}

export interface ForecastEntry {
  time: string;
  wind_mps: number;
  wind_deg: number;
  wind_beaufort: number;
  gust_mps: number;
}

export interface ForecastResponse {
  model_run: string;
  forecasts: ForecastEntry[];
}

export interface ModelStatusResponse {
  model_run: string;
}
