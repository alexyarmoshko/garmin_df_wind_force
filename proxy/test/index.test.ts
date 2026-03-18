import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  roundCoord,
  mpsToBeaufort,
  convertMps,
  degToCardinal,
  parseSlots,
  selectCurrentEntry,
  selectClosest,
  buildResponse,
  type WindUnit,
} from "../src/index";
import type { RawForecastEntry, RawForecastResponse } from "../src/types";

// ── roundCoord ───────────────────────────────────────────────────────

describe("roundCoord", () => {
  it("rounds to nearest 0.025", () => {
    expect(roundCoord(53.34)).toBe("53.350");
    expect(roundCoord(-6.22)).toBe("-6.225");
  });

  it("preserves exact grid values", () => {
    expect(roundCoord(53.35)).toBe("53.350");
    expect(roundCoord(0.0)).toBe("0.000");
  });

  it("rounds midpoints up", () => {
    expect(roundCoord(53.3375)).toBe("53.350");
  });

  it("always produces 3 decimal places", () => {
    expect(roundCoord(10)).toBe("10.000");
    expect(roundCoord(-0.012)).toBe("0.000"); // round(-0.48) = 0
  });
});

// ── mpsToBeaufort ────────────────────────────────────────────────────

describe("mpsToBeaufort", () => {
  it("returns 0 for calm (< 0.3 m/s)", () => {
    expect(mpsToBeaufort(0)).toBe(0);
    expect(mpsToBeaufort(0.2)).toBe(0);
  });

  it("returns correct Beaufort numbers at boundaries", () => {
    // Just below and at/above each threshold
    expect(mpsToBeaufort(0.3)).toBe(1); // >= 0.3 → 1
    expect(mpsToBeaufort(1.5)).toBe(1); // < 1.6 → 1
    expect(mpsToBeaufort(1.6)).toBe(2); // >= 1.6 → 2
    expect(mpsToBeaufort(3.3)).toBe(2); // < 3.4 → 2
    expect(mpsToBeaufort(3.4)).toBe(3); // >= 3.4 → 3
    expect(mpsToBeaufort(5.5)).toBe(4); // >= 5.5 → 4
    expect(mpsToBeaufort(8.0)).toBe(5); // >= 8.0 → 5
    expect(mpsToBeaufort(10.8)).toBe(6); // >= 10.8 → 6
    expect(mpsToBeaufort(13.9)).toBe(7); // >= 13.9 → 7
    expect(mpsToBeaufort(17.2)).toBe(8); // >= 17.2 → 8
    expect(mpsToBeaufort(20.8)).toBe(9); // >= 20.8 → 9
    expect(mpsToBeaufort(24.5)).toBe(10); // >= 24.5 → 10
    expect(mpsToBeaufort(28.5)).toBe(11); // >= 28.5 → 11
    expect(mpsToBeaufort(32.7)).toBe(12); // >= 32.7 → 12
  });

  it("returns 12 for hurricane force", () => {
    expect(mpsToBeaufort(40)).toBe(12);
    expect(mpsToBeaufort(100)).toBe(12);
  });
});

// ── convertMps ───────────────────────────────────────────────────────

