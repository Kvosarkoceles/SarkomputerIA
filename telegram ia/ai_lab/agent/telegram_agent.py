#!/usr/bin/env python3
import json
import os
import shlex
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock, Thread
from typing import Dict, List, Tuple

TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "2"))
OLLAMA_TIMEOUT = int(os.environ.get("OLLAMA_TIMEOUT", "600"))
TELEGRAM_TIMEOUT = int(os.environ.get("TELEGRAM_TIMEOUT", "30"))
MATH_MODEL = os.environ.get("MATH_MODEL", "phi3").strip() or "phi3"
CALLBACK_DEBOUNCE_SECONDS = float(os.environ.get("CALLBACK_DEBOUNCE_SECONDS", "2.5"))

LAB_ROOT = Path(os.environ.get("LAB_ROOT", ".")).resolve()
WHITELIST_FILE = Path(os.environ.get("WHITELIST_FILE", LAB_ROOT / "security/whitelist.txt"))
AGENT_LOG = Path(os.environ.get("AGENT_LOG", LAB_ROOT / "logs/agent.log"))
SECURITY_LOG = Path(os.environ.get("SECURITY_LOG", LAB_ROOT / "logs/security.log"))
MEMORY_DIR = Path(os.environ.get("MEMORY_DIR", LAB_ROOT / "memory/conversations"))

for p in [AGENT_LOG.parent, SECURITY_LOG.parent, MEMORY_DIR]:
    p.mkdir(parents=True, exist_ok=True)

if not TELEGRAM_BOT_TOKEN or TELEGRAM_BOT_TOKEN == "REEMPLAZAR_CON_TOKEN_REAL":
    print("TELEGRAM_BOT_TOKEN no configurado en .env", file=sys.stderr)
    sys.exit(2)

API_BASE = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}"

MAIN_MENU = {
  "keyboard": [
    ["/start", "/help"],
    ["/ai", "/codigo"],
    ["/mate", "/redactar"],
    ["/status", "/logs"],
    ["/cancel"],
  ],
  "resize_keyboard": True,
  "one_time_keyboard": False,
}

INLINE_ACTIONS = {
  "inline_keyboard": [
    [
      {"text": "Estado", "callback_data": "act_status"},
      {"text": "Ayuda", "callback_data": "act_help"},
    ],
    [
      {"text": "Mate", "callback_data": "act_mate"},
      {"text": "Redactar", "callback_data": "act_redactar"},
    ],
  ]
}

LLM_STATE_LOCK = Lock()
LLM_STATE = {"busy": False, "cmd": "", "user_id": ""}

def now() -> str:
  return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

def log_line(path: Path, level: str, message: str) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(f"{now()} [{level}] {message}\n")

def log_agent(message: str) -> None:
    log_line(AGENT_LOG, "AGENT", message)

def log_security(message: str) -> None:
    log_line(SECURITY_LOG, "SECURITY", message)

def load_whitelist() -> set:
    allowed = set()
    if not WHITELIST_FILE.exists():
        return allowed
    for raw in WHITELIST_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        allowed.add(line)
    return allowed

def is_allowed(user_id: int) -> bool:
    return str(user_id) in load_whitelist()

def tg_call(method: str, data: Dict) -> Dict:
    url = f"{API_BASE}/{method}"
    payload = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method="POST")
    with urllib.request.urlopen(req, timeout=TELEGRAM_TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))

def send_message(chat_id: int, text: str, parse_mode: str = "", with_menu: bool = True) -> None:
    try:
        payload = {"chat_id": str(chat_id), "text": text[:3900]}
        if parse_mode:
            payload["parse_mode"] = parse_mode
        if with_menu:
            payload["reply_markup"] = json.dumps(MAIN_MENU, ensure_ascii=False)
        tg_call("sendMessage", payload)
    except Exception as exc:
        log_agent(f"Error enviando mensaje a {chat_id}: {exc}")

def send_chat_action(chat_id: int, action: str = "typing") -> None:
    try:
        tg_call("sendChatAction", {"chat_id": str(chat_id), "action": action})
    except Exception as exc:
        log_agent(f"Error enviando chat action a {chat_id}: {exc}")

