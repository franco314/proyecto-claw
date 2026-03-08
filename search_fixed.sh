#!/bin/bash
# Brave Search
# Usage: search.sh "query" [max_results] [freshness]
# freshness: pd (last 24h), pw (last week), pm (last month) - optional

set -euo pipefail

QUERY="${1:-}"
MAX="${2:-5}"
FRESHNESS="${3:-}"
API_KEY="${BRAVE_API_KEY:-}"

if [ -z "$QUERY" ]; then
  echo "Usage: search.sh \"query\" [max_results] [freshness: pd|pw|pm]" >&2
  exit 1
fi

if [ -z "$API_KEY" ]; then
  echo "ERROR: BRAVE_API_KEY no esta configurada." >&2
  exit 2
fi

python3 - "$QUERY" "$MAX" "$FRESHNESS" "$API_KEY" <<'PY'
import datetime as dt
import json
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from urllib.parse import urlparse


def norm(text: str) -> str:
    return ''.join(
        c for c in unicodedata.normalize('NFD', (text or '').lower())
        if unicodedata.category(c) != 'Mn'
    )


def collapse_spaces(text: str) -> str:
    return re.sub(r'\s+', ' ', (text or '')).strip()


def smart_title(name: str) -> str:
    keep_lower = {'de', 'del', 'la', 'las', 'el', 'los', 'y'}
    words = []
    for w in collapse_spaces(name).split(' '):
        wl = w.lower()
        if wl in keep_lower:
            words.append(wl)
        else:
            words.append(w[:1].upper() + w[1:].lower())
    return ' '.join(words)


SPANISH_MONTHS = {
    'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'mayo': 5, 'junio': 6,
    'julio': 7, 'agosto': 8, 'septiembre': 9, 'setiembre': 9, 'octubre': 10,
    'noviembre': 11, 'diciembre': 12,
}
EN_MONTHS = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
    'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
    'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10,
    'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
}


def parsed_dates(text: str, today: dt.date):
    out = []
    t = norm(text)
    current_year = today.year

    for y, m, d in re.findall(r'\b(20\d{2}|19\d{2})-(\d{2})-(\d{2})\b', t):
        try:
            out.append(dt.date(int(y), int(m), int(d)))
        except ValueError:
            pass

    for d, m, y in re.findall(r'\b(\d{1,2})/(\d{1,2})/(20\d{2}|19\d{2})\b', t):
        try:
            out.append(dt.date(int(y), int(m), int(d)))
        except ValueError:
            pass

    for d, m in re.findall(r'\b(\d{1,2})/(\d{1,2})\b', t):
        try:
            guessed = dt.date(current_year, int(m), int(d))
            if guessed < today - dt.timedelta(days=60):
                guessed = dt.date(current_year + 1, int(m), int(d))
            out.append(guessed)
        except ValueError:
            pass

    for d, mon, y in re.findall(r'\b(\d{1,2})\s+de\s+([a-z]+)\s+de\s+(20\d{2}|19\d{2})\b', t):
        mon_n = SPANISH_MONTHS.get(mon)
        if mon_n:
            try:
                out.append(dt.date(int(y), mon_n, int(d)))
            except ValueError:
                pass

    for d, mon in re.findall(r'\b(\d{1,2})\s+de\s+([a-z]+)\b', t):
        mon_n = SPANISH_MONTHS.get(mon)
        if mon_n:
            try:
                guessed = dt.date(current_year, mon_n, int(d))
                if guessed < today - dt.timedelta(days=60):
                    guessed = dt.date(current_year + 1, mon_n, int(d))
                out.append(guessed)
            except ValueError:
                pass

    for mon, d, y in re.findall(r'\b([a-z]+)\s+(\d{1,2}),\s*(20\d{2}|19\d{2})\b', t):
        mon_n = EN_MONTHS.get(mon)
        if mon_n:
            try:
                out.append(dt.date(int(y), mon_n, int(d)))
            except ValueError:
                pass

    for mon, d in re.findall(r'\b([a-z]+)\s+(\d{1,2})\b', t):
        mon_n = EN_MONTHS.get(mon)
        if mon_n:
            try:
                guessed = dt.date(current_year, mon_n, int(d))
                if guessed < today - dt.timedelta(days=60):
                    guessed = dt.date(current_year + 1, mon_n, int(d))
                out.append(guessed)
            except ValueError:
                pass

    uniq = []
    seen = set()
    for d in out:
        if d not in seen:
            seen.add(d)
            uniq.append(d)
    return uniq


