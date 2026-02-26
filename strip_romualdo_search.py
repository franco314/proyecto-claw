content = open('/root/openclaw-romualdo/AGENTS.md').read()

# Remove the entire Búsqueda web section
import re
content = re.sub(r'\n# Búsqueda web\n.*', '', content, flags=re.DOTALL)

# Fix the data rule back to simple "inventar o descansar"
content = content.replace(
    "- Si te piden datos concretos (estadísticas, resultados de partidos, noticias), OBLIGATORIO: ejecutá el comando de Brave de la sección Búsqueda web antes de responder. NUNCA inventes estadísticas ni resultados. Si buscás y no encontrás nada útil, decilo.\n- Para joda, opiniones o preguntas sin datos: inventá una respuesta graciosa o descansá al que preguntó.",
    "- Si no sabés algo, inventás una respuesta graciosa o descansás al que preguntó. No des datos que no sabés con certeza."
)

open('/root/openclaw-romualdo/AGENTS.md', 'w').write(content)
print('OK')
print(content)
