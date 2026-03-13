#!/usr/bin/env bash
# ==============================================================================
# AI LAB LOCAL - INSTALADOR PROFESIONAL E IDEMPOTENTE
# ============================================================================== 
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
LAB_ROOT="${LAB_ROOT:-$PWD/ai_lab}"
AGENT_DIR="$LAB_ROOT/agent"
AGENTS_DIR="$LAB_ROOT/agents"
MEMORY_DIR="$LAB_ROOT/memory"
MEMORY_CONV_DIR="$MEMORY_DIR/conversations"
SECURITY_DIR="$LAB_ROOT/security"
TOOLS_DIR="$LAB_ROOT/tools"
MODELS_DIR="$LAB_ROOT/models"
LOGS_DIR="$LAB_ROOT/logs"
WEBUI_DIR="$LAB_ROOT/webui"

INSTALL_LOG="$LOGS_DIR/install.log"
AGENT_LOG="$LOGS_DIR/agent.log"
SECURITY_LOG="$LOGS_DIR/security.log"

WHITELIST_FILE="$SECURITY_DIR/whitelist.txt"
AGENT_ENV_FILE="$AGENT_DIR/.env"
AGENT_SCRIPT="$AGENT_DIR/telegram_agent.py"

SYSTEMD_SERVICE_PATH="/etc/systemd/system/ai-lab-agent.service"
OPENWEBUI_CONTAINER="open-webui"
OPENWEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"
OPENWEBUI_PORT_HOST="3000"
OPENWEBUI_PORT_CONTAINER="8080"

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'
C_WHITE='\033[37m'

TOTAL_STEPS=16
CURRENT_STEP=0
BAR_WIDTH=36