def send_message_with_inline(chat_id: int, text: str, parse_mode: str = "") -> None:
    try:
        payload = {
            "chat_id": str(chat_id),
            "text": text[:3900],
            "reply_markup": json.dumps(INLINE_ACTIONS, ensure_ascii=False),
        }
        if parse_mode:
            payload["parse_mode"] = parse_mode
        tg_call("sendMessage", payload)
    except Exception as exc:
        log_agent(f"Error enviando inline menu a {chat_id}: {exc}")

def answer_callback_query(callback_id: str, text: str = "Listo") -> None:
    try:
        tg_call("answerCallbackQuery", {"callback_query_id": callback_id, "text": text[:180]})
    except Exception as exc:
        msg = str(exc)
        if "HTTP Error 400" in msg:
            log_agent(f"Callback expirado {callback_id}")
            return
        log_agent(f"Error respondiendo callback {callback_id}: {exc}")

def memory_file(user_id: int) -> Path:
    return MEMORY_DIR / f"{user_id}.json"

def pending_inputs_file() -> Path:
  return MEMORY_DIR / "_pending_inputs.json"

def load_pending_inputs() -> Dict[str, str]:
  fp = pending_inputs_file()
  if not fp.exists():
    return {}
  try:
    data = json.loads(fp.read_text(encoding="utf-8"))
    if isinstance(data, dict):
      return {str(k): str(v) for k, v in data.items()}
  except Exception:
    pass
  return {}

def save_pending_inputs(data: Dict[str, str]) -> None:
  pending_inputs_file().write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

def set_pending_action(user_id: int, command: str) -> None:
  data = load_pending_inputs()
  data[str(user_id)] = command
  save_pending_inputs(data)

def pop_pending_action(user_id: int) -> str:
  data = load_pending_inputs()
  cmd = data.pop(str(user_id), "")
  save_pending_inputs(data)
  return cmd

def clear_pending_action(user_id: int) -> None:
  data = load_pending_inputs()
  if str(user_id) in data:
    data.pop(str(user_id), None)
    save_pending_inputs(data)

def callback_debounce_file() -> Path:
  return MEMORY_DIR / "_callback_debounce.json"

def offset_file() -> Path:
    return MEMORY_DIR / "_telegram_offset.txt"

def load_last_offset() -> int:
    fp = offset_file()
    if not fp.exists():
        return 0
    try:
        return max(0, int(fp.read_text(encoding="utf-8").strip() or "0"))
    except Exception:
        return 0

def save_last_offset(offset: int) -> None:
    try:
        offset_file().write_text(str(max(0, int(offset))), encoding="utf-8")
    except Exception:
        pass

def load_callback_debounce() -> Dict[str, float]:
  fp = callback_debounce_file()
  if not fp.exists():
    return {}
  try:
    data = json.loads(fp.read_text(encoding="utf-8"))
    if isinstance(data, dict):
      out = {}
      for k, v in data.items():
        try:
          out[str(k)] = float(v)
        except Exception:
          continue
      return out
  except Exception:
    pass
  return {}

def save_callback_debounce(data: Dict[str, float]) -> None:
  callback_debounce_file().write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

def is_callback_debounced(user_id: int, action: str) -> bool:
  key = f"{user_id}:{action}"
  now_ts = time.time()
  data = load_callback_debounce()
  # Lightweight cleanup of stale entries keeps the file small.
  data = {k: v for k, v in data.items() if (now_ts - v) < 600}
  prev = data.get(key, 0.0)
  if now_ts - prev < CALLBACK_DEBOUNCE_SECONDS:
    save_callback_debounce(data)
    return True
  data[key] = now_ts
  save_callback_debounce(data)
  return False

def load_memory(user_id: int) -> List[Dict]:
    fp = memory_file(user_id)
    if not fp.exists():
        return []
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:
        return []

def save_memory(user_id: int, interactions: List[Dict]) -> None:
    memory_file(user_id).write_text(json.dumps(interactions[-20:], ensure_ascii=False, indent=2), encoding="utf-8")

