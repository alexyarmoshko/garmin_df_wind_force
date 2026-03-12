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
S(G)[↑|↗|→|↘|↓|↙|←|↖][⟲|⟳]
S1(G1)[↑|↗|→|↘|↓|↙|←|↖][⟲|⟳]S2(G2)[↑|↗|→|↘|↓|↙|←|↖]
S1(G1)[↑|↗|→|↘|↓|↙|←|↖][⟲|⟳]S2(G2)[↑|↗|→|↘|↓|↙|←|↖][⟲|⟳]S3(G3)[↑|↗|→|↘|↓|↙|←|↖]

Examples:

3(4)↗⟳
3(4)↗⟳5(6)↓
3(4)↗⟳5(6)↓⟳3(5)↙
```

S - wind speed (Beaufort Scale|Knots|mp/h|km/h|m/s)
G - wind gust speed (Beaufort Scale|Knots|mp/h|km/h|m/s)
`↑|↗|→|↘|↓|↙|←|↖` - wind direction (rounded to the nearest 0,45,90,135,180,225,270,315,360 degree; 0 == 360).

`⟲|⟳` - veering (⟳, clockwise shift) or backing (⟲, anticlockwise shift) between adjacent time slots.

The layout shown depends on the data field position selected by the user on the activity screen.
All layouts occupy a single line. When more than one time slot is displayed, the veering/backing
symbol between slots indicates the directional change from the earlier slot to the later one.

When only a single time slot is displayed (1-value layout), the veering/backing symbol indicates
the directional change between the current observation and the next configured forecast interval.

## User Configuration

The following settings are configurable by the user via Garmin Connect Mobile or Garmin Express:

| Setting | Options | Default |
|---|---|---|
| Wind units | Beaufort, Knots, mph, km/h, m/s | Beaufort |
| Forecast interval 1 (S2) | 1h, 2h, 3h, 4h, 5h, 6h | 3h |
| Forecast interval 2 (S3) | 1h, 2h, 3h, 4h, 5h, 6h | 6h |

Forecast interval 2 must be greater than forecast interval 1. If the user sets them equal or
interval 2 less than interval 1, interval 2 should be clamped to interval 1 + 1h (or the
maximum of 6h, whichever is smaller).

## Architecture

The watch cannot parse XML directly. A lightweight proxy backend translates the Met Éireann
XML responses into compact JSON. The data field makes HTTP requests to this proxy via
Connect IQ's `Communications.makeWebRequest()`, which routes transparently through the paired
Android phone's internet connection via Garmin Connect. No companion Android app is required.

```text
Watch Data Field (during Kayak activity)
  → reads GPS position from Activity.Info
  → determines whether a fetch is needed (see Fetch Strategy)
  → makeWebRequest() to Cloudflare Worker proxy
  → CF Worker checks KV cache
     → hit: returns cached JSON
     → miss: fetches XML from Met Éireann, parses, caches in KV, returns JSON
  → watch displays data and stores in Application.Storage
  → on request failure: displays last cached data with staleness indicator
```

### Proxy Backend (Cloudflare Worker)

Hosted on Cloudflare Workers free tier (100,000 requests/day, KV storage included).

**Endpoints:**

`GET /forecast?lat={lat}&lon={lon}`
- Rounds coordinates to the nearest ~0.025° (~2.5 km) to maximise cache hits and match
  the HARMONIE model grid resolution
- Returns JSON containing hourly wind data for the next 6 hours:

```json
{
  "model_run": "2026-03-12T06:00:00Z",
  "forecasts": [
    {
      "time": "2026-03-12T10:00:00Z",
      "wind_mps": 7.2,
      "wind_deg": 195,
      "wind_beaufort": 4,
      "gust_mps": 11.3
    }
  ]
}
```

- KV cache key: `{rounded_lat}_{rounded_lon}_{model_run}`
- KV TTL: 7 hours (model run interval is 6h, with buffer)

`GET /model-status`
- Returns the timestamp of the latest model run available (~50 bytes)
- Used by the watch to cheaply detect whether cached data is stale

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

Three independent triggers determine when the data field initiates a new fetch. Any one
of them firing is sufficient.

| Trigger | Condition | What is fetched |
|---|---|---|
| **Distance** | Boat has moved >1.5 km from the position of the last fetch | Current position + look-ahead points along current bearing |
| **Time** | >30 minutes since the last successful fetch | Current position only (re-fetch at same location to get latest hourly slot) |
| **Model run** | `/model-status` reports a newer model run than the one in cache | Current position + look-ahead points (all cached data is from the old run) |

The model-status check is lightweight (~50 bytes) and should be performed before each full
forecast fetch to avoid unnecessary requests when the model run has not changed. It can also
be polled independently at a lower frequency (e.g. every 15 minutes) to detect new model runs
while stationary.

### Fetch Sequence

On each fetch cycle:

1. Call `/model-status` to get current model run timestamp
2. If model run matches cached data and neither distance nor time trigger has fired, do nothing
3. Otherwise, call `/forecast?lat={lat}&lon={lon}` for the current position
4. If connectivity permits, call `/forecast` for each look-ahead point
5. Store all responses in `Application.Storage` keyed by rounded grid coordinates
6. Update the display with the current position's data

Look-ahead fetches (step 4) are best-effort. If any fail, the data field continues with
whatever data it has. The current position fetch (step 3) is the priority.

### Initial Launch

When the activity starts and the data field initialises:

1. Immediately attempt to fetch the current position forecast
2. Fetch look-ahead points along the initial bearing (if bearing is not yet established,
   skip look-ahead until sufficient GPS fixes are available)
3. If the initial fetch fails entirely, display `?` in place of values, or fall back to the
   last persisted data from `Application.Storage` from a previous activity session, with a
   staleness indicator

### Unavailable Data Display

When data is unavailable for any value (no cached data, fetch failed, no GPS fix yet),
`?` is shown in place of that value. For example: `?(?)? ?` for a single-slot layout with
no data at all, or `3(4)↗ ⟳ ?(?)? ` if the current slot has data but the forecast slot
does not.

## Staleness and Connectivity Loss

### Staleness Indicator

When the displayed data is older than 30 minutes, a staleness indicator should be shown.
This could be an asterisk (`*`) appended to the display, or the age in minutes (e.g. `47m`)
if screen space permits.

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