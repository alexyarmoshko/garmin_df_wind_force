import {
  Env,
  RawForecastEntry,
  RawForecastResponse,
  ForecastEntry,
  ForecastResponse,
} from "./types";
import { fetchAndParseForecast, fetchModelRunTimestamp } from "./met-eireann";

const API_VERSION = "v1";
const FORECAST_TTL = 25_200; // 7 hours
const MODEL_STATUS_TTL = 900; // 15 minutes

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

/** Round a coordinate to the nearest 0.025 deg (~2.5 km HARMONIE grid). */
function roundCoord(value: number): string {
  return (Math.round(value / 0.025) * 0.025).toFixed(3);
}

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: CORS_HEADERS });
}

function errorResponse(message: string, status: number): Response {
  return jsonResponse({ error: message }, status);
}

// ── Unit conversion ───────────────────────────────────────────────────

export type WindUnit = "beaufort" | "knots" | "mph" | "kmh" | "mps";

const VALID_UNITS: Set<string> = new Set([
  "beaufort",
  "knots",
  "mph",
  "kmh",
  "mps",
]);

/** Beaufort scale breakpoints in m/s. Index = Beaufort number. */
const BEAUFORT_MPS = [
  0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7,
];

function mpsToBeaufort(mps: number): number {
  for (let i = 0; i < BEAUFORT_MPS.length; i++) {
    if (mps < BEAUFORT_MPS[i]) return i;
  }
  return 12;
}

function convertMps(mps: number, unit: WindUnit): number {
  switch (unit) {
    case "beaufort":
      return mpsToBeaufort(mps);
    case "knots":
      return Math.round(mps * 1.94384);
    case "mph":
      return Math.round(mps * 2.23694);
    case "kmh":
      return Math.round(mps * 3.6);
    case "mps":
      return Math.round(mps);
  }
}

// ── Direction labels ──────────────────────────────────────────────────

const DIRECTION_LABELS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

function degToCardinal(deg: number): string {
  const idx = Math.round(((deg % 360) + 360) % 360 / 45) % 8;
  return DIRECTION_LABELS[idx];
}

// ── Slot selection ────────────────────────────────────────────────────

function parseSlots(slotsParam: string | null): number[] {
  if (!slotsParam) return [0];
  const parts = slotsParam
    .split(",")
    .map((s) => parseInt(s.trim(), 10))
    .filter((n) => !isNaN(n) && n >= 0 && n <= 7);
  if (parts.length === 0) return [0];
  return parts.slice(0, 3); // max 3 slots
}

/** Find the "current" entry: the most recent entry at or before now.
 *  Falls back to the earliest available entry if none is at-or-before now. */
function selectCurrentEntry(
  forecasts: RawForecastEntry[]
): RawForecastEntry | null {
  if (forecasts.length === 0) return null;
  const now = Date.now();
  let best: RawForecastEntry | null = null;
  for (const entry of forecasts) {
    const t = new Date(entry.time).getTime();
    if (t <= now && (!best || t > new Date(best.time).getTime())) {
      best = entry;
    }
  }
  return best ?? forecasts[0];
}

/** Pick the entry whose time is closest to the given target timestamp. */
function selectClosest(
  forecasts: RawForecastEntry[],
  targetMs: number
): RawForecastEntry | null {
  if (forecasts.length === 0) return null;
  let best = forecasts[0];
  let bestDiff = Math.abs(new Date(best.time).getTime() - targetMs);
  for (let i = 1; i < forecasts.length; i++) {
    const diff = Math.abs(new Date(forecasts[i].time).getTime() - targetMs);
    if (diff < bestDiff) {
      best = forecasts[i];
      bestDiff = diff;
    }
  }
  return best;
}

/** Select slots, convert units, and compute direction labels.
 *  Slot 0 is anchored to the current hour (most recent entry at-or-before
 *  now). Later slots are offset from the current entry's time, not from
 *  Date.now(), so they stay aligned to hourly boundaries. */
