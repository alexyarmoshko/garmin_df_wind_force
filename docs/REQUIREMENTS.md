# Wind Force Garmin Connect IQ Data Field

This is a data field for Garmin Connect IQ that should be initially available for Garmin Instinct 2X Solar
smart watch and later may be expanded to the later models.

This data field should be selectable to be shown for Kayak activity. 

## Data source

[Marine terminology](https://www.met.ie/forecasts/marine-inland-lakes/sea-area-forecast-terminology)
[Met Éireann forecast API](https://data.gov.ie/en_GB/dataset/met-eireann-forecast-api/resource/5d156b15-38b8-4de9-921b-0ffc8704c88e)

The Met Éireann API returns a point forecast in XML for any given latitude/longitude. The underlying
HARMONIE-AROME model has approximately 2.5 km grid resolution. The model runs every 6 hours
(00, 06, 12, 18 UTC), with data output in hourly intervals out to 90 hours, then coarser intervals
beyond that. The forecast for a given point does not change between model runs.

The API endpoint is:
`http://openaccess.pf.api.met.ie/metno-wdb2ts/locationforecast?lat={lat};long={lon}`

Per-point response fields used by this data field: `windSpeed` (mps, beaufort), `windDirection` (deg, name),
`windGust` (mps), `precipitation` (probability, optional for future use).

## Field Structure/Layouts

```text
W/GD
W1/G1D1<W2/G2D2
W1/G1D1<W2/G2D2<W3/G3D3

Examples:

3/4NE
3/4NE<5/6S
3/4NE<5/6S<3/5SW
```

W - wind speed (Beaufort Scale|Knots|mp/h|km/h|m/s)
G - wind gust speed (Beaufort Scale|Knots|mp/h|km/h|m/s)
D - wind direction as cardinal/intercardinal label (N, NE, E, SE, S, SW, W, NW)
`<` - literal separator between adjacent time slots

The layout shown depends on the data field position selected by the user on the activity screen.
All layouts occupy a single line.

## User Configuration

The following settings are configurable by the user via Garmin Connect Mobile or Garmin Express:

| Setting | Options | Default |
|---|---|---|
| Wind units | Beaufort, Knots, mph, km/h, m/s | Beaufort |
| Forecast interval 1 (S2) | 1h, 2h, 3h, 4h, 5h, 6h | 3h |
| Forecast interval 2 (S3) | 1h, 2h, 3h, 4h, 5h, 6h | 6h |

Forecast interval 2 must be greater than forecast interval 1. When settings change,
`onSettingsChanged()` validates the pair and writes corrected values back to
`Application.Properties` so the Garmin Connect settings UI reflects the effective
configuration. If interval 2 is less than or equal to interval 1, it is corrected to
interval 1 + 1h. If interval 1 is 6h (leaving no valid interval 2), interval 1 is
reduced to 5h and interval 2 set to 6h. The background service retains its own
normalization as a safety net, though its behaviour differs in the `interval1 = 6`
edge case: rather than reducing interval 1, it suppresses the third slot and emits
a 2-slot request.

Implementation note (2026-03-14):

- The current background-service architecture reads these settings from `Application.Properties` in the service process.
- This must be validated on a physical device during an active activity to confirm that settings changes propagate to the background service without requiring an activity restart.

## Architecture

The watch cannot parse XML directly. A lightweight proxy backend translates the Met Éireann
XML responses into compact JSON. Connect IQ data fields cannot call `makeWebRequest()`
directly — calls silently fail. Instead, a background service (`System.ServiceDelegate`)
fires every 5 minutes via `Background.registerForTemporalEvent()`, reads the current GPS
position from `Application.Storage`, and fetches forecast data from the proxy. The response
is returned to the foreground process via `Background.exit()` and stored for display.
Requests route through the paired phone's internet connection via Garmin Connect Mobile.

```text
Watch Data Field (during Kayak activity)
  → compute() reads GPS from Activity.Info, saves to Application.Storage
  → Background Service fires every 5 minutes
    → reads GPS position from Application.Storage
    → reads settings from Application.Properties
    → makeWebRequest() to Cloudflare Worker proxy
    → CF Worker checks KV cache
       → hit: returns cached JSON
       → miss: fetches XML from Met Éireann, parses, caches in KV, returns JSON
    → Background.exit() returns response to foreground
  → foreground validates response against current settings
  → stores forecast in Application.Storage, updates display
  → on failure or stale settings: displays last valid cached data with staleness indicator
```

### Proxy Backend (Cloudflare Worker)

Hosted on Cloudflare Workers free tier (100,000 requests/day, KV storage included).

**Endpoints:**

`GET /v1/forecast?lat={lat}&lon={lon}&units={units}&slots={slots}`
- Rounds coordinates to the nearest ~0.025° (~2.5 km) to maximise cache hits and match
  the HARMONIE model grid resolution
- `units`: `beaufort` (default), `knots`, `mph`, `kmh`, `mps`
- `slots`: comma-separated hour offsets (e.g., `0,3,6`; max 3; default `0`)
- Returns JSON with pre-converted wind data for the requested time slots:

```json
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
    }
  ]
}
```

- KV cache key: `{rounded_lat}_{rounded_lon}_{model_run}`
- KV TTL: 7 hours (model run interval is 6h, with buffer)

### Proxy JSON Response Size

The response should contain hourly forecast entries from now out to the maximum configured
forecast interval (6h max), so at most 7 entries. At approximately 50 bytes per entry plus
overhead, the total response is approximately 300–500 bytes. This is well within Connect IQ's
web request limits.

## Data Coverage and Fetch Strategy

### Grid Model

Forecast data is requested for individual grid points. Because the HARMONIE model resolution
is approximately 2.5 km, points closer together than this yield interpolated data from the
same grid cells. The minimum useful spacing between fetch points is therefore ~2.5 km.

### Fetch Points

Implementation status note (2026-03-14):

- The current Milestone 4 implementation had to pivot to a background service because Connect IQ data fields cannot call `makeWebRequest()` directly.
- Current-position fetching and nearest-grid offline fallback are implemented.
- Look-ahead fetching was deferred during the background-service rework and is not part of the current delivered behaviour.
- The look-ahead behaviour described below remains desired follow-up scope unless it is formally re-prioritised.

On each fetch cycle, the data field requests forecasts for:

- **Current position** — the boat's current GPS location (always fetched)
- **Look-ahead points** — 2 points along the current bearing of travel, at ~2.5 km intervals
  ahead of the current position (fetched when connectivity allows, providing coverage in case
  signal is lost further along the route)

The current bearing is derived from the last several GPS fixes, smoothed to account for
paddle stroke wobble and drift. `Activity.Info` provides bearing directly when available.

The look-ahead points serve as insurance: if the boat moves into an area with no mobile
reception, the previously fetched forecast for that approximate area is already cached on
the watch and can be displayed.

### Fetch Triggers

Implementation status note (2026-03-14):

- The original design below describes distance/time/model-run driven fetches.
- The current implementation uses a 5-minute background temporal event as the only fetch trigger, because foreground `compute()` cannot perform HTTP requests on this platform.
- The model-run and look-ahead behaviour described below should therefore be treated as future target behaviour, not current delivered behaviour.

Three independent triggers determine when the data field initiates a new fetch. Any one
of them firing is sufficient.

| Trigger | Condition | What is fetched |
|---|---|---|
| **Distance** | Boat has moved >1.5 km from the position of the last fetch | Current position + look-ahead points along current bearing |
| **Time** | >30 minutes since the last successful fetch | Current position only (re-fetch at same location to get latest hourly slot) |
| **Model run** | The `/v1/forecast` response contains a newer `model_run` than the one in cache | Automatically picked up on the next background fetch cycle |

The proxy resolves the current model run internally when handling `/v1/forecast` requests. New model runs are detected automatically without a separate endpoint call.

### Fetch Sequence

The background service fires every 5 minutes and:

1. Reads the current GPS position from `Application.Storage`
2. Calls `/v1/forecast?lat={lat}&lon={lon}&units={units}&slots={slots}`
3. Returns the response to the foreground via `Background.exit()`
4. The foreground stores the data in `Application.Storage` and updates the display

### Initial Launch

When the activity starts and the data field initialises:

1. `getInitialView()` registers a 5-minute background temporal event via
   `Background.registerForTemporalEvent(Duration(300))`. Using a Duration means the first
   event fires immediately if more than 5 minutes have elapsed since the last run.
2. `compute()` begins saving the current GPS position to `Application.Storage` on each call.
3. The first background event reads the saved position and fetches from the proxy.
4. Until the first successful fetch, the display shows `NO GPS` (no fix yet) or `---`
   (GPS available but no cached forecast).

### Unavailable Data Display

When no GPS fix is available, the field displays `NO GPS`. When GPS is available but no
forecast is cached for the current or nearest grid point, the field displays `---`.

## Staleness and Connectivity Loss

### Staleness Indicator

When the displayed data is older than 30 minutes, the display is prefixed with `*`
(e.g., `*3/4NE<5/6S`).

### Connectivity Loss Behaviour

When `makeWebRequest()` fails (no mobile reception, phone disconnected, proxy unreachable):

1. Display the last successfully fetched data for the nearest cached grid point within 2.5 km
   of the current position
2. Show the staleness indicator
3. Continue triggering fetch attempts at normal intervals — they will succeed when connectivity
   is restored
4. If the boat has moved into a position covered by a previously fetched look-ahead point,
   use that look-ahead data instead (it is likely more spatially relevant even if slightly
   older)

### Look-Ahead Coverage Estimate

At approximately 3 knots (~5.5 km/h), 2 look-ahead points at 2.5 km spacing provide roughly
55 minutes of forward coverage under total signal loss. Combined with the 30-minute time
trigger, the user is unlikely to see data more than approximately 45 minutes old unless in a
prolonged dead zone.

## Constraints and Limitations

- The Met Éireann API covers Ireland, the UK, and a small area of northern France only
- HARMONIE model resolution is ~2.5 km; finer spatial precision is not available
- Connect IQ `makeWebRequest()` routes through the paired phone; if the phone is not connected
  to the watch via Bluetooth, no requests can be made
- Connect IQ web request payload size is limited; responses should be kept under 4 KB
- `Application.Storage` on Instinct 2X has limited capacity; only the most recent set of
  grid point forecasts should be retained (current position + look-ahead points)
- Tidal flows are out of scope — they are too complex and localised for this data field
- The data field requires the Met Éireann open data licence attribution to be displayed
  if the data is made publicly visible; for personal use on a watch this is not applicable,
  but should be noted for any future distribution via the Connect IQ Store

## Future Considerations

- Precipitation probability display (additional data field or overlay)
- Offshore perpendicular look-ahead point (1 point perpendicular to bearing, seaward)
- Multiple device support (Fenix, Venu, etc.)
- Configurable fetch intervals and look-ahead distance
- Alternative data sources for use outside Met Éireann coverage area
