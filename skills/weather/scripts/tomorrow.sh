#!/usr/bin/env bash
set -uo pipefail

CITY_RAW="${1:-Villa Urquiza,Buenos Aires}"
CITY_ENCODED="$(python3 - "$CITY_RAW" <<'PY'
import sys
import urllib.parse

city = (sys.argv[1] or "Villa Urquiza,Buenos Aires").strip()
print(urllib.parse.quote_plus(city, safe=","))
PY
)"

fetch_json() {
  curl -fsS --connect-timeout 5 --max-time 12 "https://wttr.in/${CITY_ENCODED}?format=j1" 2>/dev/null
}

json_payload=""
if ! json_payload="$(fetch_json)"; then
  sleep 1
  if ! json_payload="$(fetch_json)"; then
    printf 'WEATHER_ERROR\n'
    exit 0
  fi
fi

tmp_json="$(mktemp)"
trap 'rm -f "$tmp_json"' EXIT
printf '%s' "$json_payload" > "$tmp_json"

if ! python3 - "$CITY_RAW" "$tmp_json" <<'PY'
import json
import sys

city = (sys.argv[1] or "Villa Urquiza,Buenos Aires").strip()
path = sys.argv[2]

def normalize_city(value: str) -> str:
    parts = [part.strip() for part in value.split(",") if part.strip()]
    if not parts:
        return "Villa Urquiza"
    return parts[0]

def normalize_desc(value: str) -> str:
    text = (value or "").strip()
    lower = text.lower()
    mapping = [
        (("sun", "clear"), "soleado"),
        (("partly", "patchy"), "algo nublado"),
        (("cloud", "overcast"), "nublado"),
        (("rain", "drizzle", "shower"), "lluvia"),
        (("thunder", "storm"), "tormenta"),
        (("fog", "mist"), "niebla"),
        (("wind", "breezy"), "ventoso"),
    ]
    for needles, label in mapping:
        if any(needle in lower for needle in needles):
            return label
    return text or "sin detalle"

with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

days = data.get("weather") or [{}]
weather = days[1] if len(days) > 1 else days[0]
hourly = weather.get("hourly") or [{}]
mid = hourly[len(hourly) // 2] if hourly else {}
rain = max(int(item.get("chanceofrain", 0) or 0) for item in hourly) if hourly else 0
humidity_values = [int(item.get("humidity", 0) or 0) for item in hourly if item.get("humidity") not in (None, "")]
wind_values = [int(item.get("windspeedKmph", 0) or 0) for item in hourly if item.get("windspeedKmph") not in (None, "")]
avg_humidity = round(sum(humidity_values) / len(humidity_values)) if humidity_values else "?"
avg_wind = round(sum(wind_values) / len(wind_values)) if wind_values else "?"
desc = normalize_desc(((mid.get("weatherDesc") or [{"value": "sin detalle"}])[0].get("value") or "sin detalle"))
city_label = normalize_city(city)

print(
    "WEATHER_REPLY: "
    f"Manana en {city_label}: minima {weather.get('mintempC', '?')}C, maxima {weather.get('maxtempC', '?')}C, "
    f"humedad {avg_humidity}%, viento {avg_wind} km/h, lluvia {rain}%, estado {desc}."
)
PY
then
  printf 'WEATHER_ERROR\n'
fi