print_header() { printf "\n${C_BOLD}${C_BLUE}==> %s${C_RESET}\n" "$1"; }
print_info() { printf "${C_CYAN}[INFO]${C_RESET} %s\n" "$1"; }
print_ok() { printf "${C_GREEN}[OK]${C_RESET} %s\n" "$1"; }
print_warn() { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"; }
print_err() { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$1"; }

progress_step() {
  local title="$1"
  CURRENT_STEP=$((CURRENT_STEP + 1))
  local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
  local filled=$((CURRENT_STEP * BAR_WIDTH / TOTAL_STEPS))
  local empty=$((BAR_WIDTH - filled))
  local bar
  bar="$(printf "%0.s#" $(seq 1 "$filled"))$(printf "%0.s-" $(seq 1 "$empty"))"
  printf "${C_BOLD}${C_WHITE}[%s] %3d%%${C_RESET} %s\n" "$bar" "$percent" "$title"
}

on_error() {
  local line="$1"
  local code="$2"
  print_err "Fallo en linea $line (codigo $code). Revisa el log: $INSTALL_LOG"
  exit "$code"
}
trap 'on_error $LINENO $?' ERR

SUDO=""
ensure_sudo() {
  if [[ "${EUID}" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      print_err "sudo no esta disponible y el script no corre como root."
      exit 1
    fi
    SUDO="sudo"
    $SUDO -v
  fi
}

ensure_ubuntu_22_or_newer() {
  [[ -f /etc/os-release ]] || { print_err "No se detecta /etc/os-release."; exit 1; }
  # shellcheck disable=SC1091
  source /etc/os-release
  local os_id="${ID:-}"
  local os_version="${VERSION_ID:-0}"
  [[ "$os_id" == "ubuntu" ]] || { print_err "Sistema no soportado: $os_id. Se requiere Ubuntu 22.04+."; exit 1; }

  local major minor
  major="$(echo "$os_version" | cut -d. -f1)"
  minor="$(echo "$os_version" | cut -d. -f2)"
  major="${major:-0}"; minor="${minor:-0}"
  if (( major < 22 )) || { (( major == 22 )) && (( minor < 4 )); }; then
    print_err "Version Ubuntu no soportada: $os_version. Se requiere 22.04+."; exit 1
  fi
  print_ok "Ubuntu compatible detectado: $os_version"
}

create_base_structure() {
  mkdir -p "$AGENT_DIR" "$AGENTS_DIR" "$MEMORY_DIR" "$MEMORY_CONV_DIR" "$SECURITY_DIR" "$TOOLS_DIR" "$MODELS_DIR" "$LOGS_DIR" "$WEBUI_DIR"
  touch "$INSTALL_LOG" "$AGENT_LOG" "$SECURITY_LOG"
}

enable_install_logging() { exec > >(tee -a "$INSTALL_LOG") 2>&1; }

apt_update_once() {
  local stamp_file="/tmp/.ai_lab_apt_updated_$(date +%F)"
  if [[ ! -f "$stamp_file" ]]; then
    print_info "Actualizando indices APT..."
    $SUDO apt-get update -y
    touch "$stamp_file"
  else
    print_info "APT update ya realizado hoy."
  fi
}

apt_install_packages() {
  local pkgs=("$@")
  [[ "${#pkgs[@]}" -eq 0 ]] && return 0
  apt_update_once
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "${pkgs[@]}"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }
service_already_installed_msg() { print_ok "$1: Servicio ya instalado"; }

write_managed_file() {
  local target="$1"; local mode="$2"; local tmp
  local target_dir
  local -a install_cmd
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"; print_info "Sin cambios en $target"; return 0
  fi
  target_dir="$(dirname "$target")"
  if [[ "${EUID}" -eq 0 ]]; then
    mkdir -p "$target_dir"
    install_cmd=(install)
  else
    $SUDO mkdir -p "$target_dir"
    install_cmd=($SUDO install)
  fi
  # install preserves atomic-ish behavior by replacing target in one operation.
  "${install_cmd[@]}" -m "$mode" "$tmp" "$target"
  rm -f "$tmp"
  print_ok "Archivo actualizado: $target"
}

install_python3_if_needed() {
  if command_exists python3; then service_already_installed_msg "Python3"; return 0; fi
  print_info "Instalando Python3..."
  apt_install_packages python3 python3-venv python3-pip
  print_ok "Python3 instalado"
}

install_nodejs_if_needed() {
  if command_exists node; then service_already_installed_msg "NodeJS"; return 0; fi
  print_info "Instalando NodeJS..."
  apt_install_packages nodejs npm
  print_ok "NodeJS instalado"
}

install_docker_if_needed() {
  if command_exists docker; then service_already_installed_msg "Docker"; return 0; fi

  print_info "Instalando Docker Engine..."
  apt_install_packages ca-certificates curl gnupg lsb-release

  $SUDO install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local arch codename
  arch="$(dpkg --print-architecture)"
  # shellcheck disable=SC1091
  source /etc/os-release
  codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-jammy}}"

  local repo_line
  repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable"
  if [[ ! -f /etc/apt/sources.list.d/docker.list ]] || ! grep -Fq "$repo_line" /etc/apt/sources.list.d/docker.list; then
    echo "$repo_line" | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi

  apt_update_once
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  [[ -n "${SUDO:-}" ]] && $SUDO usermod -aG docker "${USER}" || true
  $SUDO systemctl enable --now docker
  print_ok "Docker instalado y activo"
}

install_docker_compose_if_needed() {
  if docker compose version >/dev/null 2>&1; then service_already_installed_msg "Docker Compose"; return 0; fi
  print_info "Instalando Docker Compose Plugin..."
  apt_install_packages docker-compose-plugin
  print_ok "Docker Compose plugin instalado"
}

install_ollama_if_needed() {
  if command_exists ollama; then service_already_installed_msg "Ollama"; return 0; fi
  print_info "Instalando Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
  command -v systemctl >/dev/null 2>&1 && $SUDO systemctl enable --now ollama || true
  print_ok "Ollama instalado"
}

install_telegram_cli_if_needed() {
  if command_exists telegram-cli; then service_already_installed_msg "telegram-cli"; return 0; fi
  print_info "Instalando telegram-cli (si esta disponible)..."
  if apt-cache show telegram-cli >/dev/null 2>&1; then
    apt_install_packages telegram-cli
    print_ok "telegram-cli instalado"
  else
    print_warn "telegram-cli no disponible en repositorio actual."
  fi
}

install_vscode_if_needed() {
  if command_exists code; then service_already_installed_msg "Visual Studio Code"; return 0; fi

  print_info "Instalando Visual Studio Code..."
  apt_install_packages wget gpg apt-transport-https software-properties-common

  if [[ ! -f /usr/share/keyrings/packages.microsoft.gpg ]]; then
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | $SUDO tee /usr/share/keyrings/packages.microsoft.gpg >/dev/null
  fi

  if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | $SUDO tee /etc/apt/sources.list.d/vscode.list >/dev/null
  fi

  apt_update_once
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y code
  print_ok "Visual Studio Code instalado"
}

OLLAMA_MODELS=("llama3" "mistral" "phi3" "mixtral" "deepseek-coder" "llava")

ensure_ollama_running() {
  if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet ollama; then
    print_warn "Servicio ollama no activo. Intentando arrancar..."
    $SUDO systemctl start ollama || true
  fi
}

ollama_model_exists() {
  local model="$1"
  local existing
  existing="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' || true)"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == "$model" || "$line" == "$model:"* ]]; then return 0; fi
  done <<< "$existing"
  return 1
}