def age_to_date(age: str, today: dt.date):
    if not age:
        return None
    age_clean = norm(age.strip())

    from_age = parsed_dates(age, today)
    if from_age:
        return max(from_age)

    if age_clean in ('today', 'hoy'):
        return today
    if age_clean in ('yesterday', 'ayer'):
        return today - dt.timedelta(days=1)

    m = re.search(r'(\d+)\s+(minute|minutes|hour|hours|day|days|week|weeks|month|months|year|years)\s+ago', age_clean)
    if not m:
        m = re.search(r'hace\s+(\d+)\s+(minuto|minutos|hora|horas|dia|dias|semana|semanas|mes|meses|ano|anos)', age_clean)
    if not m:
        return None

    n = int(m.group(1))
    unit = m.group(2)

    if 'minute' in unit or 'minuto' in unit or 'hour' in unit or 'hora' in unit:
        return today
    if 'day' in unit or 'dia' in unit:
        return today - dt.timedelta(days=n)
    if 'week' in unit or 'semana' in unit:
        return today - dt.timedelta(days=7 * n)
    if 'month' in unit or 'mes' in unit:
        return today - dt.timedelta(days=30 * n)
    return today - dt.timedelta(days=365 * n)


def extract_time(text: str):
    t = norm(text)
    m = re.search(r'\b([01]?\d|2[0-3])[:.]([0-5]\d)\s*(?:hs?|h)?\b', t)
    if m:
        return f"{int(m.group(1)):02d}:{int(m.group(2)):02d}"
    m = re.search(r'\b([01]?\d|2[0-3])\s*(?:hs|h)\b', t)
    if m:
        return f"{int(m.group(1)):02d}:00"
    return None


def clean_name(text: str):
    x = norm(text)
    x = re.split(r'\b(por|en|del|de la|de el|torneo|fecha|jornada|partido|hora|canal)\b', x)[0]
    x = re.sub(r'[^a-z0-9 .\-]', ' ', x)
    x = collapse_spaces(x)
    if len(x) < 3:
        return None
    return smart_title(x)


def valid_opponent(name: str):
    if not name:
        return False
    n = norm(name)
    tokens = re.findall(r'[a-z0-9]+', n)
    if not tokens:
        return False
    stop = {
        'este', 'esta', 'hoy', 'manana', 'viernes', 'sabado', 'domingo',
        'lunes', 'martes', 'miercoles', 'jueves', 'partido', 'fecha',
        'torneo', 'apertura', 'clausura', 'canal', 'vivo', 'en', 'de', 'del',
        'fin', 'semana'
    }
    if tokens[0] in stop:
        return False
    if all(t in stop for t in tokens):
        return False
    return True


def overlaps_team(name: str, team_tokens):
    if not team_tokens:
        return False
    n_tokens = set(re.findall(r'[a-z0-9]+', norm(name)))
    return any(t in n_tokens for t in team_tokens)


def extract_opponent(title: str, desc: str, snippets, team_tokens):
    team_blob = ' '.join(team_tokens)
    texts = [title] + list(snippets[:2]) + ([desc] if desc else [])

    for raw_text in texts:
        t = norm(raw_text)
        for m in re.finditer(r'\b(?:vs\.?|v\.?|contra)\s+([a-z0-9][a-z0-9 .\-]{1,70})', t):
            cand = clean_name(m.group(1))
            if not cand:
                continue
            if team_blob and team_blob in norm(cand):
                continue
            if overlaps_team(cand, team_tokens):
                continue
            if valid_opponent(cand):
                return cand

        for m in re.finditer(r'([a-z0-9][a-z0-9 .\-]{1,55})\s+(?:vs\.?|v\.?|contra)\s+([a-z0-9][a-z0-9 .\-]{1,55})', t):
            left = clean_name(m.group(1))
            right = clean_name(m.group(2))
            if not left or not right:
                continue
            ln = norm(left)
            rn = norm(right)
            if team_blob and team_blob in ln and team_blob not in rn and not overlaps_team(right, team_tokens) and valid_opponent(right):
                return right
            if team_blob and team_blob in rn and team_blob not in ln and not overlaps_team(left, team_tokens) and valid_opponent(left):
                return left
    return None


def extract_tournament(text: str):
    t = norm(text)
    m = re.search(r'\b(torneo [a-z0-9 .\-]{3,35}|copa [a-z0-9 .\-]{3,35}|liga [a-z0-9 .\-]{3,35})\b', t)
    if m:
        val = collapse_spaces(m.group(1))
        if len(val) >= 6:
            return smart_title(val)

    keywords = [
        'torneo apertura', 'torneo clausura', 'liga profesional', 'copa libertadores',
        'copa sudamericana', 'copa argentina', 'champions league', 'europa league',
        'premier league', 'la liga', 'serie a', 'bundesliga'
    ]
    for k in keywords:
        if k in t:
            return smart_title(k)
    return None


