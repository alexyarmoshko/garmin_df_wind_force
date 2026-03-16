# Execution Plan Review v1

Date: 2026-03-12
Reviewer: Codex

## Scope

This review covers the current repository state and the proposed execution plan in `docs/execution_plan.md`, cross-checked against `docs/REQUIREMENTS.md`, `README.md`, `AGENTS.md`, the local Garmin Connect IQ SDK 8.2.3 documentation and samples, and current Cloudflare Workers Wrangler documentation.

## Findings

### 1. High: invalid Wrangler route configuration in Milestone 2

`docs/execution_plan.md` uses `[routes]` for `wrangler.toml`:

- `docs/execution_plan.md:182`

Current Wrangler configuration uses `route`, `[route]`, or `routes = [...]`, not `[routes]`. If implemented as written, the Worker configuration will not be valid and Milestone 2 deployment will fail.

Recommended fix:

- Replace `[routes]` with either:
  - `[route]` plus `pattern` and `zone_name`, or
  - `routes = [{ pattern = "...", zone_name = "..." }]`

### 2. High: the fetch loop will poll `/model-status` too frequently

The plan states that `FetchManager.executeFetchCycle(info)` should call `fetchModelStatus()`:

- `docs/execution_plan.md:318`

The same plan also states that `compute()` initiates this flow and assumes roughly a one-second update cycle:

- `docs/execution_plan.md:337`

That means the watch will attempt a model-status request every compute cycle unless additional throttling is added. This conflicts with the requirements, which describe lower-frequency polling:

- `docs/REQUIREMENTS.md:159`

Risk:

- unnecessary battery use
- excessive phone/network activity
- avoidable load on the proxy
- harder-to-debug asynchronous behavior

Recommended fix:

- Add an explicit polling interval for `/model-status`, for example every 10 to 15 minutes.
- Keep distance/time-trigger evaluation local on the watch between model-status polls.

### 3. High: heading and bearing units are inconsistent in the look-ahead design

The look-ahead function is described as accepting `bearingDeg`:

- `docs/execution_plan.md:317`

The plan then says to use `info.currentHeading` directly:

- `docs/execution_plan.md:322`

In the local Connect IQ SDK docs, `Activity.Info.currentHeading` is in radians, and `Activity.Info.bearing` is also in radians. If implemented as written, the look-ahead points will be computed from the wrong angle units.

Risk:

- incorrect look-ahead cache locations
- degraded offline fallback behavior
- incorrect fetch spacing along route

Recommended fix:

- Standardize all internal navigation math to radians.
- Convert to degrees only for display, never for coordinate math.
- Update the function signature and milestone text to make the chosen unit explicit.

### 4. Medium: settings resource path is left ambiguous for a novice

Milestone 5 says to use `resources/settings.xml` or `resources/properties.xml` depending on SDK version:

- `docs/execution_plan.md:355`

This repository already fixes the SDK context to Garmin Connect IQ SDK 8.2.3, and the local SDK samples use `resources/properties.xml` for app properties and settings.

Risk:

- a novice may create the wrong file
- settings may not compile or may not be wired correctly

Recommended fix:

- Make the plan prescriptive and use `resources/properties.xml`.

### 5. Medium: the execution plan does not fully follow `~\.codex\PLANS.md`

The current plan includes the required major sections, but it misses two format requirements from `PLANS.md`:

- Progress entries should include timestamps.
- A revision note should be added at the bottom whenever the plan is revised.

Relevant plan section:

- `docs/execution_plan.md:14`

Risk:

- the plan is weaker as a living document
- progress tracking and handoff quality will degrade once implementation starts

Recommended fix:

- Add timestamps to each progress item.
- Append a short revision note at the bottom whenever the plan changes.

## Current Project State

The repository is documentation-first at the moment. It contains:

- `README.md`
- `docs/REQUIREMENTS.md`
- `docs/execution_plan.md`
- `docs/execution_plan_changelog.md`
- `docs/Marine-Beaufort-scale.png`
- `AGENTS.md`
- `CLAUDE.md`

The source layout described in `README.md` does not exist yet. There is currently no:

- `manifest.xml`
- `monkey.jungle`
- `source/`
- `resources/`
- `proxy/`

This is not a problem by itself, but it means the plan should be treated as a true greenfield execution plan and kept very precise.

## Additional Notes

- The current README describes a future project structure rather than the current checked-in structure. That is acceptable for now, but it should be updated once implementation begins so the README reflects reality.

## Recommended Next Revision of the Plan

The next revision of `docs/execution_plan.md` should, at minimum:

1. Fix the Wrangler route syntax.
2. Add a throttled polling strategy for `/model-status`.
3. Normalize heading and bearing math to radians throughout the watch-side design.
4. Replace the settings file ambiguity with a single prescribed file path.
5. Bring the living-document sections into compliance with `~\.codex\PLANS.md`.