install_models_if_needed() {
  if ! command_exists ollama; then print_warn "Ollama no disponible. No se pueden gestionar modelos."; return 0; fi
  ensure_ollama_running
  print_info "Consultando modelos existentes con: ollama list"
  for m in "${OLLAMA_MODELS[@]}"; do
    if ollama_model_exists "$m"; then
      print_ok "$m: Modelo ya instalado"
    else
      print_info "Descargando modelo: $m"
      ollama pull "$m"
      print_ok "$m instalado"
    fi
  done
}

create_whitelist_file() {
  if [[ -f "$WHITELIST_FILE" ]]; then print_info "Whitelist existente: $WHITELIST_FILE"; return 0; fi
  write_managed_file "$WHITELIST_FILE" "0640" <<'EOF'
# IDs de Telegram autorizados (uno por linea)
# Ejemplo:
# 123456789
EOF
}

create_agent_env() {
  if [[ -f "$AGENT_ENV_FILE" ]]; then print_info "Archivo .env del agente ya existe"; return 0; fi
  write_managed_file "$AGENT_ENV_FILE" "0640" <<EOF
TELEGRAM_BOT_TOKEN=REEMPLAZAR_CON_TOKEN_REAL
POLL_INTERVAL=2
OLLAMA_TIMEOUT=600
TELEGRAM_TIMEOUT=30
LAB_ROOT=$LAB_ROOT
WHITELIST_FILE=$WHITELIST_FILE
AGENT_LOG=$AGENT_LOG
SECURITY_LOG=$SECURITY_LOG
MEMORY_DIR=$MEMORY_CONV_DIR
EOF
}

create_agent_python() {
  if [[ -f "$AGENT_SCRIPT" ]]; then
    print_info "Script del agente ya existe, no se sobrescribe: $AGENT_SCRIPT"
    return 0
  fi
  write_managed_file "$AGENT_SCRIPT" "0750" <<'PYEOF'
#!/usr/bin/env python3
import json
import os
import shlex
import subprocess
import sys
import time
import traceback
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
        clear_pending_action(user_id)
        model = MATH_MODEL
        prompt = (
          "Eres un tutor de matematicas claro y directo. "
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
    offset = 0
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
                try:
                  if "callback_query" in item:
                    handle_callback_query(item)
                  else:
                    handle_message(item)
                except Exception as e:
                    log_agent(f"Error procesando mensaje: {e}\n{traceback.format_exc()}")
      # getUpdates already long-polls; no extra sleep needed here.
        except Exception as e:
            log_agent(f"Error en poll_loop: {e}\n{traceback.format_exc()}")
            time.sleep(max(POLL_INTERVAL, 3))

if __name__ == "__main__":
    poll_loop()
PYEOF
}

normalize_agent_file_permissions() {
  local owner_user owner_group
  owner_user="${SUDO_USER:-$USER}"
  owner_group="$(id -gn "$owner_user" 2>/dev/null || echo "$owner_user")"

  local -a targets=("$AGENT_SCRIPT" "$AGENT_ENV_FILE" "$WHITELIST_FILE")
  if [[ "${EUID}" -eq 0 ]]; then
    chown "$owner_user:$owner_group" "${targets[@]}" 2>/dev/null || true
    chmod 0750 "$AGENT_SCRIPT" 2>/dev/null || true
    chmod 0640 "$AGENT_ENV_FILE" "$WHITELIST_FILE" 2>/dev/null || true
  else
    $SUDO chown "$owner_user:$owner_group" "${targets[@]}" 2>/dev/null || true
    $SUDO chmod 0750 "$AGENT_SCRIPT" 2>/dev/null || true
    $SUDO chmod 0640 "$AGENT_ENV_FILE" "$WHITELIST_FILE" 2>/dev/null || true
  fi
}

create_systemd_service() {
  write_managed_file "$SYSTEMD_SERVICE_PATH" "0644" <<EOF
[Unit]
Description=AI Lab Telegram Agent
After=network-online.target ollama.service docker.service
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=${USER}
WorkingDirectory=${AGENT_DIR}
EnvironmentFile=${AGENT_ENV_FILE}
ExecStart=/usr/bin/python3 "${AGENT_SCRIPT}"
Restart=always
RestartSec=5
StandardOutput=append:${AGENT_LOG}
StandardError=append:${AGENT_LOG}
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable ai-lab-agent.service
  print_ok "Servicio systemd configurado: ai-lab-agent.service"
}

start_or_warn_agent() {
  local token
  token="$(grep -E '^TELEGRAM_BOT_TOKEN=' "$AGENT_ENV_FILE" | cut -d'=' -f2- || true)"
  if [[ -z "$token" || "$token" == "REEMPLAZAR_CON_TOKEN_REAL" ]]; then
    print_warn "Token Telegram no configurado. El servicio se habilita pero no se inicia."
    print_warn "Edita: $AGENT_ENV_FILE y luego: sudo systemctl restart ai-lab-agent.service"
    return 0
  fi
  $SUDO systemctl restart ai-lab-agent.service
  print_ok "Agente Telegram iniciado/reiniciado"
}

deploy_open_webui() {
  if ! command_exists docker; then print_warn "Docker no disponible. No se puede desplegar Open WebUI."; return 0; fi
  command -v systemctl >/dev/null 2>&1 && $SUDO systemctl start docker || true

  docker volume inspect open-webui >/dev/null 2>&1 || docker volume create open-webui >/dev/null

  if docker ps -a --format '{{.Names}}' | grep -xq "$OPENWEBUI_CONTAINER"; then
    if docker ps --format '{{.Names}}' | grep -xq "$OPENWEBUI_CONTAINER"; then
      print_ok "Open WebUI ya esta ejecutandose"; return 0
    fi
    docker start "$OPENWEBUI_CONTAINER" >/dev/null
    print_ok "Open WebUI existente iniciado"; return 0
  fi

  print_info "Desplegando Open WebUI en Docker..."
  docker run -d \
    --name "$OPENWEBUI_CONTAINER" \
    --restart unless-stopped \
    --add-host=host.docker.internal:host-gateway \
    -p "${OPENWEBUI_PORT_HOST}:${OPENWEBUI_PORT_CONTAINER}" \
    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
    -v open-webui:/app/backend/data \
    "$OPENWEBUI_IMAGE" >/dev/null
  print_ok "Open WebUI desplegado en http://localhost:${OPENWEBUI_PORT_HOST}"
}

print_summary() {
  print_header "RESUMEN DEL LABORATORIO IA"
  printf "%b\n" "${C_BOLD}Ruta base:${C_RESET} $LAB_ROOT"
  printf "%b\n" "${C_BOLD}Agente Telegram:${C_RESET} $AGENT_SCRIPT"
  printf "%b\n" "${C_BOLD}Whitelist:${C_RESET} $WHITELIST_FILE"
  printf "%b\n" "${C_BOLD}Logs:${C_RESET} $LOGS_DIR"
  printf "%b\n" "${C_BOLD}Memoria:${C_RESET} $MEMORY_CONV_DIR"
  printf "%b\n" "${C_BOLD}WebUI:${C_RESET} http://localhost:${OPENWEBUI_PORT_HOST}"
  printf "%b\n" "${C_BOLD}Log instalacion:${C_RESET} $INSTALL_LOG"
  cat <<EOF

Siguientes pasos:
1) Editar token Telegram:
   $AGENT_ENV_FILE
2) Agregar IDs permitidos:
   $WHITELIST_FILE