def append_interaction(user_id: int, command: str, prompt: str, response: str, model: str) -> None:
    data = load_memory(user_id)
    data.append({"timestamp": now(), "command": command, "model": model, "prompt": prompt[:1500], "response": response[:3000]})
    save_memory(user_id, data)

def run_cmd(command: str, timeout: int = 20) -> Tuple[int, str]:
    try:
        cp = subprocess.run(command, shell=True, text=True, capture_output=True, timeout=timeout, executable="/bin/bash")
        out = (cp.stdout + "\n" + cp.stderr).strip()
        return cp.returncode, out[:3500]
    except Exception as exc:
        return 1, f"Error ejecutando comando: {exc}"

def route_model(text: str, force_code: bool = False) -> str:
    t = text.lower().strip()
    if force_code:
        return "deepseek-coder"
    if any(k in t for k in ["imagen", "foto", "vision", "analiza imagen", "captura"]):
        return "llava"
    if any(k in t for k in ["codigo", "script", "python", "bash", "javascript", "bug", "error", "refactor", "api"]):
        return "deepseek-coder"
    if any(k in t for k in ["arquitectura", "estrategia", "analisis profundo", "tradeoff"]) or len(t) > 350:
        return "mixtral"
    return "llama3"

def query_ollama(model: str, prompt: str) -> str:
    try:
        cp = subprocess.run(["ollama", "run", model, prompt], capture_output=True, text=True, timeout=OLLAMA_TIMEOUT)
        out = (cp.stdout or "").strip()
        err = (cp.stderr or "").strip()
        if cp.returncode != 0:
            return f"Fallo consultando modelo {model}: {err[:1000]}"
        return out[:3800] if out else f"El modelo {model} no devolvio salida."
    except subprocess.TimeoutExpired:
        return f"Tiempo de espera agotado al consultar {model}."
    except Exception as exc:
        return f"Error interno con Ollama ({model}): {exc}"

def query_ollama_timed(model: str, prompt: str, trace: str = "") -> str:
    start = time.time()
    response = query_ollama(model, prompt)
    elapsed = time.time() - start
    log_agent(f"Inferencia modelo={model} trace={trace!r} duracion={elapsed:.1f}s")
    return response

def try_acquire_llm_slot(cmd: str, user_id: int) -> bool:
    with LLM_STATE_LOCK:
        if LLM_STATE["busy"]:
            return False
        LLM_STATE["busy"] = True
        LLM_STATE["cmd"] = cmd
        LLM_STATE["user_id"] = str(user_id)
        return True

def release_llm_slot() -> None:
    with LLM_STATE_LOCK:
        LLM_STATE["busy"] = False
        LLM_STATE["cmd"] = ""
        LLM_STATE["user_id"] = ""

def llm_busy_message() -> str:
    with LLM_STATE_LOCK:
        cmd = LLM_STATE.get("cmd", "") or "solicitud"
    return f"Estoy procesando {cmd}. Espera a que termine para enviar otra solicitud."

def run_llm_task(chat_id: int, user_id: int, cmd: str, payload: str, model: str, prompt: str, busy_text: str) -> None:
    try:
        send_message(chat_id, busy_text, with_menu=False)
        send_chat_action(chat_id)
        response = query_ollama_timed(model, prompt, trace=cmd.lstrip("/"))
        append_interaction(user_id, cmd, payload, response, model)
        send_message(chat_id, response)
    finally:
        release_llm_slot()

HELP_TEXT = """Comandos disponibles:
/ai pregunta
/codigo script
/mate problema_matematico
/redactar texto_a_corregir
/cpu
/ram
/disco
/red
/docker
/logs
/status
/cancel
"""

HELP_TEXT_STYLED = """*Bot IA - Comandos Disponibles*

`/ai <pregunta>`: consulta general.
`/codigo <solicitud>`: genera o corrige codigo.
`/mate <problema>`: resuelve matematicas paso a paso.
`/redactar <texto>`: corrige redaccion, ortografia y estilo.
`/status`: estado rapido de servicios.
`/logs`: ultimas lineas de logs del agente.
`/cancel`: cancela una entrada pendiente.
"""