def build_team_display(query_raw: str, team_tokens):
    cleaned = re.sub(r'(?i)\b(proximo|proxima|partido|partidos|cuando|juega|fixture|agenda|next|match|fecha|hora|rival|hoy|manana|mañana)\b', ' ', query_raw)
    cleaned = collapse_spaces(cleaned).strip(' ?!.,')
    if cleaned:
        return cleaned
    if team_tokens:
        return smart_title(' '.join(team_tokens))
    return 'Equipo'


def brave_search(query: str, count: int, freshness: str, api_key: str):
    enc = urllib.parse.quote(query)
    url = f"https://api.search.brave.com/res/v1/web/search?q={enc}&count={count}&country=AR&search_lang=es"
    if freshness:
        url += f"&freshness={urllib.parse.quote(freshness)}"

    req = urllib.request.Request(
        url,
        headers={
            'Accept': 'application/json',
            'X-Subscription-Token': api_key,
        },
        method='GET',
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode('utf-8', errors='replace'))


def collect_candidates(results, team_tokens, today, temporal, future_required):
    bad_domains = {
        'dle.rae.es', 'rae.es', 'dictionary.cambridge.org', 'poki.com',
        'www.crazygames.com', 'versus.com', 'wikipedia.org'
    }
    out = []

    for r in results:
        title = (r.get('title') or '').strip()
        url = (r.get('url') or '').strip()
        age = (r.get('age') or '').strip()
        desc = (r.get('description') or '').strip()
        snippets = r.get('extra_snippets') or []
        domain = (urlparse(url).netloc or '').lower()

        if not title or not url:
            continue
        if future_required and any(d in domain for d in bad_domains):
            continue

        blob = ' '.join([title, url, age, desc, ' '.join(snippets)])
        norm_blob = norm(blob)

        if team_tokens and any(tok not in norm_blob for tok in team_tokens):
            continue

        dates = parsed_dates(blob, today)
        age_date = age_to_date(age, today)
        if age_date:
            dates.append(age_date)

        future_dates = sorted({d for d in dates if d >= today})
        next_future = future_dates[0] if future_dates else None

        fixture_hint = any(k in norm_blob for k in [
            'fixture', 'calendario', 'proximo partido', 'next match',
            'team/fixtures', '/fixtures', '/calendario', 'partidos', 'agenda deportiva'
        ])

        if future_required:
            if dates and all(d < today for d in dates):
                continue
            if not dates and not fixture_hint:
                continue

        if temporal:
            years = [int(y) for y in re.findall(r'\b(20\d{2}|19\d{2})\b', norm_blob)]
            if years and max(years) < (today.year - 1):
                continue

        opponent = extract_opponent(title, desc, snippets, team_tokens)
        tournament = extract_tournament(' '.join([title, desc] + list(snippets[:2])))
        kickoff = extract_time(blob)

        score = 0
        if next_future:
            score += 1000 - min((next_future - today).days, 365)
        elif fixture_hint:
            score += 120

        if opponent:
            score += 320
        else:
            score -= 220
        if kickoff:
            score += 120
        if tournament:
            score += 60
        if re.search(r'\b(vs\.?|contra)\b', norm_blob):
            score += 90

        trusted = ('lanacion', 'tycsports', 'ole.com.ar', 'espn', 'promiedos', 'sofascore', 'flashscore', 'besoccer', 'cariverplate', 'lapaginamillonaria')
        if any(t in domain for t in trusted):
            score += 70
        if 'wikipedia.org' in domain:
            score -= 500
        if ('cariverplate.com.ar' in domain or 'calendario' in url.lower()) and not opponent and not kickoff:
            score -= 180

        out.append({
            'title': title,
            'url': url,
            'age': age,
            'desc': desc,
            'snippets': snippets,
            'next_future': next_future,
            'fixture_hint': fixture_hint,
            'opponent': opponent,
            'tournament': tournament,
            'kickoff': kickoff,
            'score': score,
        })

    out.sort(key=lambda x: (x['score'], x['next_future'] or dt.date.max), reverse=True)
    return out


def print_fallback(results, future_required):
    simple = []
    for r in results:
        title = (r.get('title') or '').strip()
        url = (r.get('url') or '').strip()
        if title and url:
            simple.append((title, url))

    if not simple:
        if future_required:
            print('Sin resultados futuros confiables.')
        else:
            print('Sin resultados.')
        return

    if future_required:
        for title, url in simple[:3]:
            print(f'{title} | FechaDetectada: a_confirmar')
            print(url)
            print()
    else:
        for title, url in simple[:3]:
            print(title)
            print(url)
            print()


