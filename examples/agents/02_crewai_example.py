#!/usr/bin/env python3
"""Ejemplo minimo de CrewAI usando Ollama local con modelo compatible con LiteLLM.

Si tu configuracion de CrewAI/LiteLLM es diferente, ajusta los valores de `llm`.
"""

import os

os.environ.setdefault("CREWAI_TRACING_ENABLED", "false")
os.environ.setdefault("CREWAI_DISABLE_TELEMETRY", "true")

try:
    from crewai import Agent, Task, Crew
except Exception as exc:
    raise SystemExit(
        "CrewAI no esta disponible. Instala con: pip3 install crewai\n"
        f"Error de importacion: {exc}"
    )

researcher = Agent(
    role="Investigador",
    goal="Encontrar una forma rapida de validar servicios de IA locales",
    backstory="Ingeniero de IA enfocado en operaciones",
    llm="ollama/llama3",
    verbose=False,
)

operator = Agent(
    role="Operador",
    goal="Escribir comandos de shell directos para chequeos de salud",
    backstory="Especialista en automatizacion Linux",
    llm="ollama/llama3",
    verbose=False,
)

task = Task(
    description="Crea una lista de 6 comandos para verificar los puertos 5050, 8888, 5002 y 5003.",
    expected_output="Una lista numerada con comandos concretos.",
    agent=operator,
)

crew = Crew(agents=[researcher, operator], tasks=[task], verbose=False)
result = crew.kickoff()
print("\n=== RESULTADO DE CREW ===")
print(result)
