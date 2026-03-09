#!/bin/bash
# ============================================================
#  AI LAB EXTREMO – Post-instalación para Debian 12/13
#  Uso: sudo bash postinstall-ai-lab.sh
# ============================================================

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Directorio del script y LOG ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/postinstall-$(date +%Y%m%d-%H%M%S).log"

# Crear log y redirigir toda la salida (stdout + stderr) a pantalla Y archivo
exec > >(tee -a "$LOG_FILE") 2>&1

echo "════════════════════════════════════════════════════════════"
echo "  AI LAB EXTREMO - Log iniciado: $(date)"
echo "  Archivo de log: $LOG_FILE"
echo "════════════════════════════════════════════════════════════"

# ── Colores ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✘]${NC} $*"; }
step() { echo -e "\n${CYAN}══════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}"; }

# ── Verificar root ──────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    err "Este script debe ejecutarse como root (usa sudo)."
    exit 1
fi

# ── Usuario destino ─────────────────────────────────────────
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
if [ "$TARGET_USER" = "root" ] || [ -z "$TARGET_USER" ]; then
    err "No se pudo detectar el usuario real. Ejecuta con: sudo bash $0"
    exit 1
fi
USER_HOME="/home/${TARGET_USER}"
log "Usuario destino: $TARGET_USER ($USER_HOME)"

# ── Función auxiliar: crear contenedor si no existe ─────────
ensure_container() {
    local name="$1"; shift
    if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
        if docker ps --format '{{.Names}}' | grep -qx "$name"; then
            log "Contenedor '$name' ya está corriendo"
        else
            warn "Contenedor '$name' existe pero está detenido, recreando con config actual..."
            docker rm "$name"
            docker run -d --name "$name" --restart always "$@"
        fi
    else
        log "Creando contenedor '$name'..."
        docker run -d --name "$name" --restart always "$@"
    fi
}

########################################
# 1. ACTUALIZAR SISTEMA
########################################
step "1/14 – Actualizar sistema"
apt-get update
apt-get upgrade -y
apt-get install -y \
    git curl wget build-essential tmux htop neovim zsh \
    gnome-tweaks gnome-shell-extensions gnupg \
    ca-certificates lsb-release \
    unzip openssl
log "Paquetes base instalados"

########################################
# 2. GNOME – TEMAS Y CONFIGURACIÓN
########################################
step "2/14 – GNOME temas y configuración"
apt-get install -y arc-theme papirus-icon-theme
sudo -u "$TARGET_USER" gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM' 2>/dev/null || true
sudo -u "$TARGET_USER" gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 48 2>/dev/null || true
log "GNOME configurado"

########################################
# 3. VISUAL STUDIO CODE
########################################
step "3/14 – Visual Studio Code"
if ! command -v code &>/dev/null; then
    # Limpiar fuentes duplicadas previas
    rm -f /etc/apt/sources.list.d/vscode.sources
    apt-get install -y gnupg
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
    chmod 644 /usr/share/keyrings/packages.microsoft.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        > /etc/apt/sources.list.d/vscode.list
    apt-get update
    apt-get install -y code
    log "VS Code instalado"
else
    log "VS Code ya instalado"
fi

########################################
# 4. NODE.JS (LTS)
########################################
step "4/14 – Node.js"
if ! command -v node &>/dev/null; then
    # Intentar NodeSource, si falla usar paquete de Debian
    if curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - 2>/dev/null; then
        apt-get install -y nodejs
    else
        warn "NodeSource no soporta Debian 13, instalando desde repos de Debian"
        apt-get install -y nodejs npm
    fi
    log "Node.js instalado ($(node --version))"
else
    log "Node.js ya instalado ($(node --version))"
fi

########################################
# 5. DOCKER CE (desde repo oficial)
########################################
step "5/14 – Docker"
if ! command -v docker &>/dev/null; then
    # Eliminar paquetes conflictivos de Debian
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        apt-get remove -y "$pkg" 2>/dev/null || true
    done

    # Agregar repo oficial de Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    ARCH=$(dpkg --print-architecture)
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    # Debian 13 (trixie) puede no tener repo Docker oficial aún, usar bookworm como fallback
    if [ "$CODENAME" = "trixie" ]; then
        warn "Debian 13 detectado: usando repositorio Docker de bookworm (compatible)"
        CODENAME="bookworm"
    fi
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $CODENAME stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    log "Docker CE instalado"
else
    log "Docker ya instalado ($(docker --version))"