function buildResponse(
  raw: RawForecastResponse,
  unit: WindUnit,
  slots: number[]
): ForecastResponse {
  const current = selectCurrentEntry(raw.forecasts);
  if (!current) {
    return { api_version: API_VERSION, model_run: raw.model_run, units: unit, forecasts: [] };
  }

  const baseTime = new Date(current.time).getTime();
  const selected: RawForecastEntry[] = [];
  for (const offset of slots) {
    if (offset === 0) {
      selected.push(current);
    } else {
      const entry = selectClosest(raw.forecasts, baseTime + offset * 3600_000);
      if (entry) selected.push(entry);
    }
  }

  const forecasts: ForecastEntry[] = selected.map((entry) => ({
    time: entry.time,
    wind_speed: convertMps(entry.wind_mps, unit),
    gust_speed: convertMps(entry.gust_mps, unit),
    wind_dir: degToCardinal(entry.wind_deg),
  }));

  return { api_version: API_VERSION, model_run: raw.model_run, units: unit, forecasts };
}

// ── /v1/forecast ──────────────────────────────────────────────────────

async function handleForecast(url: URL, env: Env): Promise<Response> {
  const latParam = url.searchParams.get("lat");
  const lonParam = url.searchParams.get("lon");

  if (!latParam || !lonParam) {
    return errorResponse("Missing lat or lon parameter", 400);
  }

  const lat = parseFloat(latParam);
  const lon = parseFloat(lonParam);

  if (
    isNaN(lat) ||
    isNaN(lon) ||
    lat < -90 ||
    lat > 90 ||
    lon < -180 ||
    lon > 180
  ) {
    return errorResponse("Invalid lat or lon value", 400);
  }

  const roundedLat = roundCoord(lat);
  const roundedLon = roundCoord(lon);

  // Parse optional units and slots params
  const unitsParam = url.searchParams.get("units") ?? "beaufort";
  const unit: WindUnit = VALID_UNITS.has(unitsParam)
    ? (unitsParam as WindUnit)
    : "beaufort";
  const slots = parseSlots(url.searchParams.get("slots"));

  // Resolve the current model run for the cache key
  let modelRun = await env.FORECAST_CACHE.get("latest_model_run");
  if (!modelRun) {
    modelRun = await fetchModelRunTimestamp();
    await env.FORECAST_CACHE.put("latest_model_run", modelRun, {
      expirationTtl: MODEL_STATUS_TTL,
    });
  }

  const cacheKey = `forecast_${roundedLat}_${roundedLon}_${modelRun}`;

  // Check for cached raw forecast
  let raw: RawForecastResponse;
  const cached = await env.FORECAST_CACHE.get(cacheKey);
  if (cached) {
    raw = JSON.parse(cached);
  } else {
    // Fetch fresh data from Met Eireann
    const { modelRun: freshModelRun, forecasts } = await fetchAndParseForecast(
      roundedLat,
      roundedLon
    );

    // Update model run if a newer run appeared
    let effectiveModelRun = modelRun;
    if (freshModelRun && freshModelRun !== modelRun) {
      effectiveModelRun = freshModelRun;
      await env.FORECAST_CACHE.put("latest_model_run", effectiveModelRun, {
        expirationTtl: MODEL_STATUS_TTL,
      });
    }

    raw = { model_run: effectiveModelRun, forecasts };
    const rawKey = `forecast_${roundedLat}_${roundedLon}_${effectiveModelRun}`;
    await env.FORECAST_CACHE.put(rawKey, JSON.stringify(raw), {
      expirationTtl: FORECAST_TTL,
    });
  }

  // Convert and return
  const response = buildResponse(raw, unit, slots);
  return jsonResponse(response);
}

// ── Worker entry point ────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          ...CORS_HEADERS,
          "Access-Control-Allow-Methods": "GET, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    if (request.method !== "GET") {
      return errorResponse("Method not allowed", 405);
    }

    switch (url.pathname) {
      case "/v1/forecast":
        return handleForecast(url, env);
      default:
        return errorResponse("Not found", 404);
    }
  },
} satisfies ExportedHandler<Env>;

// ── Exports for testing ──────────────────────────────────────────────

export {
  roundCoord,
  mpsToBeaufort,
  convertMps,
  degToCardinal,
  parseSlots,
  selectCurrentEntry,
  selectClosest,
  buildResponse,
};
