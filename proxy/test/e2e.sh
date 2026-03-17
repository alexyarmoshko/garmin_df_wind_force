#!/usr/bin/env bash
# End-to-end tests for the deployed Wind Force proxy.
# Usage: bash proxy/test/e2e.sh [base_url]
# Default base URL: https://api-wind-force.kayakshaver.com

BASE="${1:-https://api-wind-force.kayakshaver.com}"
CURL="curl -s --max-time 15"
PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

# ── Tests ─────────────────────────────────────────────────────────────

echo "Wind Force Proxy E2E Tests"
echo "Base URL: $BASE"
echo ""

# --- Routing & error handling ---

echo "=== Routing & error handling ==="

status=$($CURL -o /dev/null -w '%{http_code}' "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0")
if [[ "$status" == "200" ]]; then pass "GET valid forecast returns 200"; else fail "GET valid forecast — expected 200, got $status"; fi

# Unknown paths may return 403 (Cloudflare route restriction) or 404 (worker)
status=$($CURL -o /dev/null -w '%{http_code}' "$BASE/v1/unknown")
if [[ "$status" == "404" || "$status" == "403" ]]; then pass "GET unknown path returns $status (blocked)"; else fail "GET unknown path — expected 403 or 404, got $status"; fi

status=$($CURL -o /dev/null -w '%{http_code}' -X POST "$BASE/v1/forecast?lat=53.35&lon=-6.26")
if [[ "$status" == "405" ]]; then pass "POST returns 405"; else fail "POST — expected 405, got $status"; fi

status=$($CURL -o /dev/null -w '%{http_code}' -X OPTIONS "$BASE/v1/forecast")
if [[ "$status" == "200" ]]; then pass "OPTIONS returns 200 (CORS preflight)"; else fail "OPTIONS — expected 200, got $status"; fi

status=$($CURL -o /dev/null -w '%{http_code}' "$BASE/v1/forecast")
if [[ "$status" == "400" ]]; then pass "Missing params returns 400"; else fail "Missing params — expected 400, got $status"; fi

body=$($CURL "$BASE/v1/forecast?lat=53.35")
if echo "$body" | grep -q "Missing lat or lon"; then pass "Missing lon returns error message"; else fail "Missing lon — unexpected: $body"; fi

status=$($CURL -o /dev/null -w '%{http_code}' "$BASE/v1/forecast?lat=invalid&lon=-6.26")
if [[ "$status" == "400" ]]; then pass "Invalid lat returns 400"; else fail "Invalid lat — expected 400, got $status"; fi

status=$($CURL -o /dev/null -w '%{http_code}' "$BASE/v1/forecast?lat=91&lon=-6.26")
if [[ "$status" == "400" ]]; then pass "Out-of-range lat (91) returns 400"; else fail "Out-of-range lat — expected 400, got $status"; fi

status=$($CURL -o /dev/null -w '%{http_code}' "$BASE/v1/forecast?lat=53.35&lon=181")
if [[ "$status" == "400" ]]; then pass "Out-of-range lon (181) returns 400"; else fail "Out-of-range lon — expected 400, got $status"; fi

# --- Response structure ---

echo ""
echo "=== Response structure ==="

body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0")

if echo "$body" | grep -q '"api_version":"v1"'; then pass "api_version is v1"; else fail "api_version missing — $body"; fi

if echo "$body" | grep -qE '"model_run":"[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then pass "model_run is a timestamp"; else fail "model_run missing — $body"; fi

if echo "$body" | grep -q '"units":"beaufort"'; then pass "units field echoed"; else fail "units field missing — $body"; fi

if echo "$body" | grep -q '"forecasts":\['; then pass "forecasts array present"; else fail "forecasts array missing — $body"; fi

if echo "$body" | grep -qE '"wind_speed":[0-9]'; then pass "wind_speed present"; else fail "wind_speed missing — $body"; fi

if echo "$body" | grep -qE '"gust_speed":[0-9]'; then pass "gust_speed present"; else fail "gust_speed missing — $body"; fi

if echo "$body" | grep -qE '"wind_dir":"[NESW]'; then pass "wind_dir is a cardinal label"; else fail "wind_dir missing — $body"; fi

if echo "$body" | grep -qE '"time":"[0-9]{4}-'; then pass "time is a timestamp"; else fail "time missing — $body"; fi

# --- Unit conversions ---

echo ""
echo "=== Unit conversions ==="

for unit in beaufort knots mph kmh mps; do
  body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=$unit&slots=0")
  if echo "$body" | grep -q "\"units\":\"$unit\""; then pass "$unit — units field correct"; else fail "$unit — expected units=$unit — $body"; fi
done

body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=invalid&slots=0")
if echo "$body" | grep -q '"units":"beaufort"'; then pass "Invalid unit defaults to beaufort"; else fail "Invalid unit — expected beaufort — $body"; fi

