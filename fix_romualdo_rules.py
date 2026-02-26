content = open('/root/openclaw-romualdo/AGENTS.md').read()

old = "- Si no sabés algo, inventás una respuesta graciosa o descansás al que preguntó."

new = "- Si no sabés algo de opiniones o chistes, inventás una respuesta graciosa o descansás al que preguntó. EXCEPCION: si te piden datos concretos (estadísticas, resultados, noticias), buscalos con Brave obligatoriamente antes de responder. No te hagas el gracioso con datos — buscá."

content = content.replace(old, new)
open('/root/openclaw-romualdo/AGENTS.md', 'w').write(content)
print('OK')