describe("convertMps", () => {
  it("converts to beaufort", () => {
    expect(convertMps(7.2, "beaufort")).toBe(4); // 7.2 m/s → Beaufort 4
    expect(convertMps(11.3, "beaufort")).toBe(6); // 11.3 m/s → Beaufort 6
  });

  it("converts to knots", () => {
    // 7.2 * 1.94384 = 13.99 → 14
    expect(convertMps(7.2, "knots")).toBe(14);
    // 11.3 * 1.94384 = 21.97 → 22
    expect(convertMps(11.3, "knots")).toBe(22);
  });

  it("converts to mph", () => {
    // 7.2 * 2.23694 = 16.11 → 16
    expect(convertMps(7.2, "mph")).toBe(16);
  });

  it("converts to kmh", () => {
    // 7.2 * 3.6 = 25.92 → 26
    expect(convertMps(7.2, "kmh")).toBe(26);
  });

  it("converts to mps (rounds)", () => {
    expect(convertMps(7.2, "mps")).toBe(7);
    expect(convertMps(7.6, "mps")).toBe(8);
  });

  it("handles zero", () => {
    const units: WindUnit[] = ["beaufort", "knots", "mph", "kmh", "mps"];
    for (const u of units) {
      expect(convertMps(0, u)).toBe(0);
    }
  });

  it("always returns integers for all units with fractional m/s inputs", () => {
    const units: WindUnit[] = ["beaufort", "knots", "mph", "kmh", "mps"];
    const fractionalInputs = [0.1, 1.7, 3.33, 5.55, 7.89, 10.123, 15.6, 20.99, 33.3];
    for (const u of units) {
      for (const mps of fractionalInputs) {
        const result = convertMps(mps, u);
        expect(Number.isInteger(result), `convertMps(${mps}, "${u}") = ${result} is not integer`).toBe(true);
      }
    }
  });
});

// ── degToCardinal ────────────────────────────────────────────────────

describe("degToCardinal", () => {
  it("maps cardinal directions", () => {
    expect(degToCardinal(0)).toBe("N");
    expect(degToCardinal(90)).toBe("E");
    expect(degToCardinal(180)).toBe("S");
    expect(degToCardinal(270)).toBe("W");
  });

  it("maps intercardinal directions", () => {
    expect(degToCardinal(45)).toBe("NE");
    expect(degToCardinal(135)).toBe("SE");
    expect(degToCardinal(225)).toBe("SW");
    expect(degToCardinal(315)).toBe("NW");
  });

  it("handles boundary values (±22.5 per sector)", () => {
    expect(degToCardinal(22)).toBe("N"); // just under NE boundary
    expect(degToCardinal(23)).toBe("NE"); // just over
    expect(degToCardinal(67)).toBe("NE"); // just under E boundary
    expect(degToCardinal(68)).toBe("E"); // just over
  });

  it("wraps around 360", () => {
    expect(degToCardinal(360)).toBe("N");
    expect(degToCardinal(405)).toBe("NE");
  });

  it("handles negative degrees", () => {
    expect(degToCardinal(-90)).toBe("W");
    expect(degToCardinal(-45)).toBe("NW");
  });
});

// ── parseSlots ───────────────────────────────────────────────────────

describe("parseSlots", () => {
  it("defaults to [0] when null", () => {
    expect(parseSlots(null)).toEqual([0]);
  });

  it("defaults to [0] for empty string", () => {
    expect(parseSlots("")).toEqual([0]);
  });

  it("parses single slot", () => {
    expect(parseSlots("0")).toEqual([0]);
    expect(parseSlots("3")).toEqual([3]);
  });

  it("parses multiple slots", () => {
    expect(parseSlots("0,3,6")).toEqual([0, 3, 6]);
  });

  it("limits to 3 slots", () => {
    expect(parseSlots("0,1,2,3")).toEqual([0, 1, 2]);
  });

  it("filters invalid values", () => {
    expect(parseSlots("0,abc,3")).toEqual([0, 3]);
    expect(parseSlots("-1,0,8")).toEqual([0]); // -1 and 8 out of 0-7 range
  });

  it("handles whitespace", () => {
    expect(parseSlots(" 0 , 3 , 6 ")).toEqual([0, 3, 6]);
  });

  it("returns [0] when all values are invalid", () => {
    expect(parseSlots("abc")).toEqual([0]);
  });
});

// ── selectCurrentEntry ───────────────────────────────────────────────

