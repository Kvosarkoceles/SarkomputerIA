#!/usr/bin/env python3
import json
import urllib.request

OLLAMA_URL = "http://localhost:11434/api/chat"
MODEL = "llama3"
USER_GOAL = "Crea un plan corto para auditar servicios de IA locales y proponer mejoras."


def ask(role_instruction: str, user_input: str) -> str:
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": role_instruction},
            {"role": "user", "content": user_input},
        ],
        "stream": False,
    }

    req = urllib.request.Request(
        OLLAMA_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data.get("message", {}).get("content", "")


planner_prompt = "Eres un agente planificador. Devuelve un plan conciso de 5 pasos."
reviewer_prompt = "Eres un agente revisor. Identifica riesgos y validaciones faltantes."
executor_prompt = "Eres un agente ejecutor. Produce acciones y comandos finales."

plan = ask(planner_prompt, USER_GOAL)
review = ask(reviewer_prompt, f"Objetivo: {USER_GOAL}\nPlan preliminar:\n{plan}")
final_actions = ask(
    executor_prompt,
    f"Objetivo: {USER_GOAL}\nPlan:\n{plan}\nRevision:\n{review}\nDevuelve comandos accionables.",
)

print("=== PLAN ===")
print(plan)
print("\n=== REVISION ===")
print(review)
print("\n=== ACCIONES FINALES ===")
print(final_actions)
