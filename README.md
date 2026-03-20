# Wind Force - Garmin Connect IQ Data Field

A data field for Garmin Connect IQ that displays live wind forecast data during kayak activities. Supports the Garmin Instinct 2X / 2X Solar and Instinct 2.

## What It Does

Wind Force shows current and forecast wind conditions on your watch during a Kayak activity:

- **Wind speed** and **gust speed** in your choice of units (Beaufort, Knots, mph, km/h, m/s)
- **Wind direction** as compact cardinal labels (N, NE, E, ...)

Depending on the data field slot size, it displays 1 to 3 time slots so you can see how conditions are forecast to change over the next few hours.

```text
3/4NE              Single slot: speed 3, gust 4, NE
3/4NE•5/6S         Two slots: current + 3h forecast
3/4NE•5/6S•3/5SW   Three slots: current + 3h + 6h

*3/4NE•5/6S        Stale data (>30 min old, prefixed with *)
-/-                No forecast yet (1 slot)
-/-•-/-•-/-        No forecast yet (3 slots)
```

Slot count adapts dynamically — if the text overflows the field width even at the smallest system font, slots are reduced until it fits.

When GPS is first acquired (or reacquired after a loss), the data field triggers an immediate background fetch instead of waiting for the next 5-minute polling interval. When an activity ends, the forecast cache is cleared so the next session starts fresh.

## Architecture

```text
Watch (Kayak activity)
  |  compute() saves GPS to Storage
  v
Background Service (every 5 min)
  |  makeWebRequest()
  v
Cloudflare Worker proxy --> Met Eireann HARMONIE API
  |                              |
  +-- KV Cache                   +-- XML forecast data
  |
  v
Watch (Application.Storage) --> Display
```

The watch cannot parse XML directly. A lightweight Cloudflare Worker translates Met Eireann's XML forecasts into compact JSON (~300-500 bytes). Requests route through the paired phone's internet connection via Garmin Connect Mobile.

Connect IQ data fields cannot make direct HTTP requests. A background service (`System.ServiceDelegate`) fires every 5 minutes, reads the current GPS position from `Application.Storage`, fetches forecast data from the proxy, and returns the response to the main process via `Background.exit()`.

## Data Source

