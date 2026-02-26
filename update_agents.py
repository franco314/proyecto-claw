import re

brave_cmd = (
    'curl -s'
    ' -H "Accept: application/json"'
    ' -H "Accept-Encoding: gzip"'
    ' -H "X-Subscription-Token: $BRAVE_API_KEY"'
    ' "https://api.search.brave.com/res/v1/web/search?q=CONSULTA&count=5"'
    " | python3 -c 'import json,sys; d=json.load(sys.stdin);"
    " [print(r[\"title\"]+\"\\n\"+r[\"url\"]+\"\\n\"+r.get(\"description\",\"\"))"
    " for r in d.get(\"web\",{}).get(\"results\",[])]'"
)

brave_clawcito = (
    "# Búsqueda web\n"
    "Tenés acceso a Brave Search para buscar info actualizada en internet.\n"
    "Usalo siempre que te pregunten sobre noticias, resultados de partidos, precios, o cualquier dato reciente.\n"
    "Comando: " + brave_cmd + "\n"
    "Reemplazá CONSULTA por el término a buscar (con + en lugar de espacios, ej: River+Plate+hoy)."
)

brave_romualdo = (
    "# Búsqueda web\n"
    "Tenés acceso a Brave Search para buscar info actualizada en internet.\n"
    "Usalo cuando te pregunten sobre resultados de partidos, noticias, o cualquier dato reciente.\n"
    "Comando: " + brave_cmd + "\n"
    "Reemplazá CONSULTA por el término a buscar (con + en lugar de espacios, ej: River+Plate+hoy)."
)

for path, new_section in [
    ('/root/clawd/AGENTS.md', brave_clawcito),
    ('/root/openclaw-romualdo/AGENTS.md', brave_romualdo)
]:
    with open(path, 'r') as f:
        content = f.read()
    content = re.sub(
        r'# B[uú]squeda web\n.*?(?=\n# |\Z)',
        new_section + '\n',
        content,
        flags=re.DOTALL
    )
    with open(path, 'w') as f:
        f.write(content)
    print(f'{path}: OK')
