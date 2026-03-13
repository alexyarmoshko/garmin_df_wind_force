# Wind Force Data Field - Execution Plan

This Execution Plan is a living document. The sections Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds. This document must be maintained in accordance with `~/.codex/PLANS.md`.

## Purpose / Big Picture

After this work is complete, a kayaker wearing a Garmin Instinct 2X Solar will be able to add a "Wind Force" data field to their Kayak activity screen. During a paddle, the field will display the current wind speed (in Beaufort or other units), gust speed, wind direction (as an arrow), and whether the wind is veering or backing, all derived from Met Eireann's HARMONIE weather model. Depending on the data field slot size chosen by the user, the display shows one, two, or three time slots so the paddler can see how conditions are forecast to change over the next few hours.

The data flows from Met Eireann's XML API through a Cloudflare Worker proxy (which translates XML to compact JSON and caches results) to the watch via the paired phone's internet connection. When connectivity is lost, previously fetched data including look-ahead points along the route is displayed with a staleness indicator.

To see it working: deploy the Cloudflare Worker, side-load the data field onto the watch (or run it in the Connect IQ simulator), start a Kayak activity with the Wind Force field visible, and observe wind data updating as the GPS position changes.

## Progress

- [x] (2026-03-12) Milestone 1: Project scaffolding and static data field proof-of-concept
- [x] (2026-03-12) Milestone 2: Cloudflare Worker proxy with Met Eireann XML-to-JSON translation
- [x] (2026-03-13) Milestone 3: Data field display engine (rendering, layouts, unit conversions)
- [ ] (2026-03-12) Milestone 4: Communication layer and fetch strategy
- [ ] (2026-03-12) Milestone 5: User settings and staleness handling
- [ ] (2026-03-12) Milestone 6: Integration testing, optimisation, and deployment
- [x] (2026-03-12) Plan review v1: addressed all 5 findings (Wrangler syntax, model-status polling, radians, properties.xml, PLANS.md compliance)

## Surprises & Discoveries

- (2026-03-12) SDK 8.2.3 templates use SVG for launcher icons (not PNG). The `<bitmap>` resource element accepts SVG files with `dithering="none"`. Adopted SVG for the launcher icon.
- (2026-03-12) SDK 8.2.3 complex data field template places resources in subdirectories (`resources/strings/strings.xml`, `resources/drawables/drawables.xml`) rather than flat (`resources/strings.xml`). Adopted the subdirectory convention.
- (2026-03-12) The Instinct 2X device is confirmed at API level 3.4 (CIQ 3.4.3) per `compiler.json`. Our `minApiLevel="3.1.0"` is compatible.
- (2026-03-12) Developer key at `~/.ssh/developer_key` (DER format) works for signing builds.
- (2026-03-12) Met Eireann XML contains two types of `<time>` elements: point forecasts (from === to) with wind data, and period forecasts (from !== to) with precipitation/symbols. Parser filters on from === to.
- (2026-03-12) Met Eireann response includes multiple models (harmonie, ec_n1280_1hr, ec_n1280_3hr, ec_n1280_6hr). We extract the `termin` attribute only from the `harmonie` model entry.
- (2026-03-13) The Instinct 2X large data field slot is wide enough for the 3-slot layout with auto font sizing. Memory usage at 9.4/28.5kB after adding the display engine — still ~19kB headroom for the remaining milestones.
- (2026-03-13) Cardinal letters (N, NE, E, etc.) render correctly on the Instinct 2X fonts. Unicode arrow testing deferred — letters are compact and readable.

## Decision Log

- Decision: Target device ID is `instinct2x` (covers both Instinct 2X and Instinct 2X Solar).
  Rationale: The Connect IQ SDK uses the same device ID for the solar and non-solar variants. Confirmed in SDK device reference at `doc/docs/Device_Reference/instinct2x.html`.
  Date/Author: 2026-03-12

- Decision: Use `WatchUi.DataField` (not `SimpleDataField`) for the view class.
  Rationale: `SimpleDataField` only returns a single value for display. The wind force field needs a custom multi-segment layout with arrows, parenthesised gusts, and veering/backing symbols. `WatchUi.DataField` provides `onLayout(dc)` and `onUpdate(dc)` for full drawing control.
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

- Decision: Poll `/model-status` at most once every 15 minutes, not on every compute cycle.
  Rationale: `compute()` fires roughly once per second. Polling the proxy on every cycle would waste battery, generate excessive network traffic, and conflict with the requirements (REQUIREMENTS.md line 159-162 describes lower-frequency polling). A 15-minute interval matches the KV TTL on the proxy side and is sufficient to detect new model runs promptly.
  Date/Author: 2026-03-12

- Decision: Move unit conversion, direction labels, Beaufort lookup, slot selection, and veer/back computation from the watch to the proxy.
  Rationale: The Instinct 2X data field has a 32 KB memory limit. By performing unit conversion (Beaufort, knots, mph, km/h, m/s), Beaufort-scale lookup for gusts, cardinal direction labelling, forecast interval selection, and veer/back computation on the proxy, the watch-side code becomes a thin display layer: `DisplayRenderer` only concatenates pre-computed strings, and `WindData` stores display-ready values (`windSpeed`, `gustSpeed`, `windDir`, `veer`). The `/forecast` endpoint accepts `units` and `slots` query parameters and returns exactly the entries the watch needs to render, with all values pre-converted. When the user changes the wind unit or interval settings, the watch triggers a refetch with the new parameters rather than re-computing locally. This maximises memory savings on the watch at the cost of slightly more proxy logic and an extra network round-trip when settings change.
  Date/Author: 2026-03-13