Wind forecasts are sourced from [Met Eireann's HARMONIE-AROME model](https://data.gov.ie/en_GB/dataset/met-eireann-forecast-api), which covers Ireland, the UK, and a small area of northern France at approximately 2.5 km grid resolution. The model runs every 6 hours with hourly forecast intervals.

## Supported Devices

- **Garmin Instinct 2X / 2X Solar** (device ID: `instinct2x`) — 176 x 176 px monochrome display
- **Garmin Instinct 2** (device ID: `instinct2`) — 176 x 176 px monochrome display
- 32 KB data field memory limit on both devices

## Project Structure

```text
garmin_df_wind_force/
  manifest.xml          # Connect IQ app manifest
  monkey.jungle         # Build configuration
  source/               # Monkey C source files
    WindForceApp.mc      # App entry, background data handler
    WindForceView.mc     # DataField view and rendering
    WindForceServiceDelegate.mc  # Background service for HTTP
    FetchManager.mc      # GPS position tracking
    DisplayRenderer.mc   # Layout formatting
    StorageManager.mc    # Forecast cache management
    WindData.mc          # Forecast data model
  resources/            # Strings, settings, images
  proxy/                # Cloudflare Worker (TypeScript)
    src/                # Worker source code
    test/               # Unit tests (vitest) and E2E tests (curl)
    wrangler.toml       # Cloudflare deployment config
  test/                 # Monkey C unit tests and GPX test routes
  docs/                 # Requirements and execution plan
```

## Development

### Prerequisites

- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/overview/) 8.2.3+
- VS Code with [Monkey C extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c)
- Node.js (for the proxy; [Wrangler](https://developers.cloudflare.com/workers/wrangler/) is installed as a local devDependency)

### Build & Run (Data Field)

Create a `.env` file in the project root with your SDK paths:

```env
CIQ_HOME = $(HOME)/AppData/Roaming/Garmin/ConnectIQ
SDK_HOME = $(CIQ_HOME)/Sdks/connectiq-sdk-win-8.2.3-2025-08-11-cac5b3b21
KEY      = /c/Users/<you>/.ssh/developer_key
```

```bash
make build    # Debug build (strict type checking, -l 3)
make dist     # Release IQ package for all devices
make clean    # Remove build artifacts
make info     # Show app version, device targets, SDK path
```

Or use VS Code:

1. `Ctrl+Shift+P` > **Monkey C: Build for Device** > select `instinct2x`
2. `Ctrl+Shift+P` > **Monkey C: Run on Simulator**
3. In the simulator: load `test/dublin_bay.gpx`, start playback, then **Simulation > Trigger Background Event** to fetch data

### Side-loading to Device

1. `make dist` to build the release IQ package
2. Connect your Instinct 2 / 2X via USB
3. Copy `bin/WindForce.prg` (from inside the IQ, or the device-specific build) to the watch's `GARMIN/APPS/` directory
4. Disconnect the watch — Wind Force appears in the data field picker for Kayak activities

### Proxy Development

```bash
cd proxy
npm install
npm run dev         # Local development (wrangler dev)
npm run deploy      # Deploy to Cloudflare (wrangler deploy)
```

### Testing

#### Watch App (Monkey C)

```bash
# Build with unit tests enabled
monkeyc --unit-test -d instinct2x -f monkey.jungle -o bin/WindForce-test.prg -y ~/.ssh/developer_key

# Run in simulator (25 tests)
connectiq &
monkeydo bin/WindForce-test.prg instinct2x -t
```

Tests cover `StorageManager` (coordinate rounding, key parsing, distance calculation), `DisplayRenderer` (slot count thresholds and wind slot formatting), and `WindData` initialization. The `(:test)` annotation strips all test code from release builds — zero impact on the 32 KB memory budget.

#### Proxy (TypeScript)

```bash
cd proxy
npm test            # Unit tests (vitest, 41 tests, runs offline)
npm run test:e2e    # E2E tests (curl against deployed proxy, 34 tests)
```

The E2E script accepts an optional base URL for local testing:

```bash
bash proxy/test/e2e.sh http://localhost:8787   # against npm run dev
```

## Configuration

Settings are configurable via Garmin Connect Mobile or Garmin Express:

| Setting | Options | Default |
| ------- | ------- | ------- |
| Wind units | Beaufort, Knots, mph, km/h, m/s | Beaufort |
| Immediate Interval | 1h - 6h | 3h |
| Imminent Interval | 1h - 6h | 6h |

## Wind Speed Reference

| Bft | Description     | knots | mph   | km/h    | m/s       |
|----:|-----------------|------:|------:|--------:|----------:|
|   0 | Calm            |   < 1 |   < 1 |     < 2 | < 0.3     |
|   1 | Light air       |   1–3 |   1–3 |    2–5  | 0.3–1.5   |
|   2 | Light breeze    |   4–6 |   4–7 |   6–11  | 1.6–3.3   |
|   3 | Gentle breeze   |  7–10 |  8–12 |  12–19  | 3.4–5.4   |
|   4 | Moderate breeze | 11–16 | 13–18 |  20–28  | 5.5–7.9   |
|   5 | Fresh breeze    | 17–21 | 19–24 |  29–38  | 8.0–10.7  |
|   6 | Strong breeze   | 22–27 | 25–31 |  39–49  | 10.8–13.8 |
|   7 | Near gale       | 28–33 | 32–38 |  50–61  | 13.9–17.1 |
|   8 | Gale            | 34–40 | 39–46 |  62–74  | 17.2–20.7 |
|   9 | Strong gale     | 41–47 | 47–54 |  75–88  | 20.8–24.4 |
|  10 | Storm           | 48–55 | 55–63 |  89–102 | 24.5–28.4 |
|  11 | Violent storm   | 56–63 | 64–73 | 103–117 | 28.5–32.6 |
|  12 | Hurricane       |  ≥ 64 |  ≥ 74 |   ≥ 118 | ≥ 32.7    |

All values are displayed as rounded integers on the watch. Beaufort thresholds match the WMO standard scale used by the proxy's `mpsToBeaufort()` conversion.

## License

GNU General Public License v2 or later. See [LICENSE](LICENSE).

## Author

Yak Shaver - [kayakshaver.com](https://www.kayakshaver.com)
