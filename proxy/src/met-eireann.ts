import { XMLParser } from "fast-xml-parser";
import { ForecastEntry } from "./types";

const MET_EIREANN_BASE =
  "http://openaccess.pf.api.met.ie/metno-wdb2ts/locationforecast";

// Dublin coordinates used as a fixed reference point for model-status checks
const REFERENCE_LAT = "53.350";
const REFERENCE_LON = "-6.260";

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
});

interface ParsedForecast {
  modelRun: string;
  forecasts: ForecastEntry[];
}

export async function fetchAndParseForecast(
  lat: string,
  lon: string
): Promise<ParsedForecast> {
  const url = `${MET_EIREANN_BASE}?lat=${lat};long=${lon}`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Met Eireann API returned ${response.status}`);
  }
  const xml = await response.text();
  return parseWeatherXml(xml);
}

export async function fetchModelRunTimestamp(): Promise<string> {
  const { modelRun } = await fetchAndParseForecast(
    REFERENCE_LAT,
    REFERENCE_LON
  );
  return modelRun;
}

function parseWeatherXml(xml: string): ParsedForecast {
  const parsed = parser.parse(xml);

  // Extract HARMONIE model run timestamp from <meta>
  const models = parsed.weatherdata.meta.model;
  const modelsArr = Array.isArray(models) ? models : [models];
  const harmonie = modelsArr.find(
    (m: Record<string, string>) => m["@_name"] === "harmonie"
  );
  const modelRun: string = harmonie?.["@_termin"] ?? "";

  // Extract wind data from point-in-time forecasts (from === to)
  const times = parsed.weatherdata.product.time;
  const timesArr = Array.isArray(times) ? times : [times];

  // Include the current hour's forecast even if the clock has moved past it.
  // The most recent hourly entry represents "current conditions" for display.
  const now = Date.now();
  const minTime = now - 60 * 60 * 1000; // 1 hour ago (keep current slot)
  const maxTime = now + 7 * 60 * 60 * 1000; // 7 hours ahead

  const forecasts: ForecastEntry[] = [];

  for (const entry of timesArr) {
    const from: string = entry["@_from"];
    const to: string = entry["@_to"];

    // Only point forecasts (from === to) carry wind data
    if (from !== to) {
      continue;
    }

    const entryTime = new Date(from).getTime();
    if (entryTime < minTime || entryTime > maxTime) {
      continue;
    }

    const loc = entry.location;
    if (!loc?.windSpeed || !loc?.windDirection || !loc?.windGust) {
      continue;
    }

    forecasts.push({
      time: from,
      wind_mps: parseFloat(loc.windSpeed["@_mps"]),
      wind_deg: parseFloat(loc.windDirection["@_deg"]),
      wind_beaufort: parseInt(loc.windSpeed["@_beaufort"], 10),
      gust_mps: parseFloat(loc.windGust["@_mps"]),
    });
  }

  return { modelRun, forecasts };
}