## Outcomes & Retrospective

(To be written at major milestone completions and at project end.)

## Context and Orientation

This is a greenfield project. The repository currently contains only documentation files:

    garmin_df_wind_force/
      AGENTS.md          -- Agent instructions for the Garmin Connect IQ SDK location
      CLAUDE.md          -- References AGENTS.md
      .gitignore         -- Ignores .env, IDE files, agent config files
      docs/
        REQUIREMENTS.md  -- Full product requirements (the source of truth)
        Marine-Beaufort-scale.png  -- Reference image of the Beaufort scale

No source code exists yet. Two distinct codebases will be created:

1. The Connect IQ data field (Monkey C), which lives in the repository root following standard Connect IQ project layout.
2. The Cloudflare Worker proxy (TypeScript), which lives in a `proxy/` subdirectory with its own `package.json` and `wrangler.toml`.

**Key terms used in this plan:**

- **Data field**: A Connect IQ application type that occupies a slot on an activity screen. It receives periodic callbacks with activity data (GPS, speed, heart rate, etc.) and renders a value or graphic in its allocated screen area.
- **Monkey C**: Garmin's programming language for Connect IQ apps. It has Java-like syntax with optional type annotations, runs on a proprietary VM on the watch.
- **Cloudflare Worker**: A serverless function that runs on Cloudflare's edge network. It handles HTTP requests and can use Cloudflare KV (a key-value store) for caching.
- **KV (Key-Value store)**: Cloudflare's distributed key-value storage. Used here to cache parsed forecast JSON so the Worker does not re-fetch from Met Eireann on every request.
- **HARMONIE-AROME**: The numerical weather prediction model run by Met Eireann. It covers Ireland, the UK, and a small area of northern France. Grid resolution is approximately 2.5 km. It runs every 6 hours (00, 06, 12, 18 UTC) and produces hourly forecasts out to 90 hours.
- **Beaufort scale**: A scale from 0 to 12 that categorises wind speed by its observed effects at sea. See `docs/Marine-Beaufort-scale.png` for the full table.
- **Veering/backing**: A clockwise shift in wind direction is called veering (symbol: a clockwise arrow). An anticlockwise shift is called backing (symbol: an anticlockwise arrow).
- **makeWebRequest()**: The Connect IQ API method `Communications.makeWebRequest()` that sends an HTTP request from the watch. The request is actually routed through the paired phone's internet connection via Bluetooth and the Garmin Connect Mobile app.
- **Application.Storage**: A persistent key-value store on the watch that survives app restarts. Used to cache forecast data between fetch cycles and across activity sessions.

**Development environment:**

