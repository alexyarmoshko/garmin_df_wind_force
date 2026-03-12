import { Env, ForecastResponse } from "./types";
import { fetchAndParseForecast, fetchModelRunTimestamp } from "./met-eireann";

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

// ── /forecast ────────────────────────────────────────────────────────

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

  // Resolve the current model run for the cache key
  let modelRun = await env.FORECAST_CACHE.get("latest_model_run");
  if (!modelRun) {
    modelRun = await fetchModelRunTimestamp();
    await env.FORECAST_CACHE.put("latest_model_run", modelRun, {
      expirationTtl: MODEL_STATUS_TTL,
    });
  }

  const cacheKey = `forecast_${roundedLat}_${roundedLon}_${modelRun}`;

  // Return cached response if available
  const cached = await env.FORECAST_CACHE.get(cacheKey);
  if (cached) {
    return new Response(cached, { headers: CORS_HEADERS });
  }

  // Fetch fresh data from Met Eireann
  const { modelRun: freshModelRun, forecasts } = await fetchAndParseForecast(
    roundedLat,
    roundedLon
  );

  // Update model run if a newer one appeared
  if (freshModelRun && freshModelRun !== modelRun) {
    modelRun = freshModelRun;
    await env.FORECAST_CACHE.put("latest_model_run", modelRun, {
      expirationTtl: MODEL_STATUS_TTL,
    });
  }

  const response: ForecastResponse = { model_run: modelRun, forecasts };
  const body = JSON.stringify(response);

  await env.FORECAST_CACHE.put(cacheKey, body, {
    expirationTtl: FORECAST_TTL,
  });

  return new Response(body, { headers: CORS_HEADERS });
}

// ── /model-status ────────────────────────────────────────────────────

async function handleModelStatus(env: Env): Promise<Response> {
  const cached = await env.FORECAST_CACHE.get("latest_model_run");
  if (cached) {
    return jsonResponse({ model_run: cached });
  }

  const modelRun = await fetchModelRunTimestamp();
  await env.FORECAST_CACHE.put("latest_model_run", modelRun, {
    expirationTtl: MODEL_STATUS_TTL,
  });

  return jsonResponse({ model_run: modelRun });
}

// ── Worker entry point ───────────────────────────────────────────────

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
      case "/forecast":
        return handleForecast(url, env);
      case "/model-status":
        return handleModelStatus(env);
      default:
        return errorResponse("Not found", 404);
    }
  },
} satisfies ExportedHandler<Env>;