# Verify knots > beaufort for same data (knots values are always larger)
bft=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0")
kn=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=knots&slots=0")
bft_ws=$(echo "$bft" | grep -oE '"wind_speed":[0-9]+' | head -1 | grep -oE '[0-9]+$')
kn_ws=$(echo "$kn" | grep -oE '"wind_speed":[0-9]+' | head -1 | grep -oE '[0-9]+$')
if [[ -n "${bft_ws:-}" && -n "${kn_ws:-}" && "$kn_ws" -gt "$bft_ws" ]]; then
  pass "Knots wind_speed ($kn_ws) > Beaufort wind_speed ($bft_ws)"
else
  fail "Expected knots (${kn_ws:-?}) > beaufort (${bft_ws:-?})"
fi

# Verify kmh >= mph for same data
mph_body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=mph&slots=0")
kmh_body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=kmh&slots=0")
mph_ws=$(echo "$mph_body" | grep -oE '"wind_speed":[0-9]+' | head -1 | grep -oE '[0-9]+$')
kmh_ws=$(echo "$kmh_body" | grep -oE '"wind_speed":[0-9]+' | head -1 | grep -oE '[0-9]+$')
if [[ -n "${kmh_ws:-}" && -n "${mph_ws:-}" && "$kmh_ws" -ge "$mph_ws" ]]; then
  pass "Kmh wind_speed ($kmh_ws) >= Mph wind_speed ($mph_ws)"
else
  fail "Expected kmh (${kmh_ws:-?}) >= mph (${mph_ws:-?})"
fi

# --- Slot selection ---

echo ""
echo "=== Slot selection ==="

count_forecasts() {
  echo "$1" | grep -oE '"time":"' | wc -l | tr -d ' '
}

body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0")
n=$(count_forecasts "$body")
if [[ "$n" -eq 1 ]]; then pass "slots=0 returns 1 forecast"; else fail "slots=0 — expected 1, got $n"; fi

body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0,6")
n=$(count_forecasts "$body")
if [[ "$n" -eq 2 ]]; then pass "slots=0,6 returns 2 forecasts"; else fail "slots=0,6 — expected 2, got $n"; fi

body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0,3,6")
n=$(count_forecasts "$body")
if [[ "$n" -eq 3 ]]; then pass "slots=0,3,6 returns 3 forecasts"; else fail "slots=0,3,6 — expected 3, got $n"; fi

body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=beaufort")
n=$(count_forecasts "$body")
if [[ "$n" -eq 1 ]]; then pass "Default slots returns 1 forecast"; else fail "Default slots — expected 1, got $n"; fi

# 3-slot response should have different times for slot 0 vs slot 2
body=$($CURL "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0,3,6")
times=$(echo "$body" | grep -oE '"time":"[^"]+"' | sort -u | wc -l | tr -d ' ')
if [[ "$times" -ge 2 ]]; then
  pass "3-slot response has at least 2 distinct timestamps ($times)"
else
  fail "3-slot response has only $times distinct timestamp(s)"
fi

# --- Coordinate rounding ---

echo ""
echo "=== Coordinate rounding ==="

body1=$($CURL "$BASE/v1/forecast?lat=53.340&lon=-6.220&units=beaufort&slots=0")
body2=$($CURL "$BASE/v1/forecast?lat=53.341&lon=-6.221&units=beaufort&slots=0")
ws1=$(echo "$body1" | grep -oE '"wind_speed":[0-9]+' | head -1 | grep -oE '[0-9]+$')
ws2=$(echo "$body2" | grep -oE '"wind_speed":[0-9]+' | head -1 | grep -oE '[0-9]+$')
if [[ -n "${ws1:-}" && "${ws1:-}" == "${ws2:-}" ]]; then
  pass "Nearby coords round to same grid point (wind_speed=$ws1)"
else
  fail "Nearby coords returned different wind_speed: ${ws1:-?} vs ${ws2:-?}"
fi

# --- CORS headers ---

echo ""
echo "=== CORS headers ==="

headers=$($CURL -D - -o /dev/null "$BASE/v1/forecast?lat=53.35&lon=-6.26&units=beaufort&slots=0" 2>/dev/null)

if echo "$headers" | grep -qi 'access-control-allow-origin.*\*'; then
  pass "CORS Access-Control-Allow-Origin: * present"
else
  fail "CORS header missing or not *"
fi

if echo "$headers" | grep -qi 'content-type.*application/json'; then
  pass "Content-Type: application/json present"
else
  fail "Content-Type header missing or not JSON"
fi

opt_headers=$($CURL -D - -o /dev/null -X OPTIONS "$BASE/v1/forecast" 2>/dev/null)
if echo "$opt_headers" | grep -qi 'access-control-allow-methods'; then
  pass "OPTIONS includes Access-Control-Allow-Methods"
else
  fail "OPTIONS missing Allow-Methods header"
fi

# ── Summary ───────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