- IDE: Visual Studio Code with the Monkey C / Connect IQ extension
- Connect IQ SDK: version 8.2.3, located at `C:\Users\alex\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21\`
- SDK samples: `<SDK_PATH>\samples\` and `C:\Users\alex\repos\garmin-connectiq-apps\`
- Target device: Instinct 2X Solar (device ID: `instinct2x`)
- Display: 176 x 176 pixels, monochrome (2 colours: black and white), semi-octagon shape, no touch screen
- Data field memory limit: 32,768 bytes (32 KB) -- this is tight and requires lean code
- Cloudflare tooling: Wrangler CLI for Worker development and deployment

## Plan of Work

### Milestone 1: Project Scaffolding and Static Data Field Proof-of-Concept

This milestone establishes the Connect IQ project structure and proves that a data field can be built, run in the simulator, and display static text on the Instinct 2X screen. At the end, a developer can run the simulator, start a Kayak activity, and see "3(4)N" rendered in the data field slot.

**What to create:**

The Connect IQ project follows a standard layout rooted in the repository directory. All paths below are relative to the repository root (`garmin_df_wind_force/`).

`manifest.xml` -- the application manifest. It declares the app as type `datafield`, targets the `instinct2x` device, and requests the `Communications` permission (needed later for HTTP requests). The entry class points to the main application class. A unique UUID must be generated for the `id` attribute.

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

Open the project in VS Code with the Connect IQ extension. Build for the `instinct2x` device. Launch the Connect IQ simulator. Select the Instinct 2X device in the simulator. Start a Kayak activity simulation. The Wind Force data field should appear in one of the data field slots displaying "3(4)N". If the text renders correctly and the simulator does not report errors, Milestone 1 is complete.

Build command (from the VS Code Command Palette): `Monkey C: Build for Device` selecting `instinct2x`. Alternatively, from the terminal:

    cd c:\Users\alex\repos\garmin_df_wind_force
    "C:\Users\alex\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21\bin\monkeyc" -d instinct2x -f monkey.jungle -o bin\WindForce.prg -y "path\to\developer_key.der"

Then in the simulator, load `bin\WindForce.prg` and start a Kayak activity.

### Milestone 2: Cloudflare Worker Proxy

This milestone builds the proxy backend that sits between the watch and Met Eireann. At the end, a developer can call the deployed Worker endpoint with a latitude/longitude and receive a compact JSON response containing hourly wind forecast data. They can also call `/model-status` to get the latest model run timestamp.

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

The KV namespace ID is obtained by running `wrangler kv namespace create FORECAST_CACHE` after Wrangler is set up.

#### Endpoint: GET /forecast

URL: `/forecast?lat={lat}&lon={lon}&units={units}&slots={slots}`

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
8. Select the forecast entries matching the requested `slots` offsets. For each offset, pick the entry whose time is closest to `now + offset` hours. Compute veer/back between consecutive selected entries. Convert to the requested units and build the JSON response:

        {
          "model_run": "2026-03-12T06:00:00Z",
          "units": "beaufort",
          "forecasts": [
            {
              "time": "2026-03-12T10:00:00Z",
              "wind_speed": 4,
              "gust_speed": 6,
              "wind_dir": "SSW",
              "veer": null
            },
            {
              "time": "2026-03-12T13:00:00Z",
              "wind_speed": 5,
              "gust_speed": 7,
              "wind_dir": "SW",
              "veer": "<"
            },
            {
              "time": "2026-03-12T16:00:00Z",
              "wind_speed": 3,
              "gust_speed": 5,
              "wind_dir": "W",
              "veer": "<"
            }
          ]
        }

    Response field details:
    - `units`: echoes the unit used for `wind_speed` and `gust_speed` (e.g., `"beaufort"`, `"knots"`).
    - `wind_speed`: wind speed as a rounded integer in the requested unit.
    - `gust_speed`: gust speed as a rounded integer in the requested unit.
    - `wind_dir`: cardinal/intercardinal direction label (one of N, NE, E, SE, S, SW, W, NW). Computed from the raw degree value using 8 sectors of 45 degrees each.
    - `veer`: veering/backing symbol between this entry and the previous one. `">"` for veering (clockwise shift), `"<"` for backing (anticlockwise shift), `null` for the first entry (no predecessor to compare with). Computed from the raw degree values of the two consecutive selected entries using the same normalisation logic (difference normalised to -180..180; positive = veering, negative = backing, zero = veering by convention).

    The `forecasts` array contains exactly the number of entries requested via `slots` (1 to 3), in the same order as the offsets. The watch can render these directly without any selection, conversion, or comparison logic.

    Unit conversion formulas (from raw m/s):
    - `beaufort`: standard Beaufort scale lookup (same breakpoints as the current `mpsToBeaufort` table).
    - `knots`: `round(mps * 1.94384)`
    - `mph`: `round(mps * 2.23694)`
    - `kmh`: `round(mps * 3.6)`
    - `mps`: `round(mps)`

9. Return the JSON response.

**XML Parsing**: Cloudflare Workers do not have a built-in DOM XML parser. Use a lightweight streaming/regex-based approach to extract the needed fields from the Met Eireann XML. The XML structure uses `<time>` elements with `from` and `to` attributes, containing `<location>` elements with child elements like `<windSpeed mps="7.2" beaufort="4" .../>` and `<windDirection deg="195" name="SSW"/>` and `<windGust mps="11.3"/>`. A simple parser that extracts these attribute values using regex or a small XML parser library (such as `fast-xml-parser`, which works in Workers) is sufficient.

#### Endpoint: GET /model-status

1. Check KV for a key `latest_model_run`. If found and fresh (less than 15 minutes old), return it.
2. Otherwise, fetch a minimal forecast from Met Eireann (e.g., for a fixed point like Dublin: lat=53.35, lon=-6.26) and extract the model run timestamp from the response.
3. Store the timestamp in KV as `latest_model_run` with a TTL of 900 seconds (15 minutes).
4. Return JSON: `{ "model_run": "2026-03-12T06:00:00Z" }`

**How to validate:**

After deploying with `wrangler deploy`:

    curl "https://api.kayakshaver.com/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0,3,6"

Expected: a JSON object with `model_run`, `units` (`"beaufort"`), and `forecasts` array with exactly 3 entries. Each entry has `time`, `wind_speed` (integer), `gust_speed` (integer), `wind_dir` (cardinal label string), and `veer` (`null` for first, `">"` or `"<"` for subsequent).

    curl "https://api.kayakshaver.com/forecast?lat=53.35&lon=-6.26&units=knots&slots=0"

Expected: same structure but `units` is `"knots"`, speed values are in knots, and `forecasts` has exactly 1 entry with `veer: null`.

    curl "https://api.kayakshaver.com/model-status"

Expected: a JSON object with a single `model_run` field containing a UTC timestamp.

For local development before deploying:

    cd proxy
    npm install
    wrangler dev

Then use `http://localhost:8787/forecast?lat=53.35&lon=-6.26` to test locally.

### Milestone 3: Data Field Display Engine

This milestone implements the rendering logic that turns wind data into the compact text display shown on the watch. At the end, the data field can take a set of wind forecast entries and render the correct layout string (e.g., "3(4)N veer" or "3(4)N>5(6)S") depending on the data field slot size allocated by the user's activity screen configuration.

**Display rendering overview:**

The Instinct 2X screen is 176x176 monochrome pixels. Data field slots come in various sizes depending on the activity screen layout the user selects. The `onLayout(dc)` callback receives a drawing context (`dc`) whose `getWidth()` and `getHeight()` reveal the allocated area. The rendering engine must adapt to the available width.

**Layout selection logic:**

The number of time slots displayed depends on the width available:

