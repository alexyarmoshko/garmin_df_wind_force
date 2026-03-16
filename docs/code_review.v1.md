# Code Review v1

Date: 2026-03-12
Reviewer: Codex
Scope: Milestones 1 and 2 implementation currently present in the repository, with emphasis on the Garmin data field scaffold and the Cloudflare Worker proxy.

## Findings

### 1. High: `/forecast` drops the "current" forecast slot, so the watch cannot render the current + future layout promised by the product docs

In [proxy/src/met-eireann.ts](~/repos/garmin_df_wind_force/proxy/src/met-eireann.ts), the parser only keeps entries whose timestamp is greater than or equal to `Date.now()`:

- [proxy/src/met-eireann.ts:57](~/repos/garmin_df_wind_force/proxy/src/met-eireann.ts)
- [proxy/src/met-eireann.ts:71](~/repos/garmin_df_wind_force/proxy/src/met-eireann.ts)

That means a point-in-time forecast stamped at the start of the current hour is discarded as soon as the real clock moves past that hour boundary. The product contract, however, is explicitly "current + 3h + 6h", not "next hour + 3h + 6h":

- [README.md:17](~/repos/garmin_df_wind_force/README.md)
- [docs/REQUIREMENTS.md:49](~/repos/garmin_df_wind_force/docs/REQUIREMENTS.md)

The likely user-visible effect is that the first displayed slot will jump forward to the next forecast hour instead of representing the current conditions, especially after the top of the hour.

### 2. Medium: a new model run is cached under the old model-run key, which defeats the cache on the first request after a model update

In [proxy/src/index.ts](~/repos/garmin_df_wind_force/proxy/src/index.ts), `cacheKey` is computed before the fresh upstream fetch:

- [proxy/src/index.ts:61](~/repos/garmin_df_wind_force/proxy/src/index.ts)

If the upstream fetch discovers that a newer model run is available, the code updates `modelRun` but never recomputes `cacheKey` before storing the body:

- [proxy/src/index.ts:70](~/repos/garmin_df_wind_force/proxy/src/index.ts)
- [proxy/src/index.ts:76](~/repos/garmin_df_wind_force/proxy/src/index.ts)
- [proxy/src/index.ts:86](~/repos/garmin_df_wind_force/proxy/src/index.ts)

That writes a response containing the new `model_run` under a cache key built from the previous model run. The next request uses the updated `latest_model_run`, misses the cache, and refetches unnecessarily. This is mostly a correctness/performance bug in the cache layer, but it also makes cache behavior harder to reason about.

## Notes

I did not find a clear code defect in the Milestone 1 Garmin scaffold from static review. The data field code is still intentionally minimal and matches the proof-of-concept milestone.

## Verification Performed

- Read and reviewed:
  - `manifest.xml`
  - `monkey.jungle`
  - `source/WindForceApp.mc`
  - `source/WindForceView.mc`
  - `proxy/src/index.ts`
  - `proxy/src/met-eireann.ts`
  - `proxy/src/types.ts`
  - `proxy/wrangler.toml`
  - `proxy/package.json`
- Ran `npm run typecheck` in `proxy/`: passed
- No automated tests exist yet for the Worker parser/cache behavior
- I did not run a Connect IQ build or simulator session during this review
