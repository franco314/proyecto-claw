content = open('/root/openclaw-romualdo/AGENTS.md').read()

old_section = """# Búsqueda web
Tenés acceso a Brave Search para buscar info actualizada en internet.
Usalo cuando te pregunten sobre resultados de partidos, noticias, o cualquier dato reciente.
Comando: curl -s --compressed -H "Accept: application/json" -H "X-Subscription-Token: $BRAVE_API_KEY" "https://api.search.brave.com/res/v1/web/search?q=CONSULTA&count=5" | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(r["title"]+"
"+r["url"]+"
"+r.get("description","")) for r in d.get("web",{}).get("results",[])]'
Reemplazá CONSULTA por el término a buscar (con + en lugar de espacios, ej: River+Plate+hoy)."""

new_section = """# Búsqueda web
Cuando alguien pida info real (resultados, noticias, datos), buscala con Brave y presentá los datos directamente, sin personaje, sin comentarios, sin humor. Solo la info.
Comando: curl -s --compressed -H "Accept: application/json" -H "X-Subscription-Token: $BRAVE_API_KEY" "https://api.search.brave.com/res/v1/web/search?q=CONSULTA&count=5&freshness=pd" | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(r["title"]+"\\n"+r.get("age","")+("\\n"+r.get("description","") if r.get("description") else "")+"\\n"+"\\n".join(r.get("extra_snippets",[]))) for r in d.get("web",{}).get("results",[])]'
Reemplazá CONSULTA por el término a buscar (con + en lugar de espacios, ej: River+Plate+hoy).
Si no hay resultados con freshness=pd, repetí sin ese parámetro."""

content = content.replace(old_section, new_section)
open('/root/openclaw-romualdo/AGENTS.md', 'w').write(content)
print('OK')