- Narrow field (width < 90px): 1-slot layout: `S(G)D V` where S=speed, G=gust, D=direction arrow, V=veer/back symbol
- Medium field (90px <= width < 150px): 2-slot layout: `S1(G1)D1 V S2(G2)D2`
- Wide field (width >= 150px): 3-slot layout: `S1(G1)D1 V1 S2(G2)D2 V2 S3(G3)D3`

These thresholds should be constants that can be tuned after on-device testing.

**Files to create/modify:**

`source/WindForceView.mc` -- update `onUpdate(dc)` to call the rendering engine rather than drawing static text.

`source/DisplayRenderer.mc` -- a module containing the rendering logic. Because unit conversion, Beaufort lookup, direction labelling, slot selection, and veer/back computation are all performed by the proxy, this module is a thin formatter that concatenates pre-computed values:

- `function renderWindSlot(data)` returns a string like "3(4)NE" for one time slot. It reads the pre-converted `windSpeed`, `gustSpeed`, and `windDir` directly from the `WindData` object — no conversion needed.
- `function formatLayout(forecasts)` concatenates the forecast entries into the final display string. Each entry's `veer` field (from the proxy) is inserted between consecutive slots. No slot count parameter is needed — the `forecasts` array already contains exactly the entries requested via the `slots` query parameter. No `units` parameter is needed since values are already converted. No interval selection logic is needed since the proxy performs it.
- `function slotCount(width)` determines 1/2/3-slot layout from the field width. This value is passed to `FetchManager` to determine how many slots to request from the proxy.
- **Removed from watch**: `convertSpeed()`, `mpsToBeaufort()`, `directionLabel()`, `veerBackSymbol()` — all handled by the proxy.

`source/WindData.mc` -- a simple data class to hold pre-converted, display-ready forecast data received from the proxy:

    class WindData {
        var time as String;
        var windSpeed as Number;   // pre-converted integer (Beaufort, knots, etc.)
        var gustSpeed as Number;   // pre-converted integer in same unit
        var windDir as String;     // cardinal label from proxy (e.g., "NE", "SW")
        var veer as String or Null; // ">" (veering), "<" (backing), or null (first entry)

        function initialize(time, windSpeed, gustSpeed, windDir, veer) { ... }
    }

**Font selection:** On the 176x176 monochrome screen, `Graphics.FONT_MEDIUM` or `Graphics.FONT_SMALL` is appropriate for the data field text. The font must be small enough that a 3-slot layout fits within the widest field. Test in the simulator to determine the right font. Use `dc.getTextWidthArea(text, font)` to measure text width and select the largest font that fits.

**How to validate:**

In the simulator, configure a Kayak activity with different data field layouts (single field, 2-field, 3-field). The Wind Force field should show the appropriate number of slots. For this milestone, hardcode sample wind data using the new pre-converted format (e.g., windSpeed=3, gustSpeed=4, windDir="NE", windDeg=45; windSpeed=5, gustSpeed=6, windDir="S", windDeg=180). The display should render "3(4)NE>5(6)S" or similar depending on slot count.

### Milestone 4: Communication Layer and Fetch Strategy

This milestone connects the data field to the Cloudflare Worker proxy. At the end, the data field fetches real wind data from the proxy based on the watch's GPS position and displays live forecast information during a simulated Kayak activity.

**Files to create/modify:**

`source/ForecastService.mc` -- handles all communication with the proxy:

- Holds the proxy base URL as a constant (e.g., `https://api.kayakshaver.com`).
- `function fetchForecast(lat, lon, units, slots, callback)` calls `Communications.makeWebRequest()` to `GET /forecast?lat={lat}&lon={lon}&units={units}&slots={slots}` with `responseType` set to `HTTP_RESPONSE_CONTENT_TYPE_JSON`. The `units` parameter is one of `"beaufort"`, `"knots"`, `"mph"`, `"kmh"`, `"mps"` — read from the current user setting via `SettingsManager.getWindUnitsString()`. The `slots` parameter is a comma-separated string of hour offsets (e.g., `"0,3,6"`) built from the current slot count and interval settings. The callback receives the parsed JSON dictionary directly from the Connect IQ runtime (no manual JSON parsing needed on the watch). The response already contains pre-converted integer speeds, cardinal direction labels, and veer/back symbols, so the watch only needs to store and display them as-is.
- `function fetchModelStatus(callback)` calls `GET /model-status` to retrieve the current model run timestamp.
- Error handling: if `responseCode` is not 200, the callback receives null and the service logs the error code.

`source/FetchManager.mc` -- implements the fetch strategy described in the requirements:

- Tracks the position and timestamp of the last successful fetch.
- Tracks the last known model run timestamp.
- `function shouldFetch(currentLat, currentLon, currentTime)` returns true if any of the three triggers fire:
  - **Distance trigger**: the Haversine distance between current position and last fetch position exceeds 1.5 km. All coordinate math uses radians internally (matching `Activity.Info.currentLocation` native units). The Haversine formula in Monkey C: `d = 2 * R * arcsin(sqrt(sin^2((lat2-lat1)/2) + cos(lat1)*cos(lat2)*sin^2((lon2-lon1)/2)))` where R = 6371 km and lat/lon are in radians. Given the small distances involved (1-5 km), the equirectangular approximation is also acceptable and cheaper: `dx = (lon2-lon1) * cos((lat1+lat2)/2)`, `dy = lat2-lat1`, `d = sqrt(dx*dx + dy*dy) * R` (km), where all values are in radians.
  - **Time trigger**: more than 30 minutes (1800 seconds) since the last successful fetch.
  - **Model run trigger**: the latest model run from `/model-status` is newer than the cached model run.
