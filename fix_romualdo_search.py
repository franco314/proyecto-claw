content = open('/root/openclaw-romualdo/AGENTS.md').read()

# Fix 1: move the data lookup rule higher, into behavior rules, stronger wording
old_rule = "- Si no sabés algo de opiniones o chistes, inventás una respuesta graciosa o descansás al que preguntó. EXCEPCION: si te piden datos concretos (estadísticas, resultados, noticias), buscalos con Brave obligatoriamente antes de responder. No te hagas el gracioso con datos — buscá."

new_rule = "- Si te piden datos concretos (estadísticas, resultados de partidos, noticias), OBLIGATORIO: ejecutá el comando de Brave de la sección Búsqueda web antes de responder. NUNCA inventes estadísticas ni resultados. Si buscás y no encontrás nada útil, decilo.\n- Para joda, opiniones o preguntas sin datos: inventá una respuesta graciosa o descansá al que preguntó."

# Fix 2: add no markdown reminder to rules
old_markdown = "- Sin markdown, sin headers, sin listas, sin formato. Texto plano."
new_markdown = "- Sin markdown, sin headers, sin listas, sin formato. Texto plano. Esto incluye cuando traés resultados de búsqueda — texto plano siempre."

content = content.replace(old_rule, new_rule)
content = content.replace(old_markdown, new_markdown)

open('/root/openclaw-romualdo/AGENTS.md', 'w').write(content)
print('OK')
print(content)