describe("selectCurrentEntry", () => {
  const makeEntry = (isoTime: string): RawForecastEntry => ({
    time: isoTime,
    wind_mps: 5,
    wind_deg: 180,
    wind_beaufort: 3,
    gust_mps: 10,
  });

  beforeEach(() => {
    // Fix "now" to 2026-03-17T10:30:00Z
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-17T10:30:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns null for empty array", () => {
    expect(selectCurrentEntry([])).toBeNull();
  });

  it("picks the most recent entry at-or-before now", () => {
    const entries = [
      makeEntry("2026-03-17T09:00:00Z"),
      makeEntry("2026-03-17T10:00:00Z"),
      makeEntry("2026-03-17T11:00:00Z"),
    ];
    const result = selectCurrentEntry(entries);
    expect(result?.time).toBe("2026-03-17T10:00:00Z");
  });

  it("falls back to first entry when all are in the future", () => {
    const entries = [
      makeEntry("2026-03-17T11:00:00Z"),
      makeEntry("2026-03-17T12:00:00Z"),
    ];
    const result = selectCurrentEntry(entries);
    expect(result?.time).toBe("2026-03-17T11:00:00Z");
  });

  it("picks exact match at now", () => {
    const entries = [
      makeEntry("2026-03-17T10:30:00Z"),
      makeEntry("2026-03-17T11:00:00Z"),
    ];
    const result = selectCurrentEntry(entries);
    expect(result?.time).toBe("2026-03-17T10:30:00Z");
  });
});

// ── selectClosest ────────────────────────────────────────────────────

describe("selectClosest", () => {
  const makeEntry = (isoTime: string): RawForecastEntry => ({
    time: isoTime,
    wind_mps: 5,
    wind_deg: 180,
    wind_beaufort: 3,
    gust_mps: 10,
  });

  it("returns null for empty array", () => {
    expect(selectClosest([], 0)).toBeNull();
  });

  it("picks the entry closest to target", () => {
    const entries = [
      makeEntry("2026-03-17T10:00:00Z"),
      makeEntry("2026-03-17T11:00:00Z"),
      makeEntry("2026-03-17T12:00:00Z"),
    ];
    const target = new Date("2026-03-17T11:20:00Z").getTime();
    const result = selectClosest(entries, target);
    expect(result?.time).toBe("2026-03-17T11:00:00Z");
  });

  it("picks exact match", () => {
    const entries = [
      makeEntry("2026-03-17T10:00:00Z"),
      makeEntry("2026-03-17T13:00:00Z"),
    ];
    const target = new Date("2026-03-17T13:00:00Z").getTime();
    const result = selectClosest(entries, target);
    expect(result?.time).toBe("2026-03-17T13:00:00Z");
  });
});

// ── buildResponse ────────────────────────────────────────────────────