- `function computeLookAheadPoints(lat, lon, bearingRad)` returns 2 points along the bearing at 2.5 km intervals. All parameters use radians: `lat` and `lon` are in radians (as returned by `Activity.Info.currentLocation`, which stores coordinates in radians natively), and `bearingRad` is in radians (as returned by `Activity.Info.currentHeading`). The destination-point formula expects radians throughout: `lat2 = asin(sin(lat1)*cos(d/R) + cos(lat1)*sin(d/R)*cos(bearing))`, `lon2 = lon1 + atan2(sin(bearing)*sin(d/R)*cos(lat1), cos(d/R)-sin(lat1)*sin(lat2))`. For 2.5 km, `d/R = 2.5/6371 = 0.000392`. Conversion to degrees is only performed when constructing the proxy URL query parameters (the proxy expects degrees) and when displaying direction arrows on screen.
- `function executeFetchCycle(info)` is the main entry point called from the data field's `compute()` method. It applies throttling so that network calls are not made on every compute cycle (which fires roughly once per second). The logic is:
  1. Evaluate the distance and time triggers locally (no network cost).
  2. If at least 15 minutes have elapsed since the last `/model-status` check, call `fetchModelStatus` (~50 bytes). Store the result and timestamp. This 15-minute polling interval aligns with the requirements (`docs/REQUIREMENTS.md` line 162) and avoids unnecessary battery, network, and proxy load.
  3. Check if the wind unit setting or forecast interval settings have changed since the last fetch (compare current settings to `_lastFetchedUnits` and `_lastFetchedSlots`). If either has changed, treat this as a trigger — the cached data was converted in the old unit or selected for different intervals and must be refetched.
  4. Build the `slots` string from the current slot count (determined by `DisplayRenderer.slotCount()` from the field width) and interval settings: slot 1 is always `0` (current hour), slot 2 is `forecastInterval1`, slot 3 is `forecastInterval2`. For example, with 3 slots and intervals 3h/6h: `"0,3,6"`. With 1 slot: `"0"`.
  5. If any trigger has fired (distance, time, model-run-changed, unit-changed, or interval-changed), call `fetchForecast` for the current position, passing the current `units` and `slots` strings.
  6. On success, compute look-ahead points from `info.currentHeading` (which is in radians; see the radians note below) and fetch those too (best-effort), passing the same `units` and `slots` strings.
  7. Store all results in `Application.Storage`. Update `_lastFetchedUnits` and `_lastFetchedSlots` to the current settings.
  8. If no trigger has fired, do nothing and return immediately.

  A module-level variable `_lastModelStatusCheckTime` tracks when `/model-status` was last polled. A constant `MODEL_STATUS_POLL_INTERVAL_SEC = 900` (15 minutes) controls the polling frequency.

`source/StorageManager.mc` -- wraps `Application.Storage` for forecast data persistence:

- `function storeForecast(roundedLat, roundedLon, data)` stores a forecast JSON dictionary keyed by `"fc_{lat}_{lon}"`.
- `function loadForecast(roundedLat, roundedLon)` retrieves a cached forecast.
- `function loadNearestForecast(lat, lon)` scans stored keys to find the nearest cached grid point within 2.5 km.
- `function pruneStorage()` removes old entries, keeping only the 5 most recent to stay within storage limits.

`source/WindForceView.mc` -- update `compute(info)` to:

1. Read GPS position from `info.currentLocation` (a `Position.Location` object). Internally, `Position.Location` stores coordinates in radians. Use `toRadians()` for all internal coordinate math (distance calculations, look-ahead points). Use `toDegrees()` only when constructing the proxy URL query parameters, since the proxy API expects degrees. Read heading from `info.currentHeading`, which is in radians.
2. Call `FetchManager.executeFetchCycle(info)`.
3. In `onUpdate(dc)`, read the current position's forecast from `StorageManager` and pass it to `DisplayRenderer`.

**Asynchronous flow:** `makeWebRequest()` is asynchronous. The callback fires at a later time, not during `compute()`. The pattern is: `compute()` initiates fetches if needed, the callbacks store data in `Application.Storage`, and the next `onUpdate()` reads from storage. This means there is always a one-cycle delay between initiating a fetch and displaying its results, which is acceptable given the ~1-second update frequency.

**How to validate:**

In the simulator, configure GPS simulation to follow a route. Start a Kayak activity. The data field should:

1. Show "?" initially while the first fetch is pending.
2. After a few seconds, display real wind data from the proxy.
3. As the simulated GPS position moves, new fetches should trigger when distance exceeds 1.5 km.

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

`source/SettingsManager.mc` -- reads settings from `Application.Properties`:

- `function getWindUnits()` returns the selected unit enum value (0=Beaufort, 1=Knots, 2=mph, 3=km/h, 4=m/s).
- `function getWindUnitsString()` returns the unit as a string suitable for the proxy `units` query parameter: `"beaufort"`, `"knots"`, `"mph"`, `"kmh"`, or `"mps"`. This maps from the numeric property value.
- `function getForecastInterval1()` returns the hours offset for the second time slot.
- `function getForecastInterval2()` returns the hours offset for the third time slot, clamped to be greater than interval 1 (if equal or less, set to interval1 + 1, max 6).
- These are read via `Application.Properties.getValue("windUnits")` etc.