fi

# Asegurar servicio activo y usuario en grupo docker
systemctl enable --now docker
usermod -aG docker "$TARGET_USER" 2>/dev/null || true
log "Usuario '$TARGET_USER' en grupo docker (requiere re-login para efecto)"

########################################
# 6. PYTHON – PIP Y PAQUETES
########################################
step "6/14 – Python pip y paquetes"
apt-get install -y python3-pip python3-venv 2>/dev/null || true
pip3 install --break-system-packages --upgrade pip 2>/dev/null || pip3 install --upgrade pip
pip3 install --break-system-packages jupyterlab fastapi uvicorn psutil 2>/dev/null \
    || pip3 install jupyterlab fastapi uvicorn psutil
pip3 install --break-system-packages langchain llama-index crewai autogen-agentchat chromadb sentence-transformers 2>/dev/null \
    || pip3 install langchain llama-index crewai autogen-agentchat chromadb sentence-transformers
log "Paquetes Python instalados"

########################################
# 7. OLLAMA Y MODELOS
########################################
step "7/14 – Ollama y modelos LLM"
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
    log "Ollama instalado"
else
    log "Ollama ya instalado ($(ollama --version 2>/dev/null || echo 'OK'))"
fi

# Configurar Ollama para escuchar en todas las interfaces (necesario para Docker)
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/environment.conf <<'OCONF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
OCONF

systemctl daemon-reload
systemctl enable ollama 2>/dev/null || true
systemctl restart ollama 2>/dev/null || true

# Esperar a que Ollama esté listo (máx 30 s)
log "Esperando a que Ollama esté listo..."
for _i in $(seq 1 30); do
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        log "Ollama listo"
        break
    fi
    sleep 1
done
if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    warn "Ollama no respondió tras 30 s — los modelos se descargarán cuando arranque"
fi

MODELS=(llama3 mistral codellama gemma phi3)
for model in "${MODELS[@]}"; do
    if ollama list 2>/dev/null | grep -qi "${model}"; then
        log "Modelo '$model' ya descargado"
    else
        warn "Descargando modelo '$model' (esto puede tardar)..."
        ollama pull "$model" 2>/dev/null || warn "No se pudo descargar '$model' — reintenta con: ollama pull $model"
    fi
done

########################################
# 8. CONTENEDORES DOCKER
########################################
step "8/14 – Contenedores Docker"

# Generar clave segura para Open WebUI (256-bit)
WEBUI_SECRET_KEY=$(openssl rand -hex 32)

ensure_container "open-webui" \
    --network=host \
    -e PORT=3001 \
    -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
    -e WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" \
    -v open-webui:/app/backend/data \
    ghcr.io/open-webui/open-webui:main

ensure_container "grafana" \
    -p 3000:3000 grafana/grafana

ensure_container "prometheus" \
    -p 9090:9090 prom/prometheus

ensure_container "minio" \
    -p 9000:9000 -p 9001:9001 \
    -e MINIO_ROOT_USER=admin -e MINIO_ROOT_PASSWORD=password \
    minio/minio server /data --console-address ":9001"

log "Contenedores base configurados"

########################################
# 9. COMFYUI – GENERACIÓN DE IMÁGENES
########################################
step "9/14 – ComfyUI (Stable Diffusion)"

# Crear directorio para modelos
mkdir -p "$USER_HOME/comfyui-data/models"
mkdir -p "$USER_HOME/comfyui-data/output"

# Detectar si hay GPU NVIDIA disponible
HAS_GPU=false
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    HAS_GPU=true
    log "GPU NVIDIA detectada"
fi

if [ "$HAS_GPU" = true ]; then
    ensure_container "comfyui" \
        --gpus all \
        -p 8188:8188 \
        -v "$USER_HOME/comfyui-data/models:/app/models" \
        -v "$USER_HOME/comfyui-data/output:/app/output" \
        ghcr.io/ai-dock/comfyui:latest 2>/dev/null || \
        warn "ComfyUI con GPU falló"