def send_force_reply(chat_id: int, text: str, placeholder: str = "Escribe tu texto...") -> None:
  try:
    payload = {
      "chat_id": str(chat_id),
      "text": text[:3900],
      "reply_markup": json.dumps(
        {
          "force_reply": True,
          "selective": True,
          "input_field_placeholder": placeholder[:64],
        },
        ensure_ascii=False,
      ),
    }
    tg_call("sendMessage", payload)
  except Exception as exc:
    log_agent(f"Error enviando force_reply a {chat_id}: {exc}")

def handle_system_command(cmd: str) -> str:
    mapping = {
        "/cpu": "LC_ALL=C top -bn1 | head -n 12",
        "/ram": "free -h",
        "/disco": "df -h",
        "/red": "ip -brief addr || ifconfig",
        "/docker": "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'",
        "/logs": f"tail -n 60 {shlex.quote(str(AGENT_LOG))} {shlex.quote(str(SECURITY_LOG))}",
    }
    if cmd == "/status":
        checks = {
            "ollama": "systemctl is-active ollama || true",
            "docker": "systemctl is-active docker || true",
            "open-webui": "docker ps --format '{{.Names}}' | grep -x 'open-webui' || true",
        }
        rows = []
        for key, c in checks.items():
            _, out = run_cmd(c)
            rows.append(f"{key}: {(out.strip().splitlines()[-1] if out.strip() else 'desconocido')}")
        return "\n".join(rows)
    c = mapping.get(cmd)
    if not c:
        return HELP_TEXT
    rc, out = run_cmd(c)
    return out if rc == 0 else f"Error {cmd}:\n{out}"

def parse_text_command(text: str):
    text = (text or "").strip()
    if not text:
        return "/help", ""
    if text.startswith("/ai "):
        return "/ai", text[4:].strip()
    if text == "/ai":
        return "/ai", ""
    if text.startswith("/codigo "):
        return "/codigo", text[8:].strip()
    if text == "/codigo":
        return "/codigo", ""
    if text.startswith("/mate "):
      return "/mate", text[6:].strip()
    if text == "/mate":
      return "/mate", ""
    if text.startswith("/redactar "):
      return "/redactar", text[10:].strip()
    if text == "/redactar":
      return "/redactar", ""
    known = {
      "/cpu",
      "/ram",
      "/disco",
      "/red",
      "/docker",
      "/logs",
      "/status",
      "/help",
      "/start",
      "/mate",
      "/redactar",
      "/cancel",
    }
    token = text.split(" ", 1)[0]
    if token in known:
        return token, text[len(token):].strip()
    return "/ai", text

def is_likely_math_problem(text: str) -> bool:
    t = (text or "").lower().strip()
    if not t:
        return False

    math_keywords = [
        "matemat", "ecuacion", "ecuación", "integral", "derivada", "limite", "límite",
        "fraccion", "fracción", "porcentaje", "logarit", "raiz", "raíz", "potencia",
        "algebra", "álgebra", "geometr", "trigonom", "estadistic", "probabil",
        "matriz", "vector", "calcula", "calcular", "resuelve", "suma", "resta",
        "multiplica", "divide", "factoriza", "simplifica",
    ]
    if any(k in t for k in math_keywords):
        return True

    has_digit = any(ch.isdigit() for ch in t)
    has_math_symbol = any(ch in t for ch in ["+", "-", "*", "/", "=", "^", "%", "(", ")"])
    return has_digit and has_math_symbol

