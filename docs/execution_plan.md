# Wind Force Data Field - Execution Plan

This Execution Plan is a living document. The sections Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds. This document must be maintained in accordance with `~/.codex/PLANS.md`.

## Purpose / Big Picture

After this work is complete, a kayaker wearing a Garmin Instinct 2X Solar will be able to add a "Wind Force" data field to their Kayak activity screen. During a paddle, the field will display the current wind speed (in Beaufort or other units), gust speed, and wind direction (as a cardinal compass label), all derived from Met Eireann's HARMONIE weather model. Depending on the data field slot size chosen by the user, the display shows one, two, or three time slots separated by `•`, so the paddler can see how conditions are forecast to change over the next few hours.

The data flows from Met Eireann's XML API through a Cloudflare Worker proxy (which translates XML to compact JSON and caches results) to the watch via the paired phone's internet connection. When connectivity is lost, previously fetched data is displayed with a staleness indicator. Nearest-grid offline fallback is implemented now; look-ahead caching was deferred after the background-service rework and remains planned follow-up work.

To see it working: deploy the Cloudflare Worker, side-load the data field onto the watch (or run it in the Connect IQ simulator), start a Kayak activity with the Wind Force field visible, and observe wind data updating as the GPS position changes.

## Progress

- [x] (2026-03-12) Milestone 1: Project scaffolding and static data field proof-of-concept
- [x] (2026-03-12) Milestone 2: Cloudflare Worker proxy with Met Eireann XML-to-JSON translation
- [x] (2026-03-13) Milestone 3: Data field display engine (rendering, layouts, unit conversions)
- [x] (2026-03-13) Milestone 4: Communication layer and fetch strategy
- [x] (2026-03-15) Milestone 5: User settings and staleness handling
- [x] (2026-03-17) Milestone 6: Integration testing, optimisation, and deployment
- [x] (2026-03-12) Plan review v1: addressed all 5 findings (Wrangler syntax, model-status polling, radians, properties.xml, PLANS.md compliance)
- [x] (2026-03-18) Milestone 7: Immediate background fetch on first GPS fix and activity-completion cache pruning (addresses `docs/field_test.v1.md` and `docs/field_test.v2.md`)

## Surprises & Discoveries

- (2026-03-12) SDK 8.2.3 templates use SVG for launcher icons (not PNG). The `<bitmap>` resource element accepts SVG files with `dithering="none"`. Adopted SVG for the launcher icon.
- (2026-03-12) SDK 8.2.3 complex data field template places resources in subdirectories (`resources/strings/strings.xml`, `resources/drawables/drawables.xml`) rather than flat (`resources/strings.xml`). Adopted the subdirectory convention.
- (2026-03-12) The Instinct 2X device is confirmed at API level 3.4 (CIQ 3.4.3) per `compiler.json`. Our `minApiLevel="3.1.0"` is compatible.
- (2026-03-12) Developer key at `~/.ssh/developer_key` (DER format) works for signing builds.
- (2026-03-12) Met Eireann XML contains two types of `<time>` elements: point forecasts (from === to) with wind data, and period forecasts (from !== to) with precipitation/symbols. Parser filters on from === to.
- (2026-03-12) Met Eireann response includes multiple models (harmonie, ec_n1280_1hr, ec_n1280_3hr, ec_n1280_6hr). We extract the `termin` attribute only from the `harmonie` model entry.
- (2026-03-13) The Instinct 2X large data field slot is wide enough for the 3-slot layout with auto font sizing. Memory usage at 9.4/28.5kB after adding the display engine — still ~19kB headroom for the remaining milestones.
- (2026-03-13) Cardinal letters (N, NE, E, etc.) render correctly on the Instinct 2X fonts. Unicode arrow testing deferred — letters are compact and readable.
- (2026-03-13) Monkey C modules cannot use `method(:name)` for callbacks (no `self`). FetchManager must be a class, not a module, because `Communications.makeWebRequest()` requires a method reference callback. DisplayRenderer and StorageManager remain modules (no callbacks needed).
- (2026-03-13) Monkey C `const` float literals (e.g., `2.5`) are `Float`, not `Double`. When passing to functions expecting `Double`, must call `.toDouble()` explicitly.
- (2026-03-13) PRG file size after Milestone 4: 11.6 KB (release build). Still ~20 KB headroom within the 32 KB limit.
- (2026-03-14) **Connect IQ data fields cannot call `Communications.makeWebRequest()` directly.** The call silently does nothing — no HTTP traffic, no callback, no error. Data fields must use a background service (`System.ServiceDelegate`) registered via `Background.registerForTemporalEvent()`. This required a major architectural change from direct fetch in `compute()` to a background-service pattern.
- (2026-03-14) The `Positioning` permission is required in the manifest for `Activity.Info.currentLocation` to return non-null values, even for data fields.
- (2026-03-14) `Application.Storage` values set by the main process are not reliably readable by the background service process in the simulator. Slot count is now hardcoded to 3 (matching the Instinct 2X large data field) rather than passed via Storage.
- (2026-03-14) `Application.Properties` is used by the background service to read wind units and interval settings. This avoids relying on `Application.Storage` for settings propagation, but real-time sync between the foreground app and the background service must still be validated on a physical device during an active activity.
- (2026-03-14) Look-ahead point fetching was deferred from the Milestone 4 rework so the background-service architecture could be stabilised first. The current implementation fetches the current position only and relies on nearest cached grid-point fallback when offline.
- (2026-03-14) The background temporal event minimum interval is 5 minutes. In the simulator, background events must be triggered manually via Simulation > Trigger Background Event.

## Decision Log

- Decision: Target device ID is `instinct2x` (covers both Instinct 2X and Instinct 2X Solar).
  Rationale: The Connect IQ SDK uses the same device ID for the solar and non-solar variants. Confirmed in SDK device reference at `doc/docs/Device_Reference/instinct2x.html`.
  Date/Author: 2026-03-12

- Decision: Use `WatchUi.DataField` (not `SimpleDataField`) for the view class.
  Rationale: `SimpleDataField` only returns a single value for display. The wind force field needs a custom multi-segment layout with direction labels and multi-slot formatting. `WatchUi.DataField` provides `onLayout(dc)` and `onUpdate(dc)` for full drawing control.
  Date/Author: 2026-03-12

- Decision: Use TypeScript for the Cloudflare Worker.
  Rationale: User preference. TypeScript provides type safety and is well-supported by the Wrangler toolchain for Cloudflare Workers.
  Date/Author: 2026-03-12

- Decision: Host the proxy as a Cloudflare Worker under the existing kayakshaver.com domain.
  Rationale: User already has a Cloudflare account with this domain. The Worker can be deployed as a route or subdomain (e.g., `api.kayakshaver.com` or `kayakshaver.com/api/...`).
  Date/Author: 2026-03-12

- Decision: All internal coordinate and heading math uses radians; degrees only for display and proxy URL parameters.
  Rationale: `Activity.Info.currentHeading` and `Activity.Info.currentLocation` (via `Position.Location`) both use radians natively. Converting to degrees for internal math would introduce unnecessary conversions and risk unit-mismatch bugs. The proxy API expects degrees in query parameters, so conversion happens only at the HTTP call boundary. Confirmed in SDK docs at `doc/Toybox/Activity/Info.html`.
  Date/Author: 2026-03-12

- Decision: Remove `/v1/model-status` endpoint. Model run detection handled internally by `/v1/forecast`.
  Rationale: The watch never calls `/v1/model-status` — the background service only calls `/v1/forecast`, which internally resolves the current model run via KV cache. The separate endpoint added dead code and documentation overhead with no consumer. Removed in Milestone 6.
  Date/Author: 2026-03-17

- Decision: Move unit conversion, direction labels, Beaufort lookup, and slot selection from the watch to the proxy.
  Rationale: The Instinct 2X data field has a 32 KB memory limit. By performing unit conversion (Beaufort, knots, mph, km/h, m/s), Beaufort-scale lookup for gusts, cardinal direction labelling, and forecast interval selection on the proxy, the watch-side code becomes a thin display layer: `DisplayRenderer` only concatenates pre-computed strings with a `•` (bullet) separator between slots, and `WindData` stores display-ready values (`windSpeed`, `gustSpeed`, `windDir`). The `/v1/forecast` endpoint accepts `units` and `slots` query parameters and returns exactly the entries the watch needs to render, with all values pre-converted. When the user changes the wind unit or interval settings, the watch triggers a refetch with the new parameters rather than re-computing locally. This maximises memory savings on the watch at the cost of slightly more proxy logic and an extra network round-trip when settings change.
  Date/Author: 2026-03-13

- Decision: Use background service (`System.ServiceDelegate`) for all web requests instead of calling `makeWebRequest()` from `compute()`.
  Rationale: Connect IQ data fields cannot make direct HTTP requests — `Communications.makeWebRequest()` silently fails (no traffic, no callback). The background service pattern is mandatory: `Background.registerForTemporalEvent()` fires a `ServiceDelegate.onTemporalEvent()` every 5 minutes, which calls `makeWebRequest()` and returns data via `Background.exit()` → `AppBase.onBackgroundData()`. GPS position is persisted to `Application.Storage` by `compute()` so the background service can read it. This replaces the original FetchManager direct-fetch design, and removes the need for ForecastService module and LookAheadCallback class.
  Date/Author: 2026-03-14

