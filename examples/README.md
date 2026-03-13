# Ejemplos AI Lab (agentes + servicios sin GUI)

Esta carpeta contiene ejemplos listos para ejecutar de:
- Flujos de agentes locales (sin interfaz web)
- Modelos/servicios locales que exponen API HTTP o TCP en lugar de interfaz grafica

## Estructura

- `agents/`: ejemplos de agentes (orquestacion local y frameworks opcionales)
- `no-gui-services/`: ejemplos de uso directo por API/TCP

## Para que sirve cada servicio

- `http://localhost:5050` (AI Control Center): panel central con accesos a los servicios del laboratorio.
- `http://localhost:3001` (Open WebUI / AI Chat): interfaz web para chatear con modelos de Ollama.
- `http://localhost:11434` (Ollama API): API local para inferencia de modelos LLM (chat, generate, embeddings).
- `http://localhost:8888` (JupyterLab): entorno de notebooks para pruebas, experimentos y analisis.
- `http://localhost:5002` (OpenedAI Speech): API TTS compatible con OpenAI para convertir texto a audio.
- `localhost:5003` (Piper Wyoming): servicio TTS por protocolo Wyoming (TCP), pensado para integraciones de voz sin GUI.
- `http://localhost:8188` (ComfyUI): interfaz/servicio para generacion de imagenes con flujos de diffusion (puede requerir GPU).
- `http://localhost:3000` (Grafana): paneles de monitoreo y visualizacion de metricas.
- `http://localhost:9090` (Prometheus): recoleccion y consulta de metricas.
- `http://localhost:9001` (MinIO Console): consola de almacenamiento tipo S3.
- `http://localhost:9000` (MinIO API): endpoint S3 para guardar artefactos, datasets y salidas.

## Inicio rapido

Desde la raiz del proyecto:

```bash
cd /home/kvo/Documentos/SarkomputerIA/examples
```

### Dependencias para ejemplos de agentes

Si al ejecutar `agents/02_crewai_example.py` aparece un error de importacion, instala:

```bash
/usr/bin/python3 -m pip install --user --break-system-packages crewai litellm langchain langchain-ollama
```

### 1) Probar servicios sin GUI

```bash
bash no-gui-services/05_service_healthcheck.sh
bash no-gui-services/01_ollama_generate.sh
python3 no-gui-services/02_ollama_python_chat.py
bash no-gui-services/03_openedai_speech_tts.sh
python3 no-gui-services/04_piper_wyoming_tcp_check.py
```

### 2) Probar ejemplos de agentes

```bash
python3 agents/01_multi_agent_ollama.py
python3 agents/02_crewai_example.py
python3 agents/03_langchain_ollama_example.py
```

## Ejemplos detallados

## Para que sirve cada ejemplo

- `no-gui-services/01_ollama_generate.sh`: lanzar inferencias directas a Ollama con prompts simples desde shell.
- `no-gui-services/02_ollama_python_chat.py`: integrar chat con Ollama desde Python sin dependencias externas.
- `no-gui-services/03_openedai_speech_tts.sh`: generar audio WAV desde texto usando API TTS local.
- `no-gui-services/04_piper_wyoming_tcp_check.py`: validar conectividad del servicio Piper (sin asumir HTTP).
- `no-gui-services/05_service_healthcheck.sh`: diagnostico rapido de disponibilidad HTTP/TCP de puertos clave.
- `agents/01_multi_agent_ollama.py`: patron base de orquestacion multiagente con roles (planificador, revisor, ejecutor).
- `agents/02_crewai_example.py`: ejemplo de CrewAI conectado a modelo local de Ollama.
- `agents/03_langchain_ollama_example.py`: ejemplo de LangChain consumiendo Ollama como backend local.

### Servicios sin GUI

`no-gui-services/01_ollama_generate.sh`
- Genera una respuesta con Ollama por REST.

```bash
bash no-gui-services/01_ollama_generate.sh
bash no-gui-services/01_ollama_generate.sh mistral "Dame 3 ideas para automatizar un laboratorio IA local"
```

`no-gui-services/02_ollama_python_chat.py`
- Hace una conversacion simple con Ollama desde Python.

```bash
python3 no-gui-services/02_ollama_python_chat.py
```

`no-gui-services/03_openedai_speech_tts.sh`
- Convierte texto a voz usando OpenedAI Speech y guarda un `.wav`.

```bash
bash no-gui-services/03_openedai_speech_tts.sh
bash no-gui-services/03_openedai_speech_tts.sh "Hola equipo, prueba de voz local" ./mi-audio.wav
```

`no-gui-services/04_piper_wyoming_tcp_check.py`
- Verifica conectividad TCP al servicio Piper (protocolo Wyoming).

```bash
python3 no-gui-services/04_piper_wyoming_tcp_check.py
```

`no-gui-services/05_service_healthcheck.sh`
- Chequeo rapido de estado HTTP/TCP de puertos clave.

```bash
bash no-gui-services/05_service_healthcheck.sh
```

### Agentes

`agents/01_multi_agent_ollama.py`
- Simula un flujo de 3 agentes (planificador, revisor, ejecutor) usando Ollama local.

```bash
python3 agents/01_multi_agent_ollama.py
```

`agents/02_crewai_example.py`
- Ejemplo minimo con CrewAI y modelo local (`ollama/llama3`).

```bash
python3 agents/02_crewai_example.py
```

`agents/03_langchain_ollama_example.py`
- Ejemplo de LangChain conectando con Ollama local.

```bash
python3 agents/03_langchain_ollama_example.py
```

## Notas importantes

- `5002` corresponde a OpenedAI Speech (API compatible con OpenAI TTS).
- `5003` corresponde a Piper Wyoming TCP (no tiene interfaz HTTP en navegador).
- `8188` puede no estar disponible si la imagen de ComfyUI requiere runtime NVIDIA y no esta configurado en Docker.