else
    warn "Sin GPU NVIDIA - ComfyUI funcionará en modo CPU (lento)"
    ensure_container "comfyui" \
        -p 8188:8188 \
        -v "$USER_HOME/comfyui-data/models:/app/models" \
        -v "$USER_HOME/comfyui-data/output:/app/output" \
        -e PYTORCH_ENABLE_MPS_FALLBACK=1 \
        ghcr.io/ai-dock/comfyui:latest 2>/dev/null || \
        warn "ComfyUI no pudo iniciarse - instalar manualmente si se necesita"
fi

log "ComfyUI configurado (puerto 8188)"

########################################
# 10. COQUI TTS – GENERACIÓN DE AUDIO
########################################
step "10/14 – Coqui TTS (Text-to-Speech)"

mkdir -p "$USER_HOME/tts-data"

# Coqui TTS oficial está deprecado, usar alternativas mantenidas
# Opción 1: OpenedAI Speech (compatible con API OpenAI TTS)
if ! docker ps -a --format '{{.Names}}' | grep -qx "openedai-speech"; then
    log "Instalando OpenedAI Speech (alternativa moderna a Coqui)..."
    ensure_container "openedai-speech" \
        -p 5002:5002 \
        -v "$USER_HOME/tts-data:/app/voices" \
        ghcr.io/matatonic/openedai-speech:latest 2>/dev/null || \
        warn "OpenedAI Speech no pudo iniciarse"
else
    log "OpenedAI Speech ya configurado"
fi

# Opción 2: Piper TTS (muy ligero y rápido)
ensure_container "piper-tts" \
    -p 5003:5000 \
    -v "$USER_HOME/tts-data:/data" \
    rhasspy/wyoming-piper:latest \
    --voice es_ES-davefx-medium 2>/dev/null || \
    warn "Piper TTS no pudo iniciarse (opcional)"

log "TTS configurado (OpenedAI: 5002, Piper: 5003)"

########################################
# 11. ANIMATEDIFF – GENERACIÓN DE VIDEO
########################################
step "11/14 – AnimateDiff (Text-to-Video)"

mkdir -p "$USER_HOME/animatediff-data/output"
mkdir -p "$USER_HOME/animatediff-data/models"

# Instalar paquetes Python para video AI
pip3 install --break-system-packages diffusers transformers accelerate safetensors 2>/dev/null \
    || pip3 install diffusers transformers accelerate safetensors 2>/dev/null || true

# Script de ejemplo para generación de video
cat > "$USER_HOME/ai-agents/generate_video.py" <<'VIDEOF'
#!/usr/bin/env python3
"""
Generador de Video con AnimateDiff
Uso: python3 generate_video.py "tu prompt aquí"
"""
import sys
try:
    import torch
    from diffusers import AnimateDiffPipeline, MotionAdapter, EulerDiscreteScheduler
    from diffusers.utils import export_to_gif

    prompt = sys.argv[1] if len(sys.argv) > 1 else "A sunset over the ocean, cinematic"
    
    print(f"Generando video: {prompt}")
    
    adapter = MotionAdapter.from_pretrained("guoyww/animatediff-motion-adapter-v1-5-2")
    pipe = AnimateDiffPipeline.from_pretrained(
        "runwayml/stable-diffusion-v1-5",
        motion_adapter=adapter,
        torch_dtype=torch.float16
    )
    pipe.scheduler = EulerDiscreteScheduler.from_config(pipe.scheduler.config)
    
    if torch.cuda.is_available():
        pipe = pipe.to("cuda")
    
    output = pipe(prompt=prompt, num_frames=16, guidance_scale=7.5, num_inference_steps=25)
    export_to_gif(output.frames[0], "output_video.gif")
    print("Video guardado: output_video.gif")
    
except ImportError as e:
    print(f"Instala dependencias: pip3 install diffusers transformers accelerate torch")
    print(f"Error: {e}")
except Exception as e:
    print(f"Error generando video: {e}")
VIDEOF

log "AnimateDiff configurado"

########################################
# 12. AI AGENTS DE EJEMPLO
########################################
step "12/14 – AI Agents de ejemplo"
mkdir -p "$USER_HOME/ai-agents"

cat > "$USER_HOME/ai-agents/agents.py" <<'PYEOF'
from crewai import Agent, Task, Crew

research = Agent(role="Researcher", goal="Research tech", backstory="AI researcher")
coder = Agent(role="Developer", goal="Write software", backstory="Senior dev")
tester = Agent(role="Tester", goal="Test software", backstory="QA engineer")

