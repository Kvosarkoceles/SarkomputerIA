#!/usr/bin/env python3
import json
import urllib.request

url = "http://localhost:11434/api/chat"
payload = {
    "model": "llama3",
    "messages": [
        {"role": "system", "content": "Eres un asistente conciso."},
        {"role": "user", "content": "Dame un plan de 3 pasos para probar mi stack de IA local."},
    ],
    "stream": False,
}

req = urllib.request.Request(
    url,
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"},
)

with urllib.request.urlopen(req, timeout=60) as resp:
    data = json.loads(resp.read().decode("utf-8"))

print(data.get("message", {}).get("content", "<sin contenido>"))
