#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-llama3}"
PROMPT="${2:-Explica en 5 puntos que hace un centro de control de IA.}"

curl -sS http://localhost:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"${MODEL}\",\"prompt\":\"${PROMPT}\",\"stream\":false}" \
  | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("response", "<sin respuesta>"))'