- Decision: Schedule an immediate temporal event on first GPS fix instead of waiting for the next 5-minute polling interval.
  Rationale: Field testing (`docs/field_test.v1.md`) revealed that after starting an activity, the data field showed `---` for up to 5 minutes because GPS acquisition does not trigger a fetch. By re-registering the temporal event via `Background.registerForTemporalEvent()` with the earliest legal `Time.Moment` when GPS is first acquired, the background service fires as soon as Garmin allows. The 5-minute repeating schedule is then restored in `onBackgroundData()` by re-registering with `Duration(5 * 60)`. Alternative approaches (phone-app message trigger, pure polling) were considered and rejected: the phone-app approach requires a companion integration that is disproportionate to the problem, and pure polling already has the observed UX drawback.
  Date/Author: 2026-03-18

- Decision: Clear forecast cache on activity completion using dual hooks (`onActivityCompleted` + `onTimerReset`), not `AppBase.onStop()`.
  Rationale: Field testing (`docs/field_test.v2.md`) revealed that cached forecasts from a previous activity survive into the next activity, causing stale data to display. `AppBase.onStop()` was rejected because it fires on any app exit (memory pressure, watchface change), not just activity completion — tying cache pruning to generic shutdown would clear data in cases unrelated to session boundaries. `ServiceDelegate.onActivityCompleted()` is the semantically correct activity-completion hook. `DataField.onTimerReset()` is added as a foreground safety net in case the background event is delayed or unavailable on certain device/activity flows. Both hooks call the same cleanup logic; if one fires before the other, the second is a harmless no-op.
  Date/Author: 2026-03-18

- Decision: All wind and gust speed values are rounded to integers end-to-end — proxy returns integers, watch stores and displays integers.
  Rationale: Smaller watch displays (e.g., narrow data field slots on future devices) cannot accommodate decimal digits, and integer precision is sufficient for paddling water activities. The proxy's `convertMps()` applies `Math.round()` for all unit conversions (knots, mph, km/h, m/s) and `mpsToBeaufort()` returns an integer by table lookup. The watch-side `WindData` type stores values as Monkey C `Number` (integer). This guarantee is enforced by a dedicated proxy unit test that verifies `Number.isInteger()` across all units with fractional m/s inputs.
  Date/Author: 2026-03-18

## Outcomes & Retrospective

**Milestone 7 completed 2026-03-18.** All 7 milestones delivered. Milestone 7 addressed two field-test findings: immediate background fetch on first GPS fix and activity-completion cache pruning.

**What went well:**

- The proxy-first architecture decision (moving unit conversion, slot selection, and direction labelling to the Cloudflare Worker) paid off handsomely. The watch-side code is a thin display layer at 13,260 bytes — 40.5% of the 32 KB limit, leaving ample headroom for future features.
- The background service rework (Milestone 4, day 3) was the single largest surprise. Discovering that data fields cannot call `makeWebRequest()` directly required a significant architectural change, but the resulting design is cleaner: a simple 5-minute temporal event with GPS persisted via `Application.Storage`.
- Iterative code reviews (13 rounds) caught subtle bugs early: cross-cycle callback corruption, settings race conditions, staleness indicator accuracy, and slot selection edge cases.

**What was harder than expected:**

- `Application.Storage` synchronisation between the main process and background service is unreliable in the simulator. This forced hardcoding the slot count to 3 and using `Application.Properties` for settings instead of Storage.
- The strict type checker (`-l 3`) is aggressive with framework types like `Dictionary` vs `PersistableType`. Several methods required `(:typecheck(false))` annotations where the code is correct at runtime but the type system cannot verify it.

**Deferred work:**

- Look-ahead caching (fetching forecast data for points ahead of the current position) was deferred after the background-service rework. The current implementation fetches only the current position and relies on nearest-grid-point fallback.
- Connect IQ Store publication (requires Garmin developer account approval and store listing assets).

**Post-release work:**

- Milestone 7 was added after field testing revealed two UX issues: (1) the data field showed `---` for up to 5 minutes after GPS lock because GPS acquisition does not trigger a fetch (`docs/field_test.v1.md`), and (2) cached forecasts from a previous activity survive into the next activity, displaying stale data (`docs/field_test.v2.md`).

## Context and Orientation

The repository contains a working Connect IQ data field and a deployed Cloudflare Worker proxy:

    garmin_df_wind_force/
      AGENTS.md              -- Agent instructions for the Garmin Connect IQ SDK location
      CLAUDE.md              -- References AGENTS.md
      manifest.xml           -- Connect IQ app manifest (instinct2, instinct2x)
      monkey.jungle          -- Build configuration
      source/                -- Monkey C source files (app, view, service delegate, etc.)
      resources/             -- Strings, settings, images
      proxy/                 -- Cloudflare Worker (TypeScript)
        src/                 -- Worker source code
        wrangler.toml        -- Cloudflare deployment config
      docs/                  -- Requirements, execution plan, changelog, reviews

Two distinct codebases exist:

1. The Connect IQ data field (Monkey C), which lives in the repository root following standard Connect IQ project layout.
2. The Cloudflare Worker proxy (TypeScript), which lives in a `proxy/` subdirectory with its own `package.json` and `wrangler.toml`.

**Key terms used in this plan:**

- **Data field**: A Connect IQ application type that occupies a slot on an activity screen. It receives periodic callbacks with activity data (GPS, speed, heart rate, etc.) and renders a value or graphic in its allocated screen area.
- **Monkey C**: Garmin's programming language for Connect IQ apps. It has Java-like syntax with optional type annotations, runs on a proprietary VM on the watch.
- **Cloudflare Worker**: A serverless function that runs on Cloudflare's edge network. It handles HTTP requests and can use Cloudflare KV (a key-value store) for caching.
- **KV (Key-Value store)**: Cloudflare's distributed key-value storage. Used here to cache parsed forecast JSON so the Worker does not re-fetch from Met Eireann on every request.
- **HARMONIE-AROME**: The numerical weather prediction model run by Met Eireann. It covers Ireland, the UK, and a small area of northern France. Grid resolution is approximately 2.5 km. It runs every 6 hours (00, 06, 12, 18 UTC) and produces hourly forecasts out to 90 hours.
- **Beaufort scale**: A scale from 0 to 12 that categorises wind speed by its observed effects at sea. See `docs/Marine-Beaufort-scale.png` for the full table.
- **Slot separator**: Adjacent time slots on the display are separated by a `•` (bullet) character. This is a pure formatting separator with no directional meaning.
- **makeWebRequest()**: The Connect IQ API method `Communications.makeWebRequest()` that sends an HTTP request from the watch. The request is actually routed through the paired phone's internet connection via Bluetooth and the Garmin Connect Mobile app.
- **Application.Storage**: A persistent key-value store on the watch that survives app restarts. Used to cache forecast data between fetch cycles and across activity sessions.

**Development environment:**