3) Reiniciar agente:
   sudo systemctl restart ai-lab-agent.service
EOF
}

main() {
  progress_step "Preparando entorno y validaciones base"
  ensure_sudo
  ensure_ubuntu_22_or_newer
  create_base_structure
  enable_install_logging
  print_header "INICIO DE INSTALACION AI LAB"

  progress_step "Instalando/verificando Python3"; install_python3_if_needed
  progress_step "Instalando/verificando NodeJS"; install_nodejs_if_needed
  progress_step "Instalando/verificando Docker"; install_docker_if_needed
  progress_step "Instalando/verificando Docker Compose"; install_docker_compose_if_needed
  progress_step "Instalando/verificando Ollama"; install_ollama_if_needed
  progress_step "Instalando/verificando telegram-cli"; install_telegram_cli_if_needed
  progress_step "Instalando/verificando Visual Studio Code"; install_vscode_if_needed
  progress_step "Creando estructura del laboratorio"; create_base_structure
  progress_step "Configurando whitelist de seguridad"; create_whitelist_file
  progress_step "Generando configuracion del agente (.env)"; create_agent_env
  progress_step "Generando codigo del agente Telegram"; create_agent_python
  progress_step "Normalizando permisos del agente"; normalize_agent_file_permissions
  progress_step "Configurando servicio systemd del agente"; create_systemd_service
  progress_step "Instalando/verificando modelos Ollama"; install_models_if_needed
  progress_step "Desplegando Open WebUI"; deploy_open_webui
  progress_step "Iniciando/reiniciando agente (si token configurado)"; start_or_warn_agent
  progress_step "Finalizando y mostrando resumen"; print_summary
  print_ok "Instalacion completada."
}

main "$@"