describe("buildResponse", () => {
  const makeRaw = (entries: RawForecastEntry[]): RawForecastResponse => ({
    model_run: "2026-03-17T06:00:00Z",
    forecasts: entries,
  });

  const makeEntry = (
    isoTime: string,
    windMps: number,
    gustMps: number,
    deg: number
  ): RawForecastEntry => ({
    time: isoTime,
    wind_mps: windMps,
    wind_deg: deg,
    wind_beaufort: 0,
    gust_mps: gustMps,
  });

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-03-17T10:30:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns empty forecasts for no entries", () => {
    const result = buildResponse(makeRaw([]), "beaufort", [0]);
    expect(result.forecasts).toEqual([]);
    expect(result.api_version).toBe("v1");
    expect(result.units).toBe("beaufort");
  });

  it("builds single-slot beaufort response", () => {
    const raw = makeRaw([
      makeEntry("2026-03-17T10:00:00Z", 7.2, 11.3, 195),
      makeEntry("2026-03-17T11:00:00Z", 8.0, 12.0, 200),
    ]);
    const result = buildResponse(raw, "beaufort", [0]);
    expect(result.forecasts).toHaveLength(1);
    expect(result.forecasts[0]).toEqual({
      time: "2026-03-17T10:00:00Z",
      wind_speed: 4, // 7.2 m/s → Beaufort 4
      gust_speed: 6, // 11.3 m/s → Beaufort 6
      wind_dir: "S", // 195° → S (180±22.5)
    });
  });

  it("builds 3-slot knots response with correct offsets", () => {
    const raw = makeRaw([
      makeEntry("2026-03-17T10:00:00Z", 6.0, 12.0, 180),
      makeEntry("2026-03-17T11:00:00Z", 7.0, 13.0, 190),
      makeEntry("2026-03-17T12:00:00Z", 8.0, 14.0, 200),
      makeEntry("2026-03-17T13:00:00Z", 9.0, 15.0, 225),
      makeEntry("2026-03-17T14:00:00Z", 5.0, 10.0, 270),
      makeEntry("2026-03-17T15:00:00Z", 4.0, 8.0, 315),
      makeEntry("2026-03-17T16:00:00Z", 3.0, 6.0, 0),
    ]);
    // slots=0,3,6 → current(10:00), 10:00+3h=13:00, 10:00+6h=16:00
    const result = buildResponse(raw, "knots", [0, 3, 6]);
    expect(result.forecasts).toHaveLength(3);

    // Slot 0: 10:00 — 6 m/s → 12 kn, 12 m/s → 23 kn, 180° → S
    expect(result.forecasts[0].time).toBe("2026-03-17T10:00:00Z");
    expect(result.forecasts[0].wind_speed).toBe(12);
    expect(result.forecasts[0].wind_dir).toBe("S");

    // Slot 1: 13:00 — 9 m/s → 17 kn, 225° → SW
    expect(result.forecasts[1].time).toBe("2026-03-17T13:00:00Z");
    expect(result.forecasts[1].wind_speed).toBe(17);
    expect(result.forecasts[1].wind_dir).toBe("SW");

    // Slot 2: 16:00 — 3 m/s → 6 kn, 0° → N
    expect(result.forecasts[2].time).toBe("2026-03-17T16:00:00Z");
    expect(result.forecasts[2].wind_speed).toBe(6);
    expect(result.forecasts[2].wind_dir).toBe("N");
  });

  it("builds 2-slot mph response", () => {
    const raw = makeRaw([
      makeEntry("2026-03-17T10:00:00Z", 6.0, 12.0, 90),
      makeEntry("2026-03-17T16:00:00Z", 10.0, 18.0, 45),
    ]);
    const result = buildResponse(raw, "mph", [0, 6]);
    expect(result.forecasts).toHaveLength(2);
    expect(result.forecasts[0].wind_dir).toBe("E");
    expect(result.forecasts[1].wind_dir).toBe("NE");
    // 6 * 2.23694 = 13.4 → 13
    expect(result.forecasts[0].wind_speed).toBe(13);
    // 10 * 2.23694 = 22.4 → 22
    expect(result.forecasts[1].wind_speed).toBe(22);
  });

  it("builds kmh response", () => {
    const raw = makeRaw([
      makeEntry("2026-03-17T10:00:00Z", 5.0, 10.0, 270),
    ]);
    const result = buildResponse(raw, "kmh", [0]);
    expect(result.forecasts[0].wind_speed).toBe(18); // 5 * 3.6 = 18
    expect(result.forecasts[0].gust_speed).toBe(36); // 10 * 3.6 = 36
    expect(result.forecasts[0].wind_dir).toBe("W");
  });

  it("builds mps response (rounded)", () => {
    const raw = makeRaw([
      makeEntry("2026-03-17T10:00:00Z", 5.7, 10.3, 135),
    ]);
    const result = buildResponse(raw, "mps", [0]);
    expect(result.forecasts[0].wind_speed).toBe(6); // round(5.7)
    expect(result.forecasts[0].gust_speed).toBe(10); // round(10.3)
    expect(result.forecasts[0].wind_dir).toBe("SE");
  });

  it("includes model_run in response", () => {
    const raw = makeRaw([
      makeEntry("2026-03-17T10:00:00Z", 5, 10, 0),
    ]);
    const result = buildResponse(raw, "beaufort", [0]);
    expect(result.model_run).toBe("2026-03-17T06:00:00Z");
  });
});