- IDE: Visual Studio Code with the Monkey C / Connect IQ extension
- Connect IQ SDK: version 8.2.3, located at `~\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21\`
- SDK samples: `<SDK_PATH>\samples\` and `~\repos\garmin-connectiq-apps\`
- Target devices: Instinct 2X / 2X Solar (device ID: `instinct2x`), Instinct 2 (device ID: `instinct2`)
- Display: 176 x 176 pixels, monochrome (2 colours: black and white), semi-octagon shape, no touch screen
- Data field memory limit: 32,768 bytes (32 KB) -- this is tight and requires lean code
- Cloudflare tooling: Wrangler CLI for Worker development and deployment

## Plan of Work

### Milestone 1: Project Scaffolding and Static Data Field Proof-of-Concept

This milestone establishes the Connect IQ project structure and proves that a data field can be built, run in the simulator, and display static text on a supported device screen. At the end, a developer can run the simulator, start a Kayak activity, and see "3(4)N" rendered in the data field slot.

**What to create:**

The Connect IQ project follows a standard layout rooted in the repository directory. All paths below are relative to the repository root (`garmin_df_wind_force/`).

`manifest.xml` -- the application manifest. It declares the app as type `datafield`, targets the `instinct2x` and `instinct2` devices, and requests the `Communications` permission (needed later for HTTP requests). The entry class points to the main application class. A unique UUID must be generated for the `id` attribute.

    <?xml version="1.0"?>
    <iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" version="3">
        <iq:application
            entry="WindForceApp"
            id="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
            launcherIcon="@Drawables.LauncherIcon"
            minApiLevel="3.1.0"
            name="@Strings.AppName"
            type="datafield">
            <iq:products>
                <iq:product id="instinct2x"/>
            </iq:products>
            <iq:permissions>
                <iq:uses-permission id="Communications"/>
            </iq:permissions>
            <iq:languages>
                <iq:language>eng</iq:language>
            </iq:languages>
        </iq:application>
    </iq:manifest>

`monkey.jungle` -- build configuration. Minimal initially:

    project.manifest = manifest.xml

`source/WindForceApp.mc` -- the application class. Extends `Application.AppBase`, returns the data field view from `getInitialView()`, and provides a hook for `onSettingsChanged()` (used in Milestone 5).

`source/WindForceView.mc` -- the data field view. Extends `WatchUi.DataField`. Implements `compute(info)` to extract GPS position from `Activity.Info`, and `onUpdate(dc)` to render text on the display context. For this milestone, `onUpdate` draws the static string "3(4)N" centred on the screen.

`resources/strings.xml` -- defines string resources:

- `AppName`: "Wind Force"

`resources/drawables.xml` -- declares the launcher icon bitmap:

- `LauncherIcon`: references `images/icon.png`

`resources/images/icon.png` -- a 62x62 pixel monochrome PNG. Can be a simple placeholder (e.g., a wind arrow graphic or just the letter "W").

**How to validate:**

Open the project in VS Code with the Connect IQ extension. Build for a supported device (e.g. `instinct2x`). Launch the Connect IQ simulator. Select the device in the simulator. Start a Kayak activity simulation. The Wind Force data field should appear in one of the data field slots displaying "3(4)N". If the text renders correctly and the simulator does not report errors, Milestone 1 is complete.

Build command (from the VS Code Command Palette): `Monkey C: Build for Device` selecting `instinct2x`. Alternatively, from the terminal:

    cd ~\repos\garmin_df_wind_force
    "~\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21\bin\monkeyc" -d instinct2x -f monkey.jungle -o bin\WindForce.prg -y "path\to\developer_key.der"

Then in the simulator, load `bin\WindForce.prg` and start a Kayak activity.

### Milestone 2: Cloudflare Worker Proxy

This milestone builds the proxy backend that sits between the watch and Met Eireann. At the end, a developer can call the deployed Worker endpoint with a latitude/longitude and receive a compact JSON response containing hourly wind forecast data.

**Project structure** (all inside `proxy/` directory):

    proxy/
      package.json
      tsconfig.json
      wrangler.toml
      src/
        index.ts          -- Worker entry point, request routing
        met-eireann.ts    -- Fetches and parses Met Eireann XML responses
        types.ts          -- TypeScript type definitions
      test/
        index.test.ts     -- Tests for the Worker logic

**wrangler.toml configuration:**

    name = "wind-force-proxy"
    main = "src/index.ts"
    compatibility_date = "2024-01-01"

    [[kv_namespaces]]
    binding = "FORECAST_CACHE"
    id = "<KV_NAMESPACE_ID>"

    [[routes]]
    pattern = "api.kayakshaver.com/*"
    zone_name = "kayakshaver.com"

The KV namespace ID is obtained by running `npx wrangler kv namespace create FORECAST_CACHE` from the `proxy/` directory.

#### Endpoint: GET /v1/forecast

URL: `/v1/forecast?lat={lat}&lon={lon}&units={units}&slots={slots}`

Query parameters:

- `lat` (required): Latitude in degrees (-90 to 90).
- `lon` (required): Longitude in degrees (-180 to 180).
- `units` (optional): Wind speed unit for the response. One of `beaufort` (default), `knots`, `mph`, `kmh`, `mps`. If omitted or unrecognised, defaults to `beaufort`.
- `slots` (optional): Comma-separated hour offsets for the time slots to return (e.g., `0,3,6`). Each value is an integer 0-7 representing hours from now. The proxy selects the forecast entry whose time is closest to `now + offset` hours. If omitted, defaults to `0` (current hour only). Maximum 3 values.

Processing steps:

1. Parse and validate `lat`, `lon`, `units`, and `slots` query parameters.
2. Round both coordinates to the nearest 0.025 degrees. This aligns with the HARMONIE model's approximately 2.5 km grid and maximises cache hits. Rounding formula: `Math.round(value / 0.025) * 0.025`, then format to 3 decimal places.
3. Construct a KV cache key for the raw forecast: `forecast_{rounded_lat}_{rounded_lon}_{model_run}` where `model_run` is the latest known model run timestamp (see below). The raw forecast is cached in its original m/s + degrees form; unit conversion and slot selection are applied on the fly before returning the response.
4. Check KV for an existing cached raw entry. If found, select the requested slots, convert to the requested units, and return.
5. If not cached, fetch from Met Eireann: `http://openaccess.pf.api.met.ie/metno-wdb2ts/locationforecast?lat={rounded_lat};long={rounded_lon}`
6. Parse the XML response. Met Eireann returns XML in the `metno-wdb2ts` format. Extract `windSpeed` (mps and beaufort), `windDirection` (deg and name), and `windGust` (mps) for each hourly time step from now out to 7 hours ahead.
7. Store the raw forecast in KV with a TTL of 25,200 seconds (7 hours).
8. Select the forecast entries matching the requested `slots` offsets. For each offset, pick the entry whose time is closest to `now + offset` hours. Convert to the requested units and build the JSON response:

        {
          "api_version": "v1",
          "model_run": "2026-03-12T06:00:00Z",
          "units": "beaufort",
          "forecasts": [
            {
              "time": "2026-03-12T10:00:00Z",
              "wind_speed": 4,
              "gust_speed": 6,
              "wind_dir": "SSW"
            },
            {
              "time": "2026-03-12T13:00:00Z",
              "wind_speed": 5,
              "gust_speed": 7,
              "wind_dir": "SW"
            },
            {
              "time": "2026-03-12T16:00:00Z",
              "wind_speed": 3,
              "gust_speed": 5,
              "wind_dir": "W"
            }
          ]
        }

    Response field details:
    - `api_version`: the API version string (e.g., `"v1"`).
    - `units`: echoes the unit used for `wind_speed` and `gust_speed` (e.g., `"beaufort"`, `"knots"`).
    - `wind_speed`: wind speed as a rounded integer in the requested unit.
    - `gust_speed`: gust speed as a rounded integer in the requested unit.
    - `wind_dir`: cardinal/intercardinal direction label (one of N, NE, E, SE, S, SW, W, NW). Computed from the raw degree value using 8 sectors of 45 degrees each.

    The `forecasts` array contains exactly the number of entries requested via `slots` (1 to 3), in the same order as the offsets. The watch renders these directly with a `•` (bullet) separator between adjacent slots, without any selection or conversion logic.

    Unit conversion formulas (from raw m/s):
    - `beaufort`: standard Beaufort scale lookup (same breakpoints as the current `mpsToBeaufort` table).
    - `knots`: `round(mps * 1.94384)`
    - `mph`: `round(mps * 2.23694)`
    - `kmh`: `round(mps * 3.6)`
    - `mps`: `round(mps)`

9. Return the JSON response.

**XML Parsing**: Cloudflare Workers do not have a built-in DOM XML parser. Use a lightweight streaming/regex-based approach to extract the needed fields from the Met Eireann XML. The XML structure uses `<time>` elements with `from` and `to` attributes, containing `<location>` elements with child elements like `<windSpeed mps="7.2" beaufort="4" .../>` and `<windDirection deg="195" name="SSW"/>` and `<windGust mps="11.3"/>`. A simple parser that extracts these attribute values using regex or a small XML parser library (such as `fast-xml-parser`, which works in Workers) is sufficient.

**How to validate:**

After deploying with `npm run deploy`:

    curl "https://api.kayakshaver.com/v1/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0,3,6"

Expected: a JSON object with `api_version` (`"v1"`), `model_run`, `units` (`"beaufort"`), and `forecasts` array with exactly 3 entries. Each entry has `time`, `wind_speed` (integer), `gust_speed` (integer), and `wind_dir` (cardinal label string).

    curl "https://api.kayakshaver.com/v1/forecast?lat=53.35&lon=-6.26&units=knots&slots=0"

Expected: same structure but `units` is `"knots"`, speed values are in knots, and `forecasts` has exactly 1 entry.

For local development before deploying:

    cd proxy
    npm install
    npm run dev

Then use `http://localhost:8787/v1/forecast?lat=53.35&lon=-6.26` to test locally.

### Milestone 3: Data Field Display Engine

This milestone implements the rendering logic that turns wind data into the compact text display shown on the watch. At the end, the data field can take a set of wind forecast entries and render the correct layout string (e.g., "3/4NE" or "3/4NE<5/6S") depending on the data field slot size allocated by the user's activity screen configuration.

**Display rendering overview:**

The Instinct 2X screen is 176x176 monochrome pixels. Data field slots come in various sizes depending on the activity screen layout the user selects. The `onLayout(dc)` callback receives a drawing context (`dc`) whose `getWidth()` and `getHeight()` reveal the allocated area. The rendering engine must adapt to the available width.

**Layout selection logic:**

The number of time slots displayed depends on the width available:

- Narrow field (width < 90px): 1-slot layout: `W/GD` where W=speed, G=gust, D=direction label
- Medium field (90px <= width < 150px): 2-slot layout: `W1/G1D1<W2/G2D2`
- Wide field (width >= 150px): 3-slot layout: `W1/G1D1<W2/G2D2<W3/G3D3`

These thresholds should be constants that can be tuned after on-device testing.

**Files to create/modify:**

`source/WindForceView.mc` -- update `onUpdate(dc)` to call the rendering engine rather than drawing static text.

`source/DisplayRenderer.mc` -- a module containing the rendering logic. Because unit conversion, Beaufort lookup, direction labelling, and slot selection are all performed by the proxy, this module is a thin formatter that concatenates pre-computed values:

- `function renderWindSlot(data)` returns a string like "3/4NE" for one time slot. It reads the pre-converted `windSpeed`, `gustSpeed`, and `windDir` directly from the `WindData` object — no conversion needed.
- `function formatLayout(forecasts, fetchTimestamp, hasPosition, slots)` concatenates the forecast entries into the final display string. A `•` (bullet) separator is inserted between consecutive slots. When no forecast data is available, it builds a slot-aware placeholder (`-/-•-/-•-/-` for 3 slots) using the `slots` parameter. No `units` parameter is needed since values are already converted. No interval selection logic is needed since the proxy performs it.
- `function slotCount(width)` determines 1/2/3-slot layout from the field width. The current implementation uses this only for display truncation; the background service still requests 3 slots because cross-process slot-count sync is unresolved.
- **Removed from watch**: `convertSpeed()`, `mpsToBeaufort()`, `directionLabel()`, `veerBackSymbol()` — all handled by the proxy or no longer applicable.

`source/WindData.mc` -- a simple data class to hold pre-converted, display-ready forecast data received from the proxy:

    class WindData {
        var time as String;
        var windSpeed as Number;   // pre-converted integer (Beaufort, knots, etc.)
        var gustSpeed as Number;   // pre-converted integer in same unit
        var windDir as String;     // cardinal label from proxy (e.g., "NE", "SW")

        function initialize(time, windSpeed, gustSpeed, windDir) { ... }
    }

**Font selection:** On the 176x176 monochrome screen, `Graphics.FONT_MEDIUM` or `Graphics.FONT_SMALL` is appropriate for the data field text. The font must be small enough that a 3-slot layout fits within the widest field. Test in the simulator to determine the right font. Use `dc.getTextWidthArea(text, font)` to measure text width and select the largest font that fits.

**How to validate:**

In the simulator, configure a Kayak activity with different data field layouts (single field, 2-field, 3-field). The Wind Force field should show the appropriate number of slots. For this milestone, hardcode sample wind data using the new pre-converted format (e.g., windSpeed=3, gustSpeed=4, windDir="NE"; windSpeed=5, gustSpeed=6, windDir="S"). The display should render "3/4NE<5/6S" or similar depending on slot count.

### Milestone 4: Communication Layer and Fetch Strategy

This milestone connects the data field to the Cloudflare Worker proxy. A major discovery during implementation was that Connect IQ data fields cannot use `Communications.makeWebRequest()` directly. This required a full architectural pivot to a background service model, which is what this milestone now implements.

At the end, the data field uses a background service to fetch real wind data from the proxy based on the watch's GPS position and displays live forecast information. The current implementation fetches only the current position. Look-ahead fetches were explicitly deferred during the rework and are no longer part of Milestone 4.

**Files to create/modify:**

`source/WindForceServiceDelegate.mc` -- a new `System.ServiceDelegate` that runs in the background.
- Implements `onTemporalEvent()`, which is triggered by the system approximately every 5 minutes.
- Reads the last known GPS position, which the main app persists to `Application.Storage`.
- Calls `Communications.makeWebRequest()` to `GET /v1/forecast`, passing the appropriate `units` and `slots` parameters.
- On receiving a successful response, it passes the data payload back to the main application using `Background.exit()`.

`source/WindForceApp.mc` -- updated to manage the background service.
- Implements `getServiceDelegate()` to return an instance of `WindForceServiceDelegate`.
- Implements `onBackgroundData(data)` to receive the forecast payload from the service, stamp it with a per-forecast fetch timestamp, and call `StorageManager.storeForecast()` to persist the data.
- In `getInitialView()`, it calls `Background.registerForTemporalEvent()` to start the 5-minute background timer.

`source/FetchManager.mc` -- simplified to be a position tracker for the background service.
- The `executeFetchCycle()` method is replaced by a simpler `updatePosition(info)` method.
- `updatePosition()` is called from `compute()` and its only job is to persist the current `lat` and `lon` to `Application.Storage` so the background service can access it.
- All fetch trigger logic (distance, time, model-run) is removed from this module, as the only trigger is now the 5-minute temporal event. Look-ahead point calculation is deferred.

`source/WindForceServiceDelegate.mc` currently builds a 3-slot request string internally.
- This is a deliberate temporary compromise because passing slot count through `Application.Storage` proved unreliable in the simulator.
- Wind units and forecast intervals are read directly from `Application.Properties`.
- Physical-device validation is required to confirm that in-activity settings changes are visible to the background process without restarting the activity.

`source/StorageManager.mc` -- wraps `Application.Storage` for forecast data persistence:

- `function storeForecast(roundedLat, roundedLon, data)` stores a forecast JSON dictionary keyed by `"fc_{lat}_{lon}"`.
- `function loadForecast(roundedLat, roundedLon)` retrieves a cached forecast.
- `function loadNearestForecast(lat, lon)` scans stored keys to find the nearest cached grid point within 2.5 km.
- `function pruneStorage()` removes old entries, keeping only the 5 most recent to stay within storage limits.

`source/WindForceView.mc` -- update `compute(info)` to:

1. Call `FetchManager.updatePosition(info)` to persist the current location for the background service.
2. In `onUpdate(dc)`, read the forecast for the current position from `StorageManager` (which is populated by `onBackgroundData`) and pass it to `DisplayRenderer`.

`manifest.xml` -- updated to include the `Background` and `Positioning` permissions.

**How to validate:**

In the simulator, configure GPS simulation to follow a route. Start a Kayak activity. The data field should:

1. Show "NO GPS" or "?" initially.
2. Manually trigger a background event via the simulator menu (`Simulation > Trigger Background Event`).
3. After the event, the display should update with real wind data from the proxy.
4. Confirm that the app continues displaying the nearest cached forecast with a staleness indicator when connectivity is lost.

Check the simulator's console output for HTTP request/response logging.

### Milestone 5: User Settings and Staleness Handling

This milestone adds the configurable settings (wind units, forecast intervals) and the staleness indicator. At the end, the user can configure the data field via Garmin Connect Mobile or Garmin Express, and stale data is clearly indicated on screen.

**Settings to implement:**

`resources/properties.xml` -- declares both the default property values and the settings UI. In Connect IQ SDK 8.2.3, properties and settings are defined together in `resources/properties.xml`. The file contains a `<properties>` block for defaults and a `<settings>` block for the Garmin Connect Mobile / Garmin Express configuration UI:

    <properties>
        <property id="windUnits" type="number">0</property>
        <property id="forecastInterval1" type="number">3</property>
        <property id="forecastInterval2" type="number">6</property>
    </properties>

    <settings>
        <setting propertyKey="@Properties.windUnits" title="@Strings.WindUnitsTitle">
            <settingConfig type="list">
                <listEntry value="0">@Strings.Beaufort</listEntry>
                <listEntry value="1">@Strings.Knots</listEntry>
                <listEntry value="2">@Strings.Mph</listEntry>
                <listEntry value="3">@Strings.Kmh</listEntry>
                <listEntry value="4">@Strings.Ms</listEntry>
            </settingConfig>
        </setting>
        <setting propertyKey="@Properties.forecastInterval1" title="@Strings.Interval1Title">
            <settingConfig type="list">
                <listEntry value="1">1h</listEntry>
                <listEntry value="2">2h</listEntry>
                <listEntry value="3">3h</listEntry>
                <listEntry value="4">4h</listEntry>
                <listEntry value="5">5h</listEntry>
                <listEntry value="6">6h</listEntry>
            </settingConfig>
        </setting>
        <setting propertyKey="@Properties.forecastInterval2" title="@Strings.Interval2Title">
            <settingConfig type="list">
                <listEntry value="1">1h</listEntry>
                <listEntry value="2">2h</listEntry>
                <listEntry value="3">3h</listEntry>
                <listEntry value="4">4h</listEntry>
                <listEntry value="5">5h</listEntry>
                <listEntry value="6">6h</listEntry>
            </settingConfig>
        </setting>
    </settings>

`resources/strings.xml` -- add the setting label strings (WindUnitsTitle, Interval1Title, Interval2Title, Beaufort, Knots, Mph, Kmh, Ms).

`source/WindForceServiceDelegate.mc` -- continues to own settings-to-request mapping:

- `getUnitsString()` reads `Application.Properties.getValue("windUnits")` and maps the numeric property to the proxy `units` query parameter (`"beaufort"`, `"knots"`, `"mph"`, `"kmh"`, `"mps"`).
- `getInterval(which)` reads `forecastInterval1` / `forecastInterval2` from `Application.Properties`.
- `getSlotsString()` clamps interval 2 to be greater than interval 1 and builds the proxy `slots` string.
- This keeps settings logic in the background service and avoids an extra watch-side `SettingsManager` layer.

`source/WindForceApp.mc` -- `onSettingsChanged()` validates the interval pair (correcting invalid values back to `Application.Properties`), clears all cached forecasts via `StorageManager.clearAllForecasts()`, and requests a display update. The display shows the no-forecast placeholder (`-/-•-/-•-/-`) until the next background temporal event fetches new data using the updated settings. `onBackgroundData()` validates each response against the current `Application.Properties` values (units and slots strings) and discards responses fetched under stale settings.