task = Task(description="Create Python REST API", agent=coder)

crew = Crew(agents=[research, coder, tester], tasks=[task])
print(crew.run())
PYEOF
log "agents.py creado"

########################################
# 10. AI CONTROL CENTER + SERVICIOS
########################################
step "13/14 – AI Control Center y servicios systemd"
mkdir -p "$USER_HOME/ai-control-center"

cat > "$USER_HOME/ai-control-center/index.html" <<'HTMLEOF'
<html>
<head>
<title>AI CONTROL CENTER</title>
<style>
body {font-family:Arial; background:#111; color:white; text-align:center; padding:20px;}
h1 {color:#0ff; margin-bottom:10px;}
.section-title {color:#888; font-size:14px; margin:20px 0 10px; text-transform:uppercase;}
.grid {display:grid; grid-template-columns:repeat(3,1fr); gap:20px; margin:0 auto; max-width:900px;}
.card {background:#222; padding:30px 20px; border-radius:10px; cursor:pointer; transition:all 0.3s;}
.card:hover {background:#333; transform:scale(1.02);}
.card.llm {border-left:4px solid #0f0;}
.card.media {border-left:4px solid #f0f;}
.card.monitor {border-left:4px solid #ff0;}
.card.storage {border-left:4px solid #0ff;}
.icon {font-size:24px; margin-bottom:8px;}
</style>
</head>
<body>
<h1>🤖 AI CONTROL CENTER</h1>
<p class="section-title">Modelos de Lenguaje</p>
<div class="grid">
<div class="card llm" onclick="chat()"><div class="icon">💬</div>AI Chat</div>
<div class="card llm" onclick="ollama()"><div class="icon">🦙</div>Ollama API</div>
<div class="card llm" onclick="jupyter()"><div class="icon">📓</div>JupyterLab</div>
</div>
<p class="section-title">Generación Multimedia</p>
<div class="grid">
<div class="card media" onclick="comfyui()"><div class="icon">🎨</div>ComfyUI<br><small>Imágenes</small></div>
<div class="card media" onclick="tts()"><div class="icon">🔊</div>OpenedAI Speech<br><small>Voces API</small></div>
<div class="card media" onclick="piper()"><div class="icon">🎤</div>Piper TTS<br><small>Voces rápidas</small></div>
</div>
<p class="section-title">Monitoreo y Almacenamiento</p>
<div class="grid">
<div class="card monitor" onclick="grafana()"><div class="icon">📊</div>Grafana</div>
<div class="card monitor" onclick="prom()"><div class="icon">📈</div>Prometheus</div>
<div class="card storage" onclick="minio()"><div class="icon">💾</div>MinIO</div>
</div>
<script>
function chat(){window.open("http://localhost:3001")}
function ollama(){window.open("http://localhost:11434")}
function jupyter(){window.open("http://localhost:8888")}
function comfyui(){window.open("http://localhost:8188")}
function tts(){window.open("http://localhost:5002")}
function piper(){window.open("http://localhost:5003")}
function grafana(){window.open("http://localhost:3000")}
function prom(){window.open("http://localhost:9090")}
function minio(){window.open("http://localhost:9001")}
</script>
</body>
</html>
HTMLEOF

cat > "$USER_HOME/ai-control-center/server.py" <<'PYEOF'
from fastapi import FastAPI
from fastapi.responses import FileResponse

app = FastAPI()

@app.get("/")
def home():
    return FileResponse("index.html")
PYEOF

# Servicio: AI Control Center
cat > /etc/systemd/system/ai-control-center.service <<EOF
[Unit]
Description=AI Control Center
After=network.target
[Service]
User=$TARGET_USER
Environment=HOME=$USER_HOME
WorkingDirectory=$USER_HOME/ai-control-center
ExecStart=/usr/bin/env python3 -m uvicorn server:app --host 0.0.0.0 --port 5050
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Servicio: JupyterLab
cat > /etc/systemd/system/jupyterlab.service <<EOF
[Unit]
Description=JupyterLab
After=network.target
[Service]
User=$TARGET_USER
Environment=HOME=$USER_HOME
WorkingDirectory=$USER_HOME
ExecStart=/usr/bin/env jupyter-lab --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.token='' --ServerApp.password=''
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ai-control-center
systemctl enable --now jupyterlab
log "Servicios systemd configurados y activos"

########################################
# 11. ACCESOS DIRECTOS GNOME
########################################
step "14/14 – Accesos directos GNOME"
mkdir -p "$USER_HOME/.local/share/applications"

declare -A SHORTCUTS=(
    ["ai-control"]="AI Control Center|http://localhost:5050|applications-system"
    ["ai-chat"]="AI Chat|http://localhost:3001|utilities-terminal"
    ["jupyter-ai"]="JupyterLab|http://localhost:8888|applications-science"
    ["comfyui-ai"]="ComfyUI Imágenes|http://localhost:8188|applications-graphics"
    ["openedai-speech"]="OpenedAI Speech|http://localhost:5002|audio-x-generic"
    ["piper-tts"]="Piper TTS|http://localhost:5003|audio-speakers"
    ["grafana-ai"]="Grafana Monitoring|http://localhost:3000|utilities-system-monitor"
    ["prometheus-ai"]="Prometheus Metrics|http://localhost:9090|utilities-system-monitor"
    ["minio-ai"]="MinIO Storage|http://localhost:9001|folder-cloud"
)

for key in "${!SHORTCUTS[@]}"; do
    IFS='|' read -r name url icon <<< "${SHORTCUTS[$key]}"
    cat > "$USER_HOME/.local/share/applications/${key}.desktop" <<DEOF
[Desktop Entry]
Name=$name
Exec=xdg-open $url
Icon=$icon
Type=Application
Terminal=false
Categories=Development;
DEOF
done
log "Accesos directos creados"

########################################
# PERMISOS Y LIMPIEZA
########################################
chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/ai-control-center"
chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/ai-agents"
chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/comfyui-data" 2>/dev/null || true
chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/tts-data" 2>/dev/null || true
chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/animatediff-data" 2>/dev/null || true
chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.local/share/applications"
log "Permisos corregidos"

########################################
# VERIFICACIÓN FINAL
########################################
step "Verificación final"
FAIL=0
for cmd in git docker node npm python3 pip3 ollama code jupyter nvim; do
    if command -v "$cmd" &>/dev/null; then
        log "$cmd → OK"
    else
        err "$cmd → NO ENCONTRADO"
        FAIL=1
    fi
done

for svc in docker ai-control-center jupyterlab ollama; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        log "Servicio $svc → activo"
    else
        warn "Servicio $svc → inactivo"
    fi
done

for ctr in open-webui grafana prometheus minio comfyui openedai-speech piper-tts; do
    if docker ps --format '{{.Names}}' | grep -qx "$ctr"; then
        log "Contenedor $ctr → corriendo"
    else
        warn "Contenedor $ctr → no corriendo (puede requerir GPU o config manual)"
    fi
done

echo ""
echo -e "${GREEN}###########################################${NC}"
echo -e "${GREEN}##       AI LAB EXTREMO — LISTO          ##${NC}"
echo -e "${GREEN}###########################################${NC}"
echo ""
echo "  ═══ MODELOS DE LENGUAJE ═══"
echo "  Control Center : http://localhost:5050"
echo "  AI Chat        : http://localhost:3001"
echo "  JupyterLab     : http://localhost:8888"
echo "  Ollama API     : http://localhost:11434"
echo ""
echo "  ═══ GENERACIÓN MULTIMEDIA ═══"
echo "  ComfyUI (IMG)  : http://localhost:8188"
echo "  OpenedAI Speech: http://localhost:5002"
echo "  Piper TTS      : http://localhost:5003"
echo ""
echo "  ═══ MONITOREO ═══"
echo "  Grafana        : http://localhost:3000"
echo "  Prometheus     : http://localhost:9090"
echo "  MinIO Console  : http://localhost:9001"
echo "  MinIO API      : http://localhost:9000"
echo ""
if [ "$FAIL" -eq 0 ]; then
    log "Instalación completada exitosamente."
else
    warn "Algunas herramientas no se instalaron. Revisa los mensajes arriba."
fi
echo ""
warn "IMPORTANTE: Cierra sesión y vuelve a iniciar para usar Docker sin sudo."
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Log guardado en: $LOG_FILE"
echo "  Finalizado: $(date)"
echo "════════════════════════════════════════════════════════════"