def handle_message(update: Dict) -> None:
    if "message" not in update:
        return
    msg = update["message"]
    chat_id = msg.get("chat", {}).get("id")
    user = msg.get("from", {})
    user_id = user.get("id")
    username = user.get("username", "sin_username")
    text = msg.get("text", "")
    if chat_id is None or user_id is None:
        return

    if not is_allowed(user_id):
        send_message(chat_id, "*Acceso denegado*\nTu ID no esta en whitelist.", parse_mode="Markdown")
        log_security(f"Usuario bloqueado user_id={user_id} username={username} texto={text!r}")
        return

    log_security(f"Usuario autorizado user_id={user_id} username={username}")
    stripped = (text or "").strip()
    pending_cmd = ""
    if stripped and not stripped.startswith("/"):
        pending_cmd = pop_pending_action(user_id)

    if pending_cmd in {"/ai", "/codigo", "/mate", "/redactar"}:
        cmd, payload = pending_cmd, stripped
    else:
        cmd, payload = parse_text_command(text)
    log_agent(f"Comando ejecutado user_id={user_id} cmd={cmd} payload={payload[:120]!r}")

    if cmd in {"/help", "/start"}:
        clear_pending_action(user_id)
        send_message_with_inline(chat_id, HELP_TEXT_STYLED, parse_mode="Markdown")
        return

    if cmd == "/cancel":
        clear_pending_action(user_id)
        send_message(chat_id, "Entrada pendiente cancelada.")
        return

    if cmd in {"/cpu", "/ram", "/disco", "/red", "/docker", "/logs", "/status"}:
        send_message(chat_id, f"*Resultado {cmd}*\n```\n{handle_system_command(cmd)}\n```", parse_mode="Markdown")
        return

    if cmd == "/codigo":
        if not payload:
            set_pending_action(user_id, "/codigo")
            send_force_reply(chat_id, "Envia la descripcion del script que quieres.", "Describe el script...")
            return
        clear_pending_action(user_id)
        model = route_model(payload, force_code=True)
        prompt = "Eres un asistente de codigo seguro. Devuelve una solucion clara.\n\nSolicitud:\n" + payload
        if not try_acquire_llm_slot(cmd, user_id):
            send_message(chat_id, llm_busy_message())
            return
        Thread(
            target=run_llm_task,
            args=(chat_id, user_id, cmd, payload, model, prompt, "Procesando /codigo..."),
            daemon=True,
        ).start()
        return

    if cmd == "/mate":
        if not payload:
            set_pending_action(user_id, "/mate")
            send_force_reply(chat_id, "Envia tu problema matematico.", "Ejemplo: resuelve 2x + 5 = 15")
            return

        if not is_likely_math_problem(payload):
            clear_pending_action(user_id)
            send_message(chat_id, "Este comando solo resuelve temas matematicos.")
            return

        clear_pending_action(user_id)
        model = MATH_MODEL
        prompt = (
            "Eres un tutor de matematicas claro y directo. Responde EXCLUSIVAMENTE temas matematicos. "
            "Si el texto no es matematico, responde exactamente: 'Este comando solo resuelve temas matematicos.'. "
            "Si el problema es ambiguo, haz una suposicion razonable y explicala. "
            "Si el problema es complejo, divide la solucion en pasos claros.\n\n"
            "Resuelve paso a paso en formato breve y termina con 'Respuesta final:'.\n\n"
            "Problema:\n" + payload
        )
        if not try_acquire_llm_slot(cmd, user_id):
            send_message(chat_id, llm_busy_message())
            return
        Thread(
            target=run_llm_task,
            args=(chat_id, user_id, cmd, payload, model, prompt, f"Procesando /mate con {model}..."),
            daemon=True,
        ).start()
        return

    if cmd == "/redactar":
        if not payload:
            set_pending_action(user_id, "/redactar")
            send_force_reply(chat_id, "Envia el texto para corregir.", "Pega aqui tu texto...")
            return
        clear_pending_action(user_id)
        model = "llama3"
        prompt = (
            "Corrige ortografia, puntuacion y claridad del texto en espanol. "
            "Devuelve en este formato: \n1) Version corregida\n2) Mejoras clave (3 puntos max).\n\n"
            "Texto:\n" + payload
        )
        if not try_acquire_llm_slot(cmd, user_id):
            send_message(chat_id, llm_busy_message())
            return
        Thread(
            target=run_llm_task,
            args=(chat_id, user_id, cmd, payload, model, prompt, "Procesando /redactar..."),
            daemon=True,
        ).start()
        return

    if cmd == "/ai":
        if not payload:
            set_pending_action(user_id, "/ai")
            send_force_reply(chat_id, "Escribe tu pregunta.", "Escribe tu pregunta...")
            return
        clear_pending_action(user_id)
        model = route_model(payload)
        if not try_acquire_llm_slot(cmd, user_id):
            send_message(chat_id, llm_busy_message())
            return
        Thread(
            target=run_llm_task,
            args=(chat_id, user_id, cmd, payload, model, payload, f"Procesando /ai con {model}..."),
            daemon=True,
        ).start()
        return

    send_message(chat_id, HELP_TEXT)