- A required validation step for this milestone is confirming on-device that `Application.Properties` changes made during an active activity are visible to the background service on the next temporal event.
- If that validation fails, the mitigation options are: mirror settings into `Application.Storage` despite simulator limitations, require activity restart as a temporary limitation, or revisit the service/process communication design.

**Staleness indicator:**

In `source/DisplayRenderer.mc`, `formatLayout()` accepts a per-forecast `fetchTimestamp`. If `Time.now().value() - fetchTimestamp > 1800` (30 minutes), prefix the display string with `*`. The staleness threshold constant (1800 seconds) is defined in one place. Note: `formatLayout()` needs neither a `units` parameter nor interval selection logic - the proxy returns exactly the display-ready entries with pre-converted values. Adjacent time slots are separated by a `•` (bullet) character.

**Unavailable data display:**

Current implementation status:

- When no GPS fix is available, the field displays `NO GPS`.
- When GPS is available but no forecast is cached for the current or nearest grid point, the field displays a slot-aware placeholder: `-/-` (1 slot), `-/-•-/-` (2 slots), or `-/-•-/-•-/-` (3 slots). The count matches the display width and reduces dynamically like live data.

**Forecast interval mapping:**

The forecast intervals (e.g., 3h, 6h) determine which entries the proxy returns. `WindForceServiceDelegate` builds a `slots` string from the interval settings (currently hardcoded to 3 displayed slots because cross-process slot-count sync remains unresolved in the simulator) and passes it to the proxy. The proxy anchors slot 0 to the most recent forecast at-or-before now, then offsets later slots from that base time. The watch receives exactly the entries it needs to display - no interval mapping logic on the watch side.

**How to validate:**

1. In the simulator or on device, change wind units from Beaufort to Knots. The currently displayed data may remain visible until the next background temporal event; after that event, the field should update to show knot values instead of Beaufort numbers. The `units` field in the proxy response should reflect `"knots"`.
2. Change forecast intervals and verify the correct future time slots are shown after the next background event.
3. Set forecast interval 1 to 6 and verify that the third slot is suppressed (only 2 slots shown), since no valid later interval exists.
4. To test staleness: in the simulator, disconnect the simulated phone connection, wait, and observe the staleness indicator appearing after 30 minutes (or temporarily lower the threshold for testing).
5. On a physical device, verify that `Application.Properties` changes made during an active activity are visible to the background service on the next temporal event. Record the result explicitly, because this is currently an architectural risk rather than a confirmed behaviour.
6. Verify that changing units while offline does not crash - cached forecasts are cleared immediately and the display shows the no-forecast placeholder until connectivity is restored and a refetch succeeds with the new settings.

### Milestone 6: Integration Testing, Optimisation, and Deployment

This milestone is the final integration pass. At the end, the data field is ready for side-loading onto a physical device (Instinct 2X Solar or Instinct 2) for real-world testing on the water.

**Memory optimisation (critical):**

The Instinct 2X data field memory limit is 32,768 bytes (32 KB). This is extremely tight. During this milestone:

1. Build the project and check the memory usage reported by the compiler. The Connect IQ compiler outputs memory statistics.
2. If memory exceeds the limit, apply these optimisations in order:
   - Remove unused imports and dead code.
   - Replace class instances with module-level functions where possible (classes have overhead).
   - Reduce string literals by shortening or reusing them.
   - Use integer arithmetic instead of floating-point where possible.
   - Simplify the Haversine/equirectangular distance calculation.
   - Reduce the number of stored forecast entries in `Application.Storage`.
   - Consider inlining small helper functions.
3. Re-test after each optimisation to ensure behaviour is preserved.

**End-to-end testing checklist:**

- Start a simulated Kayak activity with GPS playback. Verify data fetches and display updates.
- Test all 3 layout sizes (1-slot, 2-slot, 3-slot) by configuring different activity screen layouts.
- Test all 5 wind unit options and verify conversions are correct against the Beaufort scale reference image.
- Test with no GPS fix (indoor start): display should show `NO GPS` until GPS is acquired.
- Test connectivity loss: disconnect simulated phone, verify staleness indicator and cached data display.
- Look-ahead point usage is deferred: do not mark this as covered by Milestone 4. Reintroduce this checklist item only when the deferred look-ahead milestone is implemented.
- Test that periodic background refreshes pick up a new model run automatically on the next successful `/v1/forecast` fetch.
- Test on-device that settings changes propagate to the background service during an active activity.
- Verify `Application.Storage` persistence: start an activity, stop it, start a new one, and verify old data is available as fallback.

**On-device deployment:**

1. Build a release PRG file: use `Monkey C: Export Project` in VS Code or run the compiler with the `-r` (release) flag.
2. Connect the Instinct 2/Instinct 2X Solar via USB.
3. Copy the `.prg` file to the watch's `GARMIN/APPS/` directory.
4. Disconnect the watch. The data field should appear in the data field picker for Kayak activities.
5. Pair the watch with a phone running Garmin Connect Mobile. Verify that settings are configurable from the phone.

**Cloudflare Worker production deployment:**

1. Run `npm run deploy` from the `proxy/` directory.
2. Verify the endpoints are accessible from the public internet.
3. Test the Worker responds correctly with the curl commands from Milestone 2.
4. Monitor Worker analytics in the Cloudflare dashboard for error rates and request counts.

**How to validate:**

The complete system is validated by performing an actual kayak paddle (or a walk/drive as a substitute) with a supported device (Instinct 2X Solar or Instinct 2) showing the Wind Force data field. The display should update with real Met Eireann wind data as the background service refreshes. Changing settings from the phone should take effect on the next background temporal event, subject to the on-device `Application.Properties` propagation validation described above.

### Milestone 7: Immediate Background Fetch on First GPS Fix and Activity-Completion Cache Pruning

This milestone addresses two field-test findings. The first, documented in `docs/field_test.v1.md`, is that the data field showed `---` for a prolonged time after acquiring GPS because GPS acquisition does not trigger a forecast fetch — only the 5-minute background temporal event can initiate a web request. The second, documented in `docs/field_test.v2.md`, is that forecast data cached during one activity survives into the next activity, causing the data field to display stale but locally valid forecast data from a previous session instead of starting clean.

At the end of this milestone, two new behaviours exist:

1. When the data field first acquires GPS (or reacquires it after a loss), it schedules a background temporal event at the earliest time permitted by Garmin's 5-minute constraint. If no temporal event has fired in the current session, the event fires immediately. If the last event was recent, the event fires as soon as the 5-minute minimum elapses. After the immediate fetch completes, the normal 5-minute repeating schedule resumes.

2. When an activity ends, the forecast cache and session-scoped storage keys are cleared. The next activity starts with an empty cache and must acquire GPS and fetch fresh data before displaying any forecast. Two independent cleanup hooks ensure robustness: a background `onActivityCompleted` event (primary) and a foreground `onTimerReset` callback (safety net).

**Garmin constraint: `Background.registerForTemporalEvent()` and the 5-minute minimum**

`Background.registerForTemporalEvent()` accepts either a `Time.Duration` (repeating interval) or a `Time.Moment` (one-shot at a specific point in time). Only one temporal registration can be active at a time; a new registration replaces the previous one.

The Duration form auto-repeats: after the event fires, it is automatically rescheduled at the same interval. The Moment form is one-shot: after it fires, there is no automatic re-scheduling. Because this milestone replaces the Duration registration with a one-shot Moment when GPS is acquired, the repeating schedule must be explicitly restored afterward.

Garmin enforces a minimum interval of 5 minutes between temporal events. `Background.getLastTemporalEventTime()` returns the `Time.Moment` when the last temporal event actually fired, or `null` if no event has fired in the current session. When scheduling a Moment that is in the past (relative to the current time), the system fires the event immediately. This means the scheduling pattern is:

    var lastTime = Background.getLastTemporalEventTime();
    if (lastTime != null) {
        // Schedule at lastTime + 5min. If that moment is in the past,
        // the event fires immediately. If it is in the future, the event
        // fires at that time.
        Background.registerForTemporalEvent(
            lastTime.add(new Time.Duration(5 * 60)));
    } else {
        // No prior event in this session — fire immediately.
        Background.registerForTemporalEvent(Time.now());
    }

**Files to modify:**

`source/FetchManager.mc` — add a `gpsJustAcquired` flag to detect the no-GPS-to-GPS transition.

- Add `var gpsJustAcquired as Boolean = false;` as a public instance variable.
- In `updatePosition()`, before setting `hasPosition = true`, check whether `hasPosition` is currently `false`. If so, this is a GPS acquisition transition: set `gpsJustAcquired = true`. The flag is read and reset by the caller (`WindForceView.compute()`).

`source/WindForceView.mc` — check the flag after each `updatePosition()` call and schedule an immediate background fetch when GPS is first acquired.

- Add `import Toybox.Background;` and `import Toybox.Time;`.
- In `compute()`, after `_fetchMgr.updatePosition(info)`, check `_fetchMgr.gpsJustAcquired`. If `true`, reset the flag to `false` and call a new private method `scheduleImmediateFetch()`.
- `scheduleImmediateFetch()` implements the scheduling pattern described above: it calls `Background.getLastTemporalEventTime()` and registers either `Time.now()` (if no prior event) or `lastTime.add(Duration(5*60))` (if a prior event exists). This replaces the currently active Duration registration with a one-shot Moment, which triggers the background service as soon as Garmin allows.

