---
name: weather
description: "Get current weather and tomorrow forecasts via wttr.in without exposing internal commands."
homepage: https://wttr.in/:help
metadata: { "openclaw": { "requires": { "bins": ["bash", "curl", "python3"] } } }
---

# Weather Skill
Use this skill for weather, temperature, and forecast questions.

## Internal Commands
- Today or no date: `bash skills/weather/scripts/today.sh`
- Tomorrow forecast: `bash skills/weather/scripts/tomorrow.sh`
- Another city: pass the city as a single quoted argument, for example `bash skills/weather/scripts/tomorrow.sh "Mar del Plata"`

## Mandatory Rules
- Execute with `exec`. Do not quote the command to the user.
- Never expose internal commands, pipelines, snippets, raw JSON, stderr, or operational instructions in normal chat.
- If the script returns a line starting with `WEATHER_REPLY:`, your next message must be exactly the text after that prefix, with no rewriting, no summary, no added tone, and no second line.
- The scripts already retry once internally.
- If the script returns `WEATHER_ERROR`, reply exactly: `No pude consultar el clima ahora, proba en unos minutos.`
- Do not use `web_search`, `web_fetch`, `browser`, or Brave for normal weather requests.
