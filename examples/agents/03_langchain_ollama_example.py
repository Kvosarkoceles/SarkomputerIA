#!/usr/bin/env python3
"""Ejemplo de LangChain con Ollama local."""

try:
    from langchain_ollama import ChatOllama
    from langchain_core.messages import HumanMessage, SystemMessage
except Exception as exc:
    raise SystemExit(
        "Faltan dependencias de LangChain para Ollama. Instala con:\n"
        "pip3 install langchain langchain-ollama\n"
        f"Error de importacion: {exc}"
    )

llm = ChatOllama(model="llama3", base_url="http://localhost:11434")
messages = [
    SystemMessage(content="Eres un asistente DevOps preciso."),
    HumanMessage(content="Dame un runbook corto para probar APIs de IA locales sin GUI."),
]

resp = llm.invoke(messages)
print(resp.content)