`source/WindForceApp.mc` — restore the repeating 5-minute schedule after every background event and handle activity-completion cleanup.

- In `getInitialView()`, add `Background.registerForActivityCompletedEvent()` alongside the existing temporal event registration. This tells the system to call `onActivityCompleted()` on the service delegate when the current activity finishes.
- In `onBackgroundData()`, after processing the response and before calling `WatchUi.requestUpdate()`, call `Background.registerForTemporalEvent(new Time.Duration(5 * 60))`. This re-registration is essential because the GPS-triggered one-shot Moment replaces the auto-repeating Duration. Without re-registration, no further background events would fire after the one-shot completes. In the normal case (no GPS override), re-registering the Duration is redundant but harmless — it replaces the existing auto-repeating registration with an equivalent one.
- In `onBackgroundData()`, add handling for `{"kind": "session_end"}`: call `StorageManager.clearAllForecasts()`, delete `bg_lat` and `bg_lon` from `Application.Storage`, and call `WatchUi.requestUpdate()`. Do not re-register the temporal event after a session-end signal — the activity is over and no further fetches are needed until the next activity starts.

`source/WindForceServiceDelegate.mc` — add activity-completion callback.

- Add `onActivityCompleted(activity as Activity.Info) as Void`. This callback fires in the background process when an activity is saved or discarded. It calls `Background.exit({"kind" => "session_end"})` to signal the foreground to clear the session cache. The actual cleanup is performed by `onBackgroundData()` in the foreground to keep the clearing logic in one place and avoid scope issues with `StorageManager` module availability in the background build.

`source/WindForceView.mc` — add foreground safety net for activity-end cleanup.

- Add `onTimerReset() as Void`. This `WatchUi.DataField` callback fires in the foreground when the activity timer is reset at the end of a session. It calls `StorageManager.clearAllForecasts()`, deletes `bg_lat` and `bg_lon` from `Application.Storage`, resets `_fetchMgr.hasPosition` to `false` and `_fetchMgr.gpsJustAcquired` to `false`, and calls `WatchUi.requestUpdate()`. This is a defence-in-depth measure: if the `onActivityCompleted` background event is delayed, unavailable, or behaves differently on certain device/activity flows, the foreground cleanup still runs.

**Session cleanup scope:**

The following Storage keys are cleared when an activity ends:

- All `fc_*` forecast entries and `fc_keys` — via `StorageManager.clearAllForecasts()`
- `bg_lat` and `bg_lon` — the GPS position persisted for the background service

The background request metadata keys (`bg_rLat`, `bg_rLon`, `bg_reqUnits`, `bg_reqSlots`) are transient values written by each `onTemporalEvent()` call and overwritten on the next background cycle. They do not need explicit cleanup.

**Why `AppBase.onStop()` is not used:**

`onStop()` is a generic app termination/suspension callback, not an activity-completion signal. Using it for cache pruning would clear forecasts when the app exits for any reason (e.g., system memory pressure, watchface change), not just when an activity ends. The field test analysis in `docs/field_test.v2.md` specifically recommends against `onStop()` for this reason.

**Sequence of events after this milestone:**

1. Activity starts. `getInitialView()` registers `Duration(5 * 60)` — first background event scheduled in ~5 minutes.
2. GPS acquires a fix (e.g., 30 seconds after start). `compute()` detects the transition. `scheduleImmediateFetch()` calls `getLastTemporalEventTime()` → `null` (no event has fired yet). Registers `Time.now()`. The one-shot Moment fires immediately, replacing the pending Duration.
3. Background service reads GPS from Storage, calls `/v1/forecast`, returns data via `Background.exit()`.
4. `onBackgroundData()` processes the forecast, stores it, re-registers `Duration(5 * 60)`, and calls `WatchUi.requestUpdate()`. The display updates from the no-forecast placeholder to live wind data.
5. Subsequent background events fire every ~5 minutes via the restored Duration registration.

Alternative scenario: GPS acquires a fix 6 minutes after start. The first Duration event fires at t=5min (background service gets no GPS from Storage, returns error, `onBackgroundData()` re-registers Duration). At t=6min, GPS acquired. `getLastTemporalEventTime()` returns t=5min. Registers t=5min + 5min = t=10min. The one-shot fires at t=10min. This is the same time the Duration would have fired anyway — the Garmin 5-minute constraint means no improvement is possible here. The fix primarily benefits the common case where GPS locks before the first temporal event.

**Activity-end sequence:**

1. User saves or discards the activity.
2. `onTimerReset()` fires in the foreground data field. It clears all cached forecasts and session keys, resets `_fetchMgr.hasPosition` to `false`, and requests a display update. The display reverts to `NO GPS`.
3. `onActivityCompleted(activity)` fires in the background service delegate. It calls `Background.exit({"kind" => "session_end"})`.
4. `onBackgroundData()` receives the session-end signal, calls `StorageManager.clearAllForecasts()`, deletes `bg_lat`/`bg_lon`, and requests a display update. If `onTimerReset()` already cleared the cache, this is a no-op (clearing an already-empty cache is harmless).
5. The next activity start calls `getInitialView()`, which re-registers both the temporal event and the activity-completed event. The display starts clean.

The two cleanup hooks are intentionally redundant. If one fires before the other, the second is a harmless no-op. If one fails to fire on a particular device or activity flow, the other still cleans up.

**How to validate:**

In the simulator (GPS fix trigger):

1. Start a Kayak activity without GPS simulation. The display should show `NO GPS`.
2. Begin GPS simulation (load a GPX file). The display should transition to the no-forecast placeholder (`-/-•-/-•-/-`).
3. Trigger a background event via `Simulation > Trigger Background Event`. The display should update to live wind data.
4. In the simulator console, verify that the temporal event registration was called when GPS was acquired (if debug logging is enabled).

On a physical device (GPS fix trigger):

1. Start a Kayak activity outdoors. Note the time when the display transitions from `NO GPS` to the no-forecast placeholder.
2. Observe the time when wind data first appears. With this fix, data should appear shortly after the placeholder state (subject to the 5-minute constraint from the last temporal event). Without this fix, data could take up to 5 minutes from the activity start.
3. Walk indoors until GPS is lost (`NO GPS`). Walk back outdoors. Verify that wind data reappears shortly after GPS is reacquired.

In the simulator (activity-end cache pruning):

1. Start a Kayak activity with GPS simulation. Trigger a background event to fetch forecast data. Verify wind data is displayed.
2. Stop and save the activity.
3. Start a new Kayak activity. The display should show `NO GPS` (or the no-forecast placeholder once GPS is acquired), not the cached forecast from the previous activity.
4. Confirm that `Application.Storage` no longer contains `fc_*` entries or `bg_lat`/`bg_lon` keys from the previous session.

On a physical device (activity-end cache pruning):

1. Complete a kayak paddle with wind data displayed.
2. Save the activity. Note whether the display clears.
3. Start a new activity. Verify that stale data from the previous session is not displayed — the field should show `NO GPS` or the no-forecast placeholder until a fresh fetch completes.

## Concrete Steps

(To be updated as each milestone is implemented. The initial concrete steps for Milestone 1 are below.)

Milestone 1 steps:

    Working directory: ~\repos\garmin_df_wind_force

    1. Create the project directory structure:
       source/
       resources/
       resources/images/
       bin/

    2. Create manifest.xml, monkey.jungle, and all source and resource files
       as described in the Milestone 1 plan above.

    3. Generate a developer key if one does not already exist:
       "~\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21\bin\connectiq" keygen

    4. Build: Open VS Code, open the garmin_df_wind_force folder, press Ctrl+Shift+P,
       select "Monkey C: Build for Device", choose instinct2x.

    5. If build succeeds, run the simulator:
       Ctrl+Shift+P > "Monkey C: Run on Simulator"

    6. In the simulator, navigate to Activities > Kayak > Data Fields and verify
       Wind Force appears and displays "3(4)N".

## Validation and Acceptance

Each milestone has its own validation section above. The overall acceptance criteria for the complete project:

1. A Kayak activity on a supported device (Instinct 2X Solar or Instinct 2) displays the Wind Force data field with live Met Eireann wind data.
2. The display shows wind speed, gust speed, and wind direction label, with a `•` separator between adjacent time slots.
3. Multiple time slots are shown when the data field occupies a wider screen slot.
4. Wind units are configurable (Beaufort, Knots, mph, km/h, m/s) via Garmin Connect Mobile.
5. Forecast intervals for the 2nd and 3rd time slots are configurable (1-6 hours).
6. Data refreshes via background temporal events using the latest stored GPS position, and new model runs are picked up automatically on subsequent `/v1/forecast` fetches.
7. Offline fallback uses the nearest cached forecast grid point. Look-ahead caching is deferred follow-up work and is not currently part of the implemented Milestone 4 architecture.
8. Stale data (older than 30 minutes) is indicated with a `*` prefix.
9. When no GPS fix is available, the field shows `NO GPS`. When GPS is available but no forecast is cached for the current or nearest grid point, the field shows a slot-aware placeholder (`-/-•-/-•-/-` for 3 slots).
10. The data field fits within the 32 KB memory limit.
11. The Cloudflare Worker proxy correctly translates Met Eireann XML to compact JSON and caches results.
12. When GPS is first acquired (or reacquired after a loss), a background fetch is triggered at the earliest time permitted by Garmin's 5-minute constraint, rather than waiting for the next scheduled polling interval.
13. When an activity ends (saved or discarded), the forecast cache and session storage keys are cleared. The next activity starts with an empty cache and does not display stale data from a previous session.