`source/WindForceApp.mc` -- implement `onSettingsChanged()` to call `WatchUi.requestUpdate()` so the display refreshes when settings change. Note: because unit conversion and slot selection now happen on the proxy, a unit or interval change does **not** immediately re-render with new values. Instead, `FetchManager.executeFetchCycle()` detects the change on the next `compute()` call and triggers a refetch with the new `units` and `slots` parameters. The display continues showing old data until the refetch completes (typically 1-3 seconds with connectivity).

**Staleness indicator:**

In `source/DisplayRenderer.mc`, modify `formatLayout()` to accept a `fetchTimestamp` parameter. If `Time.now().value() - fetchTimestamp > 1800` (30 minutes), append `*` to the display string. If space permits and the data is very old, append the age in minutes (e.g., `*47m`). The staleness threshold constant (1800 seconds) should be defined in one place. Note: `formatLayout()` needs neither a `units` parameter nor interval selection logic — the proxy returns exactly the display-ready entries with pre-converted values and veer/back symbols.

**Unavailable data display:**

When no forecast data is available for a time slot, render `?(?)` with no direction arrow. When no data is available at all, render `?(?)? ?` for a 1-slot layout. This is handled in `DisplayRenderer.formatLayout()` by checking for null entries.

**Forecast interval mapping:**

The forecast intervals (e.g., 3h, 6h) determine which entries the proxy returns. `FetchManager` builds a `slots` string from the current slot count and interval settings (e.g., `"0,3,6"`) and passes it to the proxy. The proxy selects the forecast entry whose time is closest to `now + offset` hours for each slot. The watch receives exactly the entries it needs to display — no interval mapping logic on the watch side.

**How to validate:**

1. In the simulator, open the app settings and change wind units from Beaufort to Knots. The data field should trigger a refetch and, after a brief delay (1-3 seconds with connectivity), update to show knot values instead of Beaufort numbers. The `units` field in the proxy response should reflect `"knots"`.
2. Change forecast intervals and verify the correct future time slots are shown.
3. Set forecast interval 2 equal to interval 1 and verify it gets clamped to interval1 + 1.
4. To test staleness: in the simulator, disconnect the simulated phone connection, wait, and observe the staleness indicator appearing after 30 minutes (or temporarily lower the threshold for testing).
5. Verify that changing units while offline does not crash — the display should continue showing old-unit data with the staleness indicator until connectivity is restored and a refetch succeeds.

### Milestone 6: Integration Testing, Optimisation, and Deployment

This milestone is the final integration pass. At the end, the data field is ready for side-loading onto a physical Instinct 2X Solar for real-world testing on the water.

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
- Test with no GPS fix (indoor start): display should show "?" until GPS is acquired.
- Test connectivity loss: disconnect simulated phone, verify staleness indicator and cached data display.
- Test look-ahead point usage: move GPS to a position that was previously a look-ahead point and verify cached data is used.
- Test the model run change trigger: manually update KV to simulate a new model run.
- Verify `Application.Storage` persistence: start an activity, stop it, start a new one, and verify old data is available as fallback.

**On-device deployment:**

1. Build a release PRG file: use `Monkey C: Export Project` in VS Code or run the compiler with the `-r` (release) flag.
2. Connect the Instinct 2X Solar via USB.
3. Copy the `.prg` file to the watch's `GARMIN/APPS/` directory.
4. Disconnect the watch. The data field should appear in the data field picker for Kayak activities.
5. Pair the watch with a phone running Garmin Connect Mobile. Verify that settings are configurable from the phone.

**Cloudflare Worker production deployment:**

1. Run `wrangler deploy` from the `proxy/` directory.
2. Verify the endpoints are accessible from the public internet.
3. Test the Worker responds correctly with the curl commands from Milestone 2.
4. Monitor Worker analytics in the Cloudflare dashboard for error rates and request counts.

**How to validate:**

The complete system is validated by performing an actual kayak paddle (or a walk/drive as a substitute) with the Instinct 2X Solar showing the Wind Force data field. The display should update with real Met Eireann wind data as the user moves. Changing settings from the phone should take effect on the next display refresh.

## Concrete Steps

(To be updated as each milestone is implemented. The initial concrete steps for Milestone 1 are below.)

Milestone 1 steps:

    Working directory: c:\Users\alex\repos\garmin_df_wind_force

    1. Create the project directory structure:
       source/
       resources/
       resources/images/
       bin/

    2. Create manifest.xml, monkey.jungle, and all source and resource files
       as described in the Milestone 1 plan above.

    3. Generate a developer key if one does not already exist:
       "C:\Users\alex\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21\bin\connectiq" keygen

    4. Build: Open VS Code, open the garmin_df_wind_force folder, press Ctrl+Shift+P,
       select "Monkey C: Build for Device", choose instinct2x.

    5. If build succeeds, run the simulator:
       Ctrl+Shift+P > "Monkey C: Run on Simulator"

    6. In the simulator, navigate to Activities > Kayak > Data Fields and verify
       Wind Force appears and displays "3(4)N".

## Validation and Acceptance