def main():
    query_raw = sys.argv[1]
    max_results = int(sys.argv[2])
    freshness = sys.argv[3]
    api_key = sys.argv[4]

    query = norm(query_raw)
    query_tokens = re.findall(r'[a-z0-9]+', query)

    generic_terms = {
        'proximo', 'proxima', 'partido', 'partidos', 'cuando', 'juega', 'fixture',
        'agenda', 'latest', 'hoy', 'resultado', 'resultados', 'femenino', 'futbol',
        'club', 'vs', 'sub', 'next', 'match', 'fecha', 'hora', 'rival', 'de', 'del'
    }
    team_tokens = [t for t in query_tokens if len(t) >= 3 and t not in generic_terms]

    temporal = any(k in query for k in [
        'proximo', 'proxima', 'cuando juega', 'fixture', 'agenda', 'latest',
        'hoy', 'partido', 'resultado', 'resultados', 'recent', 'reciente',
        'ultimo', 'ultima', 'next match'
    ])
    future_required = any(k in query for k in [
        'proximo', 'proxima', 'cuando juega', 'fixture', 'agenda', 'next'
    ])

    today = dt.datetime.now().date()

    try:
        primary_data = brave_search(query_raw, max_results, freshness, api_key)
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', errors='replace') if hasattr(e, 'read') else ''
        print(f'ERROR: Brave HTTP {e.code}. {body[:200]}')
        return
    except Exception:
        print('ERROR: respuesta invalida de Brave.')
        return

    primary_results = primary_data.get('web', {}).get('results', [])
    if not primary_results:
        print('Sin resultados.')
        return

    candidates = collect_candidates(primary_results, team_tokens, today, temporal, future_required)

    if future_required:
        strong = [c for c in candidates if c['next_future'] and c['opponent']]
        if not strong:
            team_display = build_team_display(query_raw, team_tokens)
            alt_queries = [
                f'cuando juega {team_display}',
                f'cuando juega {team_display} vs',
                f'{team_display} vs proximo partido',
                f'{team_display} proximo partido fecha y hora',
                f'site:promiedos.com {team_display} proximo partido',
                f'site:espn.com.ar {team_display} calendario',
            ]
            seen = {((r.get('url') or '').strip()) for r in primary_results}
            merged = list(primary_results)

            for aq in alt_queries:
                if norm(aq) == norm(query_raw):
                    continue
                try:
                    extra = brave_search(aq, max_results, '', api_key).get('web', {}).get('results', [])
                except Exception:
                    continue
                for r in extra:
                    u = (r.get('url') or '').strip()
                    if not u or u in seen:
                        continue
                    seen.add(u)
                    merged.append(r)

            candidates = collect_candidates(merged, team_tokens, today, temporal, future_required)

    if future_required:
        if not candidates:
            print_fallback(primary_results, future_required=True)
            return

        preferred = [
            c for c in candidates
            if c['next_future'] and c['opponent'] and not overlaps_team(c['opponent'], team_tokens)
        ]
        if preferred:
            preferred.sort(key=lambda c: (c['next_future'], -c['score']))
            best = preferred[0]
        else:
            best = candidates[0]
        team_display = smart_title(build_team_display(query_raw, team_tokens))
        opponent = best['opponent'] or '?'
        if opponent != '?' and overlaps_team(opponent, team_tokens):
            opponent = '?'
        tournament = best['tournament'] or 'a confirmar'
        detected_date = best['next_future'].isoformat() if best['next_future'] else 'a confirmar'
        kickoff = best['kickoff'] or 'a confirmar'

        print(f'Proximo partido: {team_display} vs {opponent} | Torneo: {tournament} | Fecha: {detected_date} | Hora: {kickoff} (America/Buenos_Aires).')
        print(f'Fuente: {best["url"]}')
        print(f'Contexto: {best["title"]}')

        for extra in candidates[1:3]:
            d = extra['next_future'].isoformat() if extra['next_future'] else 'a_confirmar'
            print()
            print(f"{extra['title']} | FechaDetectada: {d}")
            print(extra['url'])
        return

    if temporal:
        if not candidates:
            print_fallback(primary_results, future_required=False)
            return
        for c in candidates:
            age_str = f" [{c['age']}]" if c['age'] else ''
            print(f"{c['title']}{age_str}")
            print(c['url'])
            print()
    else:
        if not candidates:
            print_fallback(primary_results, future_required=False)
            return
        for c in candidates:
            age_str = f" [{c['age']}]" if c['age'] else ''
            print(f"{c['title']}{age_str}")
            print(c['url'])
            if c['desc']:
                print(c['desc'])
            for s in c['snippets'][:2]:
                print(s)
            print()


if __name__ == '__main__':
    main()
PY