## Idempotence and Recovery

All source files are created fresh in this plan and tracked in git. Running the build multiple times produces the same output. The Cloudflare Worker can be deployed repeatedly with `npm run deploy` without side effects (it overwrites the previous version). KV cache entries expire via TTL and do not accumulate unboundedly.

If a milestone is partially completed and needs to be restarted, the developer can `git stash` or `git checkout` the incomplete changes and begin the milestone from scratch using the instructions in this plan.

The Met Eireann API is read-only and stateless; there is no risk of corrupting upstream data.

## Artifacts and Notes

Met Eireann API example request:

    curl "http://openaccess.pf.api.met.ie/metno-wdb2ts/locationforecast?lat=53.35;long=-6.26"

The response is XML in the `metno-wdb2ts` format. An abbreviated example of the relevant elements:

    <weatherdata>
      <product class="pointData">
        <time datatype="forecast" from="2026-03-12T10:00:00Z" to="2026-03-12T10:00:00Z">
          <location latitude="53.3500" longitude="-6.2600" altitude="15">
            <windDirection deg="195.0" name="SSW"/>
            <windSpeed mps="7.2" beaufort="4" name="Moderate breeze"/>
            <windGust mps="11.3"/>
          </location>
        </time>
        ...
      </product>
    </weatherdata>

Beaufort scale conversion reference (from `docs/Marine-Beaufort-scale.png`):

    Force 0: Calm, < 1 knot
    Force 1: Light air, 1-3 knots
    Force 2: Light breeze, 4-6 knots
    Force 3: Gentle breeze, 7-10 knots
    Force 4: Moderate breeze, 11-16 knots
    Force 5: Fresh breeze, 17-21 knots
    Force 6: Strong breeze, 22-27 knots
    Force 7: Near gale, 28-33 knots
    Force 8: Gale, 34-40 knots
    Force 9: Strong gale, 41-47 knots
    Force 10: Storm, 48-55 knots
    Force 11: Violent storm, 56-63 knots
    Force 12: Hurricane, 64+ knots

## Interfaces and Dependencies

**Connect IQ Data Field (Monkey C):**

In `source/WindForceApp.mc`:

    class WindForceApp extends Application.AppBase {
        function initialize() as Void
        function getInitialView() as [Views] or [Views, InputDelegates]
        function onBackgroundData(data as Application.PersistableType) as Void
        function getServiceDelegate() as [System.ServiceDelegate]
    }

In `source/WindForceView.mc`:

    class WindForceView extends WatchUi.DataField {
        function initialize() as Void
        function compute(info as Activity.Info) as Void
        function onLayout(dc as Graphics.Dc) as Void
        function onUpdate(dc as Graphics.Dc) as Void
        function onTimerReset() as Void                    // Milestone 7: activity-end cache cleanup
        private function scheduleImmediateFetch() as Void  // Milestone 7: GPS-triggered one-shot
    }

In `source/DisplayRenderer.mc`:

    module DisplayRenderer {
        function renderWindSlot(data as WindData) as String
        function formatLayout(forecasts as Array<WindData>, fetchTimestamp as Number, hasPosition as Boolean) as String
        function slotCount(width as Number) as Number
    }

In `source/FetchManager.mc`:

    class FetchManager {
        var currentLatDeg as Double
        var currentLonDeg as Double
        var hasPosition as Boolean
        var gpsJustAcquired as Boolean   // set true on no-GPS → GPS transition
        function updatePosition(info as Activity.Info) as Void
    }

In `source/StorageManager.mc`:

    module StorageManager {
        function storeForecast(roundedLat as String, roundedLon as String, data as Dictionary) as Void
        function loadForecast(roundedLat as String, roundedLon as String) as Dictionary or Null
        function loadNearestForecast(lat as Double, lon as Double) as Dictionary or Null
        function pruneStorage() as Void
        function getStoredKeys() as Array<String>
        function roundCoord(value as Double) as String
    }

In `source/WindData.mc`:

    class WindData {
        var time as String
        var windSpeed as Number      // pre-converted integer in the requested unit
        var gustSpeed as Number      // pre-converted integer in the same unit
        var windDir as String        // cardinal/intercardinal label (e.g., "NE")
        function initialize(time as String, windSpeed as Number, gustSpeed as Number, windDir as String) as Void
    }

In `source/WindForceServiceDelegate.mc`:

    class WindForceServiceDelegate extends System.ServiceDelegate {
        function onTemporalEvent() as Void
        function onForecastReceived(responseCode as Number, data as Dictionary or String or Null) as Void
        function onActivityCompleted(activity as Activity.Info) as Void  // Milestone 7: session-end signal
    }

**Cloudflare Worker (TypeScript):**

In `proxy/src/types.ts`:

    // Raw forecast entry as parsed from Met Eireann XML (stored in KV cache)
    interface RawForecastEntry {
        time: string;
        wind_mps: number;
        wind_deg: number;
        wind_beaufort: number;
        gust_mps: number;
    }

    // Converted forecast entry returned to the watch
    interface ForecastEntry {
        time: string;
        wind_speed: number;    // pre-converted integer
        gust_speed: number;    // pre-converted integer
        wind_dir: string;      // cardinal/intercardinal label (e.g., "NE")
    }

    interface ForecastResponse {
        api_version: string;   // API version (e.g., "v1")
        model_run: string;
        units: string;         // echoes the requested unit (e.g., "beaufort", "knots")
        forecasts: ForecastEntry[];
    }

    interface ModelStatusResponse {
        api_version: string;   // API version (e.g., "v1")
        model_run: string;
    }

    interface Env {
        FORECAST_CACHE: KVNamespace;
    }

In `proxy/src/index.ts`:

    export default {
        async fetch(request: Request, env: Env): Promise<Response>
    }

In `proxy/src/met-eireann.ts`:

    function roundCoordinate(value: number): number
    async function fetchAndParseForecast(lat: number, lon: number): Promise<ForecastResponse>
    function parseMetEireannXml(xml: string): ForecastResponse

**External dependencies:**

- Garmin Connect IQ SDK 8.2.3 (already installed)
- Cloudflare Wrangler CLI (installed as local devDependency via `npm install` in `proxy/`)
- Node.js (for Wrangler and Worker development)
- `fast-xml-parser` npm package (for XML parsing in the Worker, ~50 KB, well within Worker limits)

---

## Revision History

**Revision 2 (2026-03-12):** Addressed all 5 findings from `docs/execution_plan_review.v1.md`:

1. Fixed Wrangler route syntax from `[routes]` to `[[routes]]` (TOML array-of-tables).
2. Added 15-minute throttled polling interval for `/v1/model-status` with `MODEL_STATUS_POLL_INTERVAL_SEC` constant; `executeFetchCycle` now evaluates local triggers first and only polls the proxy on the configured interval.
3. Standardised all internal coordinate and heading math to radians (matching `Activity.Info.currentHeading` and `Position.Location` native units). Degrees used only for display and proxy URL parameters. Updated `computeLookAheadPoints` signature from `bearingDeg` to `bearingRad`. Added Decision Log entries.
4. Replaced ambiguous settings file reference with prescriptive `resources/properties.xml` (confirmed for SDK 8.2.3).
5. Added timestamps to all Progress entries and added this Revision History section per PLANS.md requirements.

**Revision 3 (2026-03-12):** Milestone 1 completed. Created project scaffolding:

- `manifest.xml` (version 3 format, `datafield` type, `instinct2x` product, `Communications` permission, `minApiLevel="3.1.0"`)
- `monkey.jungle` (minimal build config)
- `source/WindForceApp.mc` (AppBase subclass with `getInitialView()`)
- `source/WindForceView.mc` (DataField subclass, renders static "3(4)N" centred on screen)
- `resources/strings/strings.xml` (AppName = "Wind Force")
- `resources/drawables/drawables.xml` + `launcher_icon.svg` (62x62 wind arrow placeholder)
- Updated `.gitignore` with `bin/` and `*.prg`
- Build verified: `monkeyc -d instinct2x -l 3` passes with no errors or warnings.
- Deviations from original plan: used SVG icon instead of PNG (SDK 8.2.3 convention), used resource subdirectories instead of flat layout.

**Revision 4 (2026-03-12):** Milestone 2 completed. Cloudflare Worker proxy:

- `proxy/package.json`, `proxy/tsconfig.json`, `proxy/wrangler.toml` (project scaffolding)
- `proxy/src/types.ts` (Env, RawForecastEntry, ForecastEntry, ForecastResponse, RawForecastResponse interfaces)
- `proxy/src/met-eireann.ts` (XML fetch + parsing with fast-xml-parser; filters point forecasts where from===to; extracts harmonie model run timestamp)
- `proxy/src/index.ts` (Worker entry point; GET /v1/forecast with coordinate rounding to 0.025 deg, KV caching with 7h TTL, model run resolution with 15min TTL; CORS headers; input validation)
- Endpoint tested locally via `npm run dev`: `/v1/forecast?lat=53.35&lon=-6.26` returns api_version, units, and forecasts with wind_speed, gust_speed, wind_dir.
- Error handling verified: missing params (400), invalid coords (400), unknown paths (404).
- KV namespace ID is a placeholder; must run `npx wrangler kv namespace create FORECAST_CACHE` before deploying.