Each milestone has its own validation section above. The overall acceptance criteria for the complete project:

1. A Kayak activity on the Instinct 2X Solar displays the Wind Force data field with live Met Eireann wind data.
2. The display shows wind speed, gust speed, direction arrow, and veering/backing symbol.
3. Multiple time slots are shown when the data field occupies a wider screen slot.
4. Wind units are configurable (Beaufort, Knots, mph, km/h, m/s) via Garmin Connect Mobile.
5. Forecast intervals for the 2nd and 3rd time slots are configurable (1-6 hours).
6. Data refreshes based on distance moved (>1.5 km), time elapsed (>30 min), or new model run.
7. Look-ahead points provide coverage when the boat moves beyond mobile reception.
8. Stale data is indicated with an asterisk or age in minutes.
9. When no data is available, "?" is shown in place of values.
10. The data field fits within the 32 KB memory limit.
11. The Cloudflare Worker proxy correctly translates Met Eireann XML to compact JSON and caches results.

## Idempotence and Recovery

All source files are created fresh in this plan and tracked in git. Running the build multiple times produces the same output. The Cloudflare Worker can be deployed repeatedly with `wrangler deploy` without side effects (it overwrites the previous version). KV cache entries expire via TTL and do not accumulate unboundedly.

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
        function getInitialView() as [Views]
        function onSettingsChanged() as Void
    }

In `source/WindForceView.mc`:

    class WindForceView extends WatchUi.DataField {
        function initialize() as Void
        function compute(info as Activity.Info) as Void
        function onLayout(dc as Graphics.Dc) as Void
        function onUpdate(dc as Graphics.Dc) as Void
    }

In `source/DisplayRenderer.mc`:

    module DisplayRenderer {
        function renderWindSlot(data as WindData) as String
        function formatLayout(forecasts as Array, fetchTimestamp as Number) as String
        function slotCount(width as Number) as Number
    }

In `source/ForecastService.mc`:

    module ForecastService {
        function fetchForecast(lat as Double, lon as Double, units as String, slots as String, callback as Method) as Void
        function fetchModelStatus(callback as Method) as Void
    }

In `source/FetchManager.mc`:

    module FetchManager {
        function shouldFetch(lat as Double, lon as Double, currentTime as Number) as Boolean
        function computeLookAheadPoints(lat as Double, lon as Double, bearingRad as Float) as Array
        function executeFetchCycle(info as Activity.Info) as Void
    }

In `source/StorageManager.mc`:

    module StorageManager {
        function storeForecast(roundedLat as Float, roundedLon as Float, data as Dictionary) as Void
        function loadForecast(roundedLat as Float, roundedLon as Float) as Dictionary or Null
        function loadNearestForecast(lat as Double, lon as Double) as Dictionary or Null
        function pruneStorage() as Void
    }

In `source/SettingsManager.mc`:

    module SettingsManager {
        function getWindUnits() as Number
        function getWindUnitsString() as String
        function getForecastInterval1() as Number
        function getForecastInterval2() as Number
    }

