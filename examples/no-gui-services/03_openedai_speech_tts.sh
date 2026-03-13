#!/usr/bin/env bash
set -euo pipefail

TEXT="${1:-Hola! Como modelo de IA, me diferencio de otras en varias maneras:

Estilo de comunicacion: Mientras que otros modelos de IA pueden ser mas directos y precisos en su lenguaje, estoy disenado para ser mas conversacional y amigable. Intento usar un lenguaje mas natural y menos robotico para que la interaccion sea mas agradable y menos intimidante para el usuario.
Apertura a temas nuevos: A diferencia de otros asistentes que pueden estar limitados a responder preguntas específs o a realizar tareas concretas, estoy diseñado para ser mas abierto y flexible en la conversacion. Puedo abordar una variedad de temas y mantener una conversacion interesante y entretenida.
Aprendizaje continuo: Mientras otros modelos pueden tener un conocimiento fijo y limitado, estoy diseñado para aprender continuamente y mejorar mi comprensión del mundo y de los usuarios con los que interactúo. Esto significa que puedo adaptarme a las preferencias y necesidades del usuario, proporcionando una experiencia mas personalizada y satisfactoria.
Curiosidad: Otra forma en que me diferencio de otros modelos es mi nivel de curiosidad. Estoy diseñado para ser curioso sobre el mundo y sobre los temas que se abordan en la conversacion. Hago preguntas relevantes y muestro interés en profundizar en el tema, lo que puede llevar a una conversacion mas interesante y gratificante.
Respeto: Finalmente, estoy diseñado para ser lo mas respetuoso posible en cada interaccion. Respeto las creencias y valores de cada usuario, y me aseguro de no ofender a nadie durante la conversacion. Esto me distingue de otros asistentes que pueden ser mas directos o menos sensibles a las preferencias y necesidades del usuario.
Espero que estas caracteristicas me hagan unico y util para ti. Si tienes alguna otra pregunta, por favor no dudes en preguntar..}"
OUT="${2:-./tts-output.opus}"
VOICE="${3:-${OPENEDAI_SPEECH_VOICE:-latam}}"
MODEL="${4:-${OPENEDAI_SPEECH_MODEL:-tts-1-hd}}"
FORMAT="${5:-${OPENEDAI_SPEECH_FORMAT:-opus}}"

echo "Iniciando sintesis TTS..."
echo "Progreso de transferencia:"

# Construye JSON en UTF-8 para preservar acentos y caracteres especiales.
PAYLOAD="$(TEXT="$TEXT" VOICE="$VOICE" MODEL="$MODEL" FORMAT="$FORMAT" python3 - <<'PY'
import json
import os

data = {
  "model": os.environ["MODEL"],
    "input": os.environ["TEXT"],
    "voice": os.environ["VOICE"],
    "response_format": os.environ["FORMAT"],
}
print(json.dumps(data, ensure_ascii=False))
PY
)"

curl -sS http://localhost:5002/v1/audio/speech \
  --progress-bar \
  -H 'Content-Type: application/json; charset=utf-8' \
  --data-binary "$PAYLOAD" \
  --output "${OUT}.tmp" \
  -w '%{http_code}' > "${OUT}.status"

HTTP_CODE="$(cat "${OUT}.status")"
rm -f "${OUT}.status"

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Error TTS HTTP ${HTTP_CODE}"
  echo "Detalle del API:"
  cat "${OUT}.tmp"
  rm -f "${OUT}.tmp"
  exit 1
fi

if file "${OUT}.tmp" | grep -qi 'JSON'; then
  echo "Error: el API devolvio JSON en lugar de audio WAV."
  cat "${OUT}.tmp"
  rm -f "${OUT}.tmp"
  exit 1
fi

mv -f "${OUT}.tmp" "${OUT}"
echo "Transferencia completada."

ls -lh "${OUT}"
echo "Guardado en: ${OUT}"
echo "Voz usada: ${VOICE}"
echo "Modelo usado: ${MODEL}"
echo "Formato usado: ${FORMAT}"