**Revision 5 (2026-03-13):** Milestone 3 completed. Display engine:

- `source/WindData.mc` (data class: time, windMps, windDeg, windBeaufort, gustMps)
- `source/DisplayRenderer.mc` (module: renderWindSlot, formatLayout, slotCount)
- Updated `source/WindForceView.mc` (onLayout determines slot count from dc width; onUpdate calls DisplayRenderer with hardcoded sample data; selectFont auto-picks largest font that fits)
- Layout selection: 1-slot (<90px), 2-slot (90-149px), 3-slot (>=150px)
- Direction: 8 cardinal/intercardinal labels (N, NE, E, SE, S, SW, W, NW)
- Separator: `•` (bullet) between adjacent time slots
- Unit conversion: Beaufort (default), knots, mph, km/h, m/s with mpsToBeaufort lookup for gust
- Verified in simulator: small slot shows "3/4NE", large slot shows "3/4NE•5/6S•3/5SW"
- Memory: 9.4/28.5kB — ~19kB headroom remaining.

**Revision 6 (2026-03-13):** Architectural change — move calculations from watch to proxy.

Motivation: The Instinct 2X data field has a 32 KB memory limit. Unit conversion, Beaufort lookup, and direction labelling code on the watch consumes memory that could be saved by performing these calculations on the proxy instead. This also simplifies the watch-side code significantly.

Changes across milestones:

- **Milestone 2 (Proxy):** `/v1/forecast` endpoint now accepts an optional `units` query parameter (`beaufort`, `knots`, `mph`, `kmh`, `mps`; default `beaufort`). Raw forecast data is cached in KV in its original m/s + degrees form; unit conversion is applied on the fly before returning the response. Response shape changed: `wind_mps`/`wind_beaufort`/`gust_mps` replaced by `wind_speed` (integer), `gust_speed` (integer), `wind_dir` (cardinal label string). Top-level `units` field added to echo the requested unit.
- **Milestone 3 (Display Engine):** `DisplayRenderer` simplified — removed `convertSpeed()`, `mpsToBeaufort()`, `directionLabel()`. `renderWindSlot()` reads pre-converted values directly. `formatLayout()` no longer takes a `units` parameter. `WindData` fields changed from raw floats to pre-converted integers + direction string.
- **Milestone 4 (Communication):** `ForecastService.fetchForecast()` signature gains a `units` string parameter. `FetchManager.executeFetchCycle()` reads the current unit setting, passes it to `fetchForecast()`, and tracks `_lastFetchedUnits` to detect unit changes as a fetch trigger.
- **Milestone 5 (Settings):** `SettingsManager` gains `getWindUnitsString()` to map the numeric setting to a proxy-compatible string. Unit change triggers a refetch (not a local re-render), with a brief display delay of 1-3 seconds while the new data is fetched.
- **Interfaces:** TypeScript `types.ts` splits into `RawForecastEntry` (internal/cache) and `ForecastEntry` (response). `ForecastResponse` gains a `units` field. Monkey C `WindData` fields changed to `windSpeed`, `gustSpeed`, `windDir`, `windDeg`.
- **Decision Log:** New entry added for this architectural shift.

**Revision 7 (2026-03-13):** Move slot selection from watch to proxy.

Motivation: Since the proxy already performs unit conversion and direction labelling, it's natural to also have it select the forecast entries for the requested time slots. This eliminates interval selection logic from the watch and removes `wind_deg` from the response (no longer needed on the watch).

Changes across milestones:

- **Milestone 2 (Proxy):** `/v1/forecast` endpoint gains a `slots` query parameter (comma-separated hour offsets, e.g., `0,3,6`, max 3 values, default `0`). The proxy selects the closest forecast entry for each offset. Response field `wind_deg` removed (not needed on the watch).
- **Milestone 3 (Display Engine):** `DisplayRenderer` further simplified — `formatLayout()` takes a `slots` parameter (for building the no-forecast placeholder) but does not perform interval selection; it iterates the `forecasts` array directly (which already contains exactly the right entries) and inserts a `•` between slots. `WindData` field `windDeg` removed.
- **Milestone 4 (Communication):** `ForecastService.fetchForecast()` signature gains a `slots` string parameter. `FetchManager.executeFetchCycle()` builds the `slots` string from the current slot count (from field width) and interval settings, and tracks `_lastFetchedSlots` to detect interval changes as a fetch trigger.
- **Milestone 5 (Settings):** Interval change now triggers a refetch (same as unit change). Forecast interval mapping logic moved from `DisplayRenderer` to the proxy.
- **Interfaces:** `ForecastEntry` field `wind_deg` removed. Monkey C `WindData` field `windDeg` removed. `ForecastService.fetchForecast()` gains `slots` parameter. `DisplayRenderer.formatLayout()` loses `slotCount` parameter.
- **Decision Log:** Entry updated to include slot selection.

**Revision 8 (2026-03-14):** Align execution plan with the background-service rework and documented deferrals.

- Rewrote Milestone 4 to describe `System.ServiceDelegate` + `Background.registerForTemporalEvent()` rather than the removed direct-fetch architecture.
- Updated Milestone 5 to build settings handling on top of the background service, not `FetchManager.executeFetchCycle()`.
- Corrected interface signatures for `WindForceApp`, `WindForceView`, `FetchManager`, `StorageManager`, `DisplayRenderer`, and `WindForceServiceDelegate` to match the current codebase.
- Documented that look-ahead fetching is deferred follow-up work, not part of the current Milestone 4 implementation.
- Added an explicit on-device validation requirement for `Application.Properties` propagation from foreground settings changes to the background service during an active activity.

**Revision 9 (2026-03-18):** Added Milestone 7 — immediate background fetch on first GPS fix.

- Added Milestone 7 section addressing the field-test finding in `docs/field_test.v1.md`: after GPS acquisition, the data field showed `---` for up to 5 minutes because GPS lock does not trigger a fetch.
- Implementation: `FetchManager` gains a `gpsJustAcquired` flag set on the no-GPS → GPS transition. `WindForceView.compute()` detects this flag and calls `scheduleImmediateFetch()`, which registers a one-shot `Time.Moment` via `Background.registerForTemporalEvent()` at the earliest legal time (respecting the 5-minute minimum via `Background.getLastTemporalEventTime()`). `WindForceApp.onBackgroundData()` re-registers `Duration(5 * 60)` after every background event to restore the repeating schedule.
- Added Decision Log entry for the GPS-fix trigger approach.
- Updated Progress, Interfaces (FetchManager, WindForceView), Validation and Acceptance (criterion 12), and Outcomes & Retrospective (post-release work).

**Revision 10 (2026-03-18):** Extended Milestone 7 with activity-completion cache pruning.

- Addresses `docs/field_test.v2.md`: cached forecasts from a previous activity survive into the next activity, displaying stale data.
- Implementation: `WindForceApp.getInitialView()` registers `Background.registerForActivityCompletedEvent()`. `WindForceServiceDelegate` gains `onActivityCompleted()` which signals the foreground via `Background.exit({"kind" => "session_end"})`. `WindForceApp.onBackgroundData()` handles the session-end signal by calling `StorageManager.clearAllForecasts()` and deleting `bg_lat`/`bg_lon`. `WindForceView` gains `onTimerReset()` as a foreground safety net performing the same cleanup.
- Added Decision Log entry explaining why `onActivityCompleted` + `onTimerReset` were chosen over `AppBase.onStop()`.
- Updated Milestone 7 title, introduction, files-to-modify, sequence-of-events, and validation sections.
- Updated Progress, Interfaces (WindForceView, WindForceServiceDelegate), Validation and Acceptance (criterion 13), and Outcomes & Retrospective.

**Revision 11 (2026-03-18):** Implemented Milestone 7.

- Implemented all four file changes as designed in Revisions 9–10.
- `FetchManager.mc`: added `gpsJustAcquired` flag, set on `!hasPosition` → GPS transition in `updatePosition()`.
- `WindForceView.mc`: `compute()` checks and resets `gpsJustAcquired`, calls `scheduleImmediateFetch()`. Added `scheduleImmediateFetch()` (one-shot Moment via `getLastTemporalEventTime()`). Added `onTimerReset()` for activity-end cleanup.
- `WindForceApp.mc`: `getInitialView()` registers for activity-completed events. `onBackgroundData()` handles `session_end` kind (clears cache, deletes session keys, returns without re-registering temporal event). Re-registers `Duration(5*60)` after all other background events. Added `Storage` import.
- `WindForceServiceDelegate.mc`: added `onActivityCompleted()` callback that exits with `{"kind" => "session_end"}`. Used untyped `activity` parameter to avoid `Activity.Sport`/`Activity.SubSport` resolution failure in `(:background)` scope.
- Strict build (`-l 3`) passes. Release IQ package built for all 3 device variants.
- Marked Milestone 7 as complete in Progress section.
