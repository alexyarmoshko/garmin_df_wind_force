# Wind Force - Garmin Connect IQ Data Field

A data field for Garmin Connect IQ that displays live wind forecast data during kayak activities. Designed for the Garmin Instinct 2X Solar.

## What It Does

Wind Force shows current and forecast wind conditions on your watch during a Kayak activity:

- **Wind speed** and **gust speed** in your choice of units (Beaufort, Knots, mph, km/h, m/s)
- **Wind direction** as a compass arrow
- **Veering/backing** indicator showing how the wind direction is shifting

Depending on the data field slot size, it displays 1 to 3 time slots so you can see how conditions are forecast to change over the next few hours.

```
3(4)NE>        Single slot: speed 3, gust 4, NE, veering
3(4)NE>5(6)S   Two slots: current + 3h forecast
3(4)NE>5(6)S>3(5)SW   Three slots: current + 3h + 6h
```

## Architecture

```
Watch (Kayak activity) --> Cloudflare Worker proxy --> Met Eireann HARMONIE API
       ^                          |
       |                     KV Cache
       +-- Application.Storage (offline fallback)
```

The watch cannot parse XML directly. A lightweight Cloudflare Worker translates Met Eireann's XML forecasts into compact JSON (~300-500 bytes). Requests route through the paired phone's internet connection via Garmin Connect Mobile.

## Data Source

Wind forecasts are sourced from [Met Eireann's HARMONIE-AROME model](https://data.gov.ie/en_GB/dataset/met-eireann-forecast-api), which covers Ireland, the UK, and a small area of northern France at approximately 2.5 km grid resolution. The model runs every 6 hours with hourly forecast intervals.

## Target Device

- **Garmin Instinct 2X Solar** (device ID: `instinct2x`)
- 176 x 176 px monochrome display
- 32 KB data field memory limit

## Project Structure

```
garmin_df_wind_force/
  manifest.xml          # Connect IQ app manifest
  monkey.jungle         # Build configuration
  source/               # Monkey C source files
  resources/            # Strings, settings, images
  proxy/                # Cloudflare Worker (TypeScript)
    src/                # Worker source code
    wrangler.toml       # Cloudflare deployment config
  docs/                 # Requirements and execution plan
```

## Development

### Prerequisites

- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/overview/) 8.2.3+
- VS Code with [Monkey C extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c)
- Node.js and [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/) (for the proxy)

### Build & Run (Data Field)

1. Open the project in VS Code
2. `Ctrl+Shift+P` > **Monkey C: Build for Device** > select `instinct2x`
3. `Ctrl+Shift+P` > **Monkey C: Run on Simulator**

### Proxy Development

```bash
cd proxy
npm install
wrangler dev        # Local development
wrangler deploy     # Deploy to Cloudflare
```

## Configuration

Settings are configurable via Garmin Connect Mobile or Garmin Express:

| Setting | Options | Default |
|---------|---------|---------|
| Wind units | Beaufort, Knots, mph, km/h, m/s | Beaufort |
| Forecast interval 1 | 1h - 6h | 3h |
| Forecast interval 2 | 1h - 6h | 6h |

## License

GNU General Public License v2 or later. See [LICENSE](LICENSE).

## Author

Yak Shaver - [kayakshaver.com](https://www.kayakshaver.com)