def handle_callback_query(update: Dict) -> None:
    cb = update.get("callback_query", {})
    cb_id = cb.get("id")
    data = (cb.get("data") or "").strip()
    message = cb.get("message", {})
    chat_id = message.get("chat", {}).get("id")
    user = cb.get("from", {})
    user_id = user.get("id")
    username = user.get("username", "sin_username")

    if not cb_id or chat_id is None or user_id is None:
        return

    if not is_allowed(user_id):
        answer_callback_query(cb_id, "No autorizado")
        send_message(chat_id, "*Acceso denegado*\nTu ID no esta en whitelist.", parse_mode="Markdown")
        log_security(f"Callback bloqueado user_id={user_id} username={username} data={data!r}")
        return

    if is_callback_debounced(user_id, data):
        answer_callback_query(cb_id, "Espera un momento...")
        log_agent(f"Callback ignorado por debounce user_id={user_id} data={data!r}")
        return

    answer_callback_query(cb_id, "Accion ejecutada")
    log_security(f"Callback autorizado user_id={user_id} username={username}")
    log_agent(f"Callback ejecutado user_id={user_id} data={data!r}")

    if data == "act_help":
        send_message_with_inline(chat_id, HELP_TEXT_STYLED, parse_mode="Markdown")
        return
    if data == "act_status":
        out = handle_system_command("/status")
        send_message_with_inline(chat_id, f"*Resultado /status*\n```\n{out}\n```", parse_mode="Markdown")
        return
    if data == "act_mate":
        set_pending_action(user_id, "/mate")
        send_force_reply(chat_id, "Envia tu problema matematico.", "Ejemplo: integral de x^2")
        return
    if data == "act_redactar":
        set_pending_action(user_id, "/redactar")
        send_force_reply(chat_id, "Envia el texto para corregir.", "Pega aqui tu texto...")
        return

    send_message_with_inline(chat_id, HELP_TEXT_STYLED, parse_mode="Markdown")

def poll_loop() -> None:
    log_agent("Agente iniciado")
    offset = load_last_offset()
    save_last_offset(offset)
    poll_timeout = max(1, TELEGRAM_TIMEOUT - 5)
    while True:
        try:
            data = tg_call("getUpdates", {"timeout": str(poll_timeout), "offset": str(offset)})
            if not data.get("ok", False):
                log_agent(f"Respuesta no OK de Telegram: {data}")
                time.sleep(POLL_INTERVAL)
                continue
            items = data.get("result", [])
            for item in items:
                upd_id = item.get("update_id")
                if isinstance(upd_id, int):
                    offset = max(offset, upd_id + 1)
                    save_last_offset(offset)
                try:
                    if "callback_query" in item:
                        handle_callback_query(item)
                    else:
                        handle_message(item)
                except Exception as e:
                    log_agent(f"Error procesando mensaje: {e}\n{traceback.format_exc()}")
            # getUpdates already long-polls; no extra sleep needed here.
        except TimeoutError:
            continue
        except urllib.error.HTTPError as e:
            log_agent(f"Error en poll_loop HTTP {e.code}: {e.reason}")
            time.sleep(max(POLL_INTERVAL, 3))
        except urllib.error.URLError as e:
            log_agent(f"Error de red en poll_loop: {e.reason}")
            time.sleep(max(POLL_INTERVAL, 3))
        except Exception as e:
            log_agent(f"Error en poll_loop: {e}\n{traceback.format_exc()}")
            time.sleep(max(POLL_INTERVAL, 3))

if __name__ == "__main__":
    poll_loop()