In `source/WindData.mc`:

    class WindData {
        var time as String
        var windSpeed as Number      // pre-converted integer in the requested unit
        var gustSpeed as Number      // pre-converted integer in the same unit
        var windDir as String        // cardinal/intercardinal label (e.g., "NE")
        var veer as String or Null   // ">" (veering), "<" (backing), or null (first entry)
        function initialize(time as String, windSpeed as Number, gustSpeed as Number, windDir as String, veer as String or Null) as Void
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
        veer: string | null;   // ">" (veering), "<" (backing), or null (first entry)
    }

    interface ForecastResponse {
        model_run: string;
        units: string;         // echoes the requested unit (e.g., "beaufort", "knots")
        forecasts: ForecastEntry[];
    }

    interface ModelStatusResponse {
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
- Cloudflare Wrangler CLI (`npm install -g wrangler`)
- Node.js (for Wrangler and Worker development)
- `fast-xml-parser` npm package (for XML parsing in the Worker, ~50 KB, well within Worker limits)

---

## Revision History

**Revision 2 (2026-03-12):** Addressed all 5 findings from `docs/execution_plan_review.v1.md`:

1. Fixed Wrangler route syntax from `[routes]` to `[[routes]]` (TOML array-of-tables).
2. Added 15-minute throttled polling interval for `/model-status` with `MODEL_STATUS_POLL_INTERVAL_SEC` constant; `executeFetchCycle` now evaluates local triggers first and only polls the proxy on the configured interval.
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
- `proxy/src/types.ts` (Env, ForecastEntry, ForecastResponse, ModelStatusResponse interfaces)
- `proxy/src/met-eireann.ts` (XML fetch + parsing with fast-xml-parser; filters point forecasts where from===to; extracts harmonie model run timestamp)
- `proxy/src/index.ts` (Worker entry point; GET /forecast with coordinate rounding to 0.025 deg, KV caching with 7h TTL; GET /model-status with 15min TTL; CORS headers; input validation)
- Both endpoints tested locally via `wrangler dev`: `/forecast?lat=53.35&lon=-6.26` returns 7 hourly forecasts with wind_mps, wind_deg, wind_beaufort, gust_mps; `/model-status` returns harmonie model run timestamp.
- Error handling verified: missing params (400), invalid coords (400), unknown paths (404).
- KV namespace ID is a placeholder; must run `wrangler kv namespace create FORECAST_CACHE` before deploying.

**Revision 5 (2026-03-13):** Milestone 3 completed. Display engine:

- `source/WindData.mc` (data class: time, windMps, windDeg, windBeaufort, gustMps)
- `source/DisplayRenderer.mc` (module: renderWindSlot, directionLabel, veerBackSymbol, convertSpeed, mpsToBeaufort, formatLayout, slotCount)
- Updated `source/WindForceView.mc` (onLayout determines slot count from dc width; onUpdate calls DisplayRenderer with hardcoded sample data; selectFont auto-picks largest font that fits)
- Layout selection: 1-slot (<90px), 2-slot (90-149px), 3-slot (>=150px)
- Direction: 8 cardinal/intercardinal labels (N, NE, E, SE, S, SW, W, NW)
- Veer/back: ">" for veering (clockwise), "<" for backing (anticlockwise)
- Unit conversion: Beaufort (default), knots, mph, km/h, m/s with mpsToBeaufort lookup for gust
- Verified in simulator: small slot shows "3(4)NE", large slot shows "3(4)NE>5(6)S>3(5)SW"
- Memory: 9.4/28.5kB — ~19kB headroom remaining.

**Revision 6 (2026-03-13):** Architectural change — move calculations from watch to proxy.

Motivation: The Instinct 2X data field has a 32 KB memory limit. Unit conversion, Beaufort lookup, and direction labelling code on the watch consumes memory that could be saved by performing these calculations on the proxy instead. This also simplifies the watch-side code significantly.

Changes across milestones:

- **Milestone 2 (Proxy):** `/forecast` endpoint now accepts an optional `units` query parameter (`beaufort`, `knots`, `mph`, `kmh`, `mps`; default `beaufort`). Raw forecast data is cached in KV in its original m/s + degrees form; unit conversion is applied on the fly before returning the response. Response shape changed: `wind_mps`/`wind_beaufort`/`gust_mps` replaced by `wind_speed` (integer), `gust_speed` (integer), `wind_dir` (cardinal label string). `wind_deg` retained for veer/back. Top-level `units` field added to echo the requested unit.
- **Milestone 3 (Display Engine):** `DisplayRenderer` simplified — removed `convertSpeed()`, `mpsToBeaufort()`, `directionLabel()`. `renderWindSlot()` reads pre-converted values directly. `formatLayout()` no longer takes a `units` parameter. `WindData` fields changed from raw floats to pre-converted integers + direction string.
- **Milestone 4 (Communication):** `ForecastService.fetchForecast()` signature gains a `units` string parameter. `FetchManager.executeFetchCycle()` reads the current unit setting, passes it to `fetchForecast()`, and tracks `_lastFetchedUnits` to detect unit changes as a fetch trigger.
- **Milestone 5 (Settings):** `SettingsManager` gains `getWindUnitsString()` to map the numeric setting to a proxy-compatible string. Unit change triggers a refetch (not a local re-render), with a brief display delay of 1-3 seconds while the new data is fetched.
- **Interfaces:** TypeScript `types.ts` splits into `RawForecastEntry` (internal/cache) and `ForecastEntry` (response). `ForecastResponse` gains a `units` field. Monkey C `WindData` fields changed to `windSpeed`, `gustSpeed`, `windDir`, `windDeg`.
- **Decision Log:** New entry added for this architectural shift.

**Revision 7 (2026-03-13):** Move slot selection and veer/back computation from watch to proxy.

Motivation: Since the proxy already performs unit conversion and direction labelling, it's natural to also have it select the forecast entries for the requested time slots and compute the veer/back symbol between them. This eliminates `veerBackSymbol()` and interval selection logic from the watch, and removes `wind_deg` from the response (no longer needed on the watch).

Changes across milestones:

- **Milestone 2 (Proxy):** `/forecast` endpoint gains a `slots` query parameter (comma-separated hour offsets, e.g., `0,3,6`, max 3 values, default `0`). The proxy selects the closest forecast entry for each offset and computes veer/back between consecutive selected entries. Response field `wind_deg` replaced by `veer` (`">"`, `"<"`, or `null` for the first entry).
- **Milestone 3 (Display Engine):** `DisplayRenderer` further simplified — removed `veerBackSymbol()`. `formatLayout()` no longer takes a `slotCount` parameter or performs interval selection; it iterates the `forecasts` array directly (which already contains exactly the right entries). `WindData` field `windDeg` replaced by `veer` (String or Null).
- **Milestone 4 (Communication):** `ForecastService.fetchForecast()` signature gains a `slots` string parameter. `FetchManager.executeFetchCycle()` builds the `slots` string from the current slot count (from field width) and interval settings, and tracks `_lastFetchedSlots` to detect interval changes as a fetch trigger.
- **Milestone 5 (Settings):** Interval change now triggers a refetch (same as unit change). Forecast interval mapping logic moved from `DisplayRenderer` to the proxy.
- **Interfaces:** `ForecastEntry` field `wind_deg` replaced by `veer: string | null`. Monkey C `WindData` field `windDeg` replaced by `veer as String or Null`. `ForecastService.fetchForecast()` gains `slots` parameter. `DisplayRenderer.formatLayout()` loses `slotCount` parameter; `veerBackSymbol()` removed.
- **Decision Log:** Entry updated to include slot selection and veer/back.
