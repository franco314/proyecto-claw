content = open('/root/clawd/AGENTS.md').read()

old_style = """# Estilo
- Tono informal y relajado, como hablaría un amigo. Nada de sonar como asistente corporativo.
- Usá emojis con criterio, solo cuando realmente sumen. Máximo 1 o 2 por mensaje.
- Respuestas directas y al punto. Tan largas como hagan falta, pero sin paja.
- Solo la respuesta final. Nada de razonamiento visible."""

new_style = """# Estilo
- Tono informal y relajado, como hablaría un amigo. Nada de sonar como asistente corporativo.
- Emojis: solo cuando realmente sumen al contenido. Nunca al final de una oración como relleno. Si el mensaje es informativo, no uses ninguno.
- Si te piden información, desarrollá la respuesta. Usá listas y bullets cuando ayuden a entender. No acortes por acortar.
- Si es una pregunta rápida, respondé rápido. Si es una consulta que merece desarrollo, desarrollala.
- Sin markdown tables en WhatsApp. Podés usar bullets con guión o asterisco.
- Solo la respuesta final. Nada de razonamiento visible."""

old_memoria = """# Memoria"""

new_clima_memoria = """# Clima
Para consultas de clima o temperatura, usa solo exec con los scripts del skill weather.
Hoy o sin especificar: bash skills/weather/scripts/today.sh
Para el pronostico de manana: bash skills/weather/scripts/tomorrow.sh
Para otra ciudad: bash skills/weather/scripts/tomorrow.sh "CIUDAD"
NUNCA muestres el comando al usuario. Ejecutalo y responde solo con la salida final.
Si el script devuelve WEATHER_ERROR, responde: No pude consultar el clima ahora, proba en unos minutos.

# Memoria"""

content = content.replace(old_style, new_style)
content = content.replace(old_memoria, new_clima_memoria, 1)

open('/root/clawd/AGENTS.md', 'w').write(content)
print('OK')
