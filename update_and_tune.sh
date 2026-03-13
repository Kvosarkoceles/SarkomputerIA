#!/bin/bash

# Script para actualizar Ubuntu 24.04 y personalizar GNOME con temas satánicos
# Compatible con múltiples GPUs (NVIDIA, AMD, Intel) - Sin conflictos
# Autor: [Tu Nombre]
# Fecha: $(date)

# Variables de color para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Obtener usuario real (no root)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Función para ejecutar gsettings como el usuario real
run_as_user() {
    sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $REAL_USER)/bus" "$@"
}

# Función para imprimir mensajes
print_message() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# ═══════════════════════════════════════════════════════════════
# FUNCIÓN PARA APLICAR TEMAS SATÁNICOS
# ═══════════════════════════════════════════════════════════════
apply_satanic_themes() {
    print_message "Aplicando temas satánicos..."

    # Tema oscuro compatible con GNOME Flashback para evitar menús invisibles
    if [ -d "/usr/share/themes/Yaru-dark" ]; then
        SATANIC_GTK_THEME="Yaru-dark"
    else
        SATANIC_GTK_THEME="Adwaita-dark"
    fi
    
    # GNOME: Tema oscuro
    run_as_user gsettings set org.gnome.desktop.interface gtk-theme "$SATANIC_GTK_THEME" 2>/dev/null || true
    run_as_user gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true

    # Tema de ventanas para GNOME Flashback/Metacity
    run_as_user gsettings set org.gnome.desktop.wm.preferences theme "$SATANIC_GTK_THEME" 2>/dev/null || \
    run_as_user gsettings set org.gnome.desktop.wm.preferences theme "Adwaita" 2>/dev/null || true
    run_as_user gsettings set org.gnome.metacity.theme name "Adwaita" 2>/dev/null || true
    
    # Terminal: Colores satánicos (rojo/negro)
    run_as_user dconf write /org/gnome/terminal/legacy/theme-variant "'dark'" 2>/dev/null || true
    
    # Fondo de pantalla satánico
    SATANIC_BG="$REAL_HOME/.local/share/backgrounds/satanic-dark.png"
    mkdir -p "$(dirname "$SATANIC_BG")"
    
    # Crear fondo satánico si no existe
    if ! [ -f "$SATANIC_BG" ] && command -v convert &>/dev/null; then
        convert -size 1920x1080 gradient:'#000000-#3d0000' "$SATANIC_BG" 2>/dev/null || true
    fi
    
    if [ -f "$SATANIC_BG" ]; then
        run_as_user gsettings set org.gnome.desktop.background picture-uri "file://$SATANIC_BG" 2>/dev/null || true
        run_as_user gsettings set org.gnome.desktop.background picture-uri-dark "file://$SATANIC_BG" 2>/dev/null || true
    fi

    # CSS para forzar contraste y visibilidad de menús/panel en Flashback
    GTK3_DIR="$REAL_HOME/.config/gtk-3.0"
    mkdir -p "$GTK3_DIR"
    cat > "$GTK3_DIR/gtk.css" << 'CSS_EOF'
/* Flashback panel: menús legibles con estética rojo/negro */
#PanelToplevel,
.gnome-panel-menu-bar,
.gnome-panel-menu-bar menubar,
.gnome-panel-menu-bar menuitem,
.gnome-panel-menu-bar label,
.gnome-panel-menu-button,
.gnome-panel-menu-button label {
    background-color: rgba(12, 0, 0, 0.88);
    color: #ff4d4d;
}

#PanelToplevel *:hover,
.gnome-panel-menu-bar menuitem:hover,
.gnome-panel-menu-button:hover {
    background-color: rgba(45, 0, 0, 0.95);
    color: #ffd0d0;
}
CSS_EOF
    chown "$REAL_USER":"$REAL_USER" "$GTK3_DIR/gtk.css" 2>/dev/null || true
    
    print_success "Temas satánicos aplicados y panel con alto contraste"
}

# Función para verificar si estamos en Ubuntu
check_ubuntu() {
    if ! grep -qi "Ubuntu" /etc/os-release; then
        print_error "Este script es solo para sistemas Ubuntu 24.04."
        exit 1
    fi
    
    # Verificar versión Ubuntu 24.04+
    UBUNTU_VERSION=$(grep "VERSION_ID" /etc/os-release | cut -d'"' -f2)
    if [[ "$UBUNTU_VERSION" < "24.04" ]]; then
        print_warning "Se recomienda Ubuntu 24.04 o superior. Versión actual: $UBUNTU_VERSION"
    fi
}

# Función para verificar si el usuario es root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script debe ejecutarse con privilegios de root (sudo)."
        exit 1
    fi
}

# Detectar e instalar drivers de hardware SIN CONFLICTOS
install_hardware_drivers() {
    print_message "Detectando hardware del sistema..."
    
    # ═══════════════════════════════════════════════════════════════
    # DETECCIÓN DE GPU (CON PREVENCIÓN DE CONFLICTOS)
    # ═══════════════════════════════════════════════════════════════
    
    # Usar ubuntu-drivers para instalación segura
    if command -v ubuntu-drivers &>/dev/null; then
        print_message "Usando ubuntu-drivers para instalación segura de drivers..."
        
        # Detectar y listar dispositivos
        DETECTED_DEVICES=$(ubuntu-drivers devices 2>/dev/null | grep -E "driver :" | head -1)
        
        if [ -n "$DETECTED_DEVICES" ]; then
            print_message "Dispositivos detectados: $DETECTED_DEVICES"
            
            # Instalar recomendado (solo instala lo compatible)
            ubuntu-drivers autoinstall 2>/dev/null && \
            print_success "Drivers instalados via ubuntu-drivers" || \
            print_warning "ubuntu-drivers no pudo instalar automáticamente"
        fi
    fi
    
    # Detección manual con prevención de conflictos
    print_message "Verificando GPUs disponibles..."
    
    HAS_NVIDIA=false
    HAS_AMD=false
    HAS_INTEL=false
    
    # Detectar GPU NVIDIA
    if lspci 2>/dev/null | grep -qi "nvidia"; then
        print_message "GPU NVIDIA detectada"
        HAS_NVIDIA=true
        
        # Desinstalar driver nouveau conflictivo ANTES de instalar NVIDIA
        if lsmod 2>/dev/null | grep -q "nouveau"; then
            print_warning "Driver opengl 'nouveau' detectado, desinstalando..."
            apt remove -y xserver-xorg-video-nouveau 2>/dev/null || true
            modprobe -r nouveau 2>/dev/null || true
        fi
        
        # Agregar repo de NVIDIA si es necesario
        if ! dpkg -l | grep -q "nvidia-driver-"; then
            print_message "Instalando drivers NVIDIA (a través de ubuntu-drivers)..."
            # Intentar instalar vía ubuntu-drivers primero
            if ! ubuntu-drivers autoinstall 2>/dev/null; then
                # Fallback: instalar genérico
                apt install -y nvidia-driver 2>/dev/null || \
                print_warning "No se pudo instalar driver NVIDIA - puede requerir instalación manual"
            fi
        else
            NVIDIA_VERSION=$(dpkg -l | grep nvidia-driver | awk '{print $3}' | tail -1)
            print_success "Driver NVIDIA ya instalado (v$NVIDIA_VERSION)"
        fi
    fi
    
    # Detectar GPU AMD (Radeon/RDNA/NAVI)
    if lspci 2>/dev/null | grep -qi "amd.*radeon\|amd.*vega\|amd.*navi\|amd.*wcn"; then
        print_message "GPU AMD detectada"
        HAS_AMD=true
        
        # Solo instalar firmware, no drivers conflictivos
        print_message "Instalando soporte AMD (firmware, no driver de kernel)..."
        apt install -y firmware-amd-graphics mesa-vulkan-drivers libvulkan1 2>/dev/null || true
        apt install -y libdrm-amdgpu1 2>/dev/null || true
        print_success "Drivers AMD configurados"
    fi
    
    # Detectar GPU Intel (UHD, Iris, Xe)
    if lspci 2>/dev/null | grep -qi "intel.*graphics\|intel.*uhd\|intel.*iris\|intel.*xe"; then
        print_message "GPU Intel detectada"
        HAS_INTEL=true
        
        print_message "Instalando soporte Intel..."
        apt install -y intel-media-va-driver mesa-vulkan-drivers libvulkan1 2>/dev/null || true
        apt install -y intel-gpu-tools 2>/dev/null || true
        print_success "Drivers Intel configurados"
    fi
    
    # ═══════════════════════════════════════════════════════════════
    # WIFI Y BLUETOOTH
    # ═══════════════════════════════════════════════════════════════
    
    # Detectar WiFi que necesita firmware
    print_message "Verificando firmware WiFi..."
    
    # Intel WiFi
    if lspci 2>/dev/null | grep -qi "intel.*wireless\|intel.*wifi\|intel.*centrino"; then
        apt install -y firmware-iwlwifi 2>/dev/null || true
        print_success "Firmware Intel WiFi instalado"
    fi
    
    # Realtek WiFi
    if lspci 2>/dev/null | grep -qi "realtek.*rtl\|realtek.*wireless"; then
        apt install -y firmware-realtek 2>/dev/null || true
        print_success "Firmware Realtek instalado"
    fi
    
    # Broadcom WiFi (común en laptops)
    if lspci 2>/dev/null | grep -qi "broadcom.*bcm\|broadcom.*wireless"; then
        apt install -y firmware-brcm80211 2>/dev/null || \
        apt install -y broadcom-sta-dkms 2>/dev/null || true
        print_success "Firmware Broadcom instalado"
    fi
    
    # Atheros/Qualcomm WiFi
    if lspci 2>/dev/null | grep -qi "atheros\|qualcomm.*ath"; then
        apt install -y firmware-atheros firmware-ath9k-htc 2>/dev/null || true
        print_success "Firmware Atheros instalado"
    fi
    
    # MediaTek WiFi
    if lspci 2>/dev/null | grep -qi "mediatek\|ralink"; then
        apt install -y firmware-misc-nonfree 2>/dev/null || true
        print_success "Firmware MediaTek instalado"
    fi
    
    # Bluetooth
    print_message "Verificando Bluetooth..."
    if lsusb 2>/dev/null | grep -qi "bluetooth" || lspci 2>/dev/null | grep -qi "bluetooth"; then
        apt install -y bluetooth bluez bluez-tools blueman 2>/dev/null || true
        systemctl enable bluetooth 2>/dev/null || true
        systemctl start bluetooth 2>/dev/null || true
        print_success "Bluetooth configurado"
    fi
    
    # ═══════════════════════════════════════════════════════════════
    # AUDIO
    # ═══════════════════════════════════════════════════════════════
    
    print_message "Verificando audio..."
    
    # PipeWire (moderno) o PulseAudio
    if ! command -v pw-cli &>/dev/null; then
        apt install -y pipewire pipewire-audio pipewire-pulse wireplumber 2>/dev/null || \
        apt install -y pulseaudio pulseaudio-utils pavucontrol 2>/dev/null || true
    fi
    
    # Firmware de audio
    apt install -y firmware-sof-signed 2>/dev/null || true  # Intel SOF
    
    # Códecs multimedia
    apt install -y gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav ffmpeg 2>/dev/null || true
    
    print_success "Audio configurado"
    
    # ═══════════════════════════════════════════════════════════════
    # TOUCHPAD Y DISPOSITIVOS DE ENTRADA
    # ═══════════════════════════════════════════════════════════════
    
    print_message "Verificando dispositivos de entrada..."
    
    # Drivers de touchpad
    apt install -y xserver-xorg-input-libinput xserver-xorg-input-synaptics 2>/dev/null || true
    
    # Wacom tablets
    if lsusb 2>/dev/null | grep -qi "wacom"; then
        apt install -y xserver-xorg-input-wacom 2>/dev/null || true
        print_success "Driver Wacom instalado"
    fi
    
    # ═══════════════════════════════════════════════════════════════
    # IMPRESORAS Y ESCÁNERES
    # ═══════════════════════════════════════════════════════════════
    
    print_message "Configurando soporte de impresoras..."
    apt install -y cups cups-bsd cups-client system-config-printer \
        printer-driver-all hplip 2>/dev/null || true
    systemctl enable cups 2>/dev/null || true
    
    # Escáneres
    apt install -y sane sane-utils simple-scan 2>/dev/null || true
    
    print_success "Impresoras y escáneres configurados"
    
    # ═══════════════════════════════════════════════════════════════
    # SENSORES Y GESTIÓN DE ENERGÍA (LAPTOPS)
    # ═══════════════════════════════════════════════════════════════
    
    # Detectar si es laptop
    if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
        print_message "Laptop detectada - instalando herramientas de energía..."
        apt install -y tlp tlp-rdw powertop acpi acpid 2>/dev/null || true
        systemctl enable tlp 2>/dev/null || true
        
        # Herramientas de ThinkPad
        if dmidecode -s system-manufacturer 2>/dev/null | grep -qi "lenovo"; then
            apt install -y thinkfan tp-smapi-dkms 2>/dev/null || true
        fi
        
        print_success "Gestión de energía configurada"
    fi
    
    # Sensores de temperatura
    apt install -y lm-sensors hddtemp 2>/dev/null || true
    sensors-detect --auto 2>/dev/null || true
    
    # ═══════════════════════════════════════════════════════════════
    # FIRMWARE ADICIONAL
    # ═══════════════════════════════════════════════════════════════
    
    print_message "Instalando firmware adicional..."
    apt install -y firmware-linux 2>/dev/null || true
    
    # Mucode (Intel/AMD) - a menudo necesario
    apt install -y amd64-microcode intel-microcode 2>/dev/null || true
    
    # ═══════════════════════════════════════════════════════════════
    # VERIFICAR HARDWARE SIN DRIVER
    # ═══════════════════════════════════════════════════════════════
    
    print_message "Verificando hardware sin driver..."
    
    # Mostrar dispositivos sin driver
    MISSING_DRIVERS=$(lspci -k 2>/dev/null | grep -A2 "Kernel driver in use" | grep -B1 "^--$" | grep -v "^--$" || true)
    
    if [ -n "$MISSING_DRIVERS" ]; then
        print_warning "Algunos dispositivos pueden no tener driver:"
        echo "$MISSING_DRIVERS" | head -10
    else
        print_success "Todos los dispositivos PCI tienen driver"
    fi
    
    # Verificar módulos cargados
    print_message "Módulos de kernel cargados: $(lsmod | wc -l)"
    
    print_success "Verificación de hardware completada"
}

# Actualizar sistema Ubuntu 24.04
update_system() {
    print_message "Limpiando repositorios duplicados..."
    # Eliminar archivo contrib.list si existe y está duplicado con sources.list
    if [ -f /etc/apt/sources.list.d/contrib.list ]; then
        rm -f /etc/apt/sources.list.d/contrib.list
        print_success "Repositorios duplicados eliminados"
    fi
    
    print_message "Actualizando repositorios APT..."
    apt update
    
    print_message "Actualizando sistema..."
    apt upgrade -y
    
    print_message "Actualizando distribuciones..."
    apt dist-upgrade -y
    
    print_message "Instalando dependencias base..."
    apt install -y imagemagick fonts-dejavu dconf-cli ubuntu-drivers-common 2>/dev/null || true
    
    print_message "Limpiando paquetes innecesarios..."
    apt autoremove -y
    apt autoclean
    
    print_success "Sistema Ubuntu 24.04 actualizado completamente."
}

# Instalar y configurar GNOME Flashback con mejoras
install_gnome_tweaks() {
    print_message "Instalando GNOME Flashback y componentes..."
    
    # Paquetes base de GNOME Flashback
    apt install -y \
        gnome-flashback \
        gnome-session-flashback \
        gnome-panel \
        gnome-menus \
        gnome-tweaks \
        dconf-editor \
        gnome-applets

    # Applets extra para mejorar compatibilidad del panel superior en Flashback/Compiz
    apt install -y indicator-applet indicator-applet-complete 2>/dev/null || true
    
    print_message "Instalando herramientas de personalización..."
    apt install -y \
        plank \
        xfce4-terminal \
        fonts-font-awesome \
        qt5ct \
        lxappearance
    
    print_success "Componentes de GNOME instalados."
}

# Configurar temas y animaciones con estilos satánicos
configure_themes_and_animations() {
    print_message "Instalando temas modernos (Ubuntu 24.04)..."
    
    # Instalar temas populares (compatibles con Ubuntu 24.04)
    apt install -y \
        adwaita-icon-theme \
        arc-theme \
        papirus-icon-theme 2>/dev/null || true
    
    # ═══════════════════════════════════════════════════════════════
    # ICONOS MODERNOS CON ESTILO 3D/GRADIENTE
    # ═══════════════════════════════════════════════════════════════
    
    print_message "Instalando iconos modernos (Tela, Numix, Reversal)..."
    
    # Tela Icons - iconos con gradientes y sombras (muy populares)
    if [ ! -d "/usr/share/icons/Tela" ]; then
        print_message "Instalando Tela Icons..."
        git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git /tmp/tela-icons 2>/dev/null && \
        cd /tmp/tela-icons && ./install.sh -a 2>/dev/null && \
        rm -rf /tmp/tela-icons && \
        print_success "Tela Icons instalados" || \
        print_warning "No se pudo instalar Tela Icons"
    fi
    
    # Numix Circle - iconos circulares con colores vibrantes
    if [ ! -d "/usr/share/icons/Numix-Circle" ]; then
        print_message "Instalando Numix Circle Icons..."
        apt install -y numix-icon-theme numix-icon-theme-circle 2>/dev/null || \
        (git clone --depth 1 https://github.com/numixproject/numix-icon-theme-circle.git /tmp/numix-circle 2>/dev/null && \
        cp -r /tmp/numix-circle/Numix-Circle /usr/share/icons/ && \
        rm -rf /tmp/numix-circle) || true
    fi
    
    # Reversal Icons - iconos con estilo moderno y gradientes
    if [ ! -d "/usr/share/icons/Reversal" ]; then
        print_message "Instalando Reversal Icons..."
        git clone --depth 1 https://github.com/yeyushengfan258/Reversal-icon-theme.git /tmp/reversal-icons 2>/dev/null && \
        cd /tmp/reversal-icons && ./install.sh -a 2>/dev/null && \
        rm -rf /tmp/reversal-icons && \
        print_success "Reversal Icons instalados" || true
    fi
    
    # Kora Icons - iconos con sombras y profundidad
    if [ ! -d "/usr/share/icons/kora" ]; then
        print_message "Instalando Kora Icons..."
        git clone --depth 1 https://github.com/bikass/kora.git /tmp/kora-icons 2>/dev/null && \
        cp -r /tmp/kora-icons/kora* /usr/share/icons/ && \
        rm -rf /tmp/kora-icons && \
        print_success "Kora Icons instalados" || true
    fi
    
    # Papirus con colores personalizados (más vibrantes)
    if command -v papirus-folders &>/dev/null || [ -f /usr/bin/papirus-folders ]; then
        papirus-folders -C blue --theme Papirus-Dark 2>/dev/null || true
    fi
    
    # Actualizar caché de iconos
    gtk-update-icon-cache /usr/share/icons/Tela 2>/dev/null || true
    gtk-update-icon-cache /usr/share/icons/Reversal 2>/dev/null || true
    gtk-update-icon-cache /usr/share/icons/kora 2>/dev/null || true
    
    # Clonar temas adicionales desde GitHub (opcional)
    print_message "Instalando tema Nordic desde GitHub..."
    
    # Nordic Theme (popular tema oscuro) - versión actual
    if [ ! -d "/usr/share/themes/Nordic" ]; then
        # Usar la última release disponible
        NORDIC_URL=$(curl -s https://api.github.com/repos/EliverLara/Nordic/releases/latest | grep -oP '"browser_download_url": "\K[^"]*Nordic\.tar\.xz' | head -1)
        if [ -n "$NORDIC_URL" ]; then
            wget -q --show-progress -O /tmp/nordic-theme.tar.xz "$NORDIC_URL" && \
            tar -xf /tmp/nordic-theme.tar.xz -C /usr/share/themes/ && \
            rm /tmp/nordic-theme.tar.xz && \
            print_success "Nordic theme instalado" || \
            print_warning "No se pudo instalar Nordic theme"
        else
            # Fallback: clonar repositorio
            print_message "Clonando Nordic desde git..."
            git clone --depth 1 https://github.com/EliverLara/Nordic.git /usr/share/themes/Nordic 2>/dev/null || \
            print_warning "No se pudo clonar Nordic theme"
        fi
    fi
    
    # Configurar temas en GNOME
    print_message "Aplicando estilo satánico consistente..."
    
    # Configurar iconos (prioridad: Tela > Reversal > Kora > Papirus)
    if [ -d "/usr/share/icons/Tela-blue-dark" ]; then
        run_as_user gsettings set org.gnome.desktop.interface icon-theme "Tela-blue-dark"
        print_success "Iconos: Tela Blue Dark"
    elif [ -d "/usr/share/icons/Tela" ]; then
        run_as_user gsettings set org.gnome.desktop.interface icon-theme "Tela"
        print_success "Iconos: Tela"
    elif [ -d "/usr/share/icons/Reversal-blue-dark" ]; then
        run_as_user gsettings set org.gnome.desktop.interface icon-theme "Reversal-blue-dark"
        print_success "Iconos: Reversal Blue Dark"
    elif [ -d "/usr/share/icons/kora" ]; then
        run_as_user gsettings set org.gnome.desktop.interface icon-theme "kora"
        print_success "Iconos: Kora"
    else
        run_as_user gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
        print_success "Iconos: Papirus Dark"
    fi
    
    run_as_user gsettings set org.gnome.desktop.interface cursor-theme "Adwaita"
    
    # Configurar animaciones
    print_message "Configurando animaciones..."
    
    # Activar animaciones en GNOME
    run_as_user gsettings set org.gnome.desktop.interface enable-animations true

    # Reforzar tema satánico en GTK/WM/fondos (evita que Nordic u otros lo sobrescriban)
    apply_satanic_themes
    
    print_success "Temas y animaciones configuradas."
}

# Optimizar rendimiento y efectos visuales
optimize_performance() {
    print_message "Optimizando rendimiento para animaciones..."
    
    # Instalar compositor mejorado (Compiz opcional)
    apt install -y compiz compiz-plugins compizconfig-settings-manager
    
    # Configurar GNOME Flashback para usar Compiz (opcional)
    if [ -f "/usr/bin/compiz" ]; then
        print_message "Configurar Compiz como compositor..."
        # Nota: Esto requiere configuración manual en ~/.config/compiz/compizconfig
    fi
    
    # Configurar caché para gráficos
    print_message "Configurar caché de gráficos..."
    
    # Para sistemas con GPU Intel
    if [ -d "/usr/share/drirc.d" ]; then
        cat > /usr/share/drirc.d/99-gnome-optimizations.conf << 'EOF'
<drirc>
    <!-- Optimización para Intel GPU -->
    <device screen="0" driver="intel">
        <application name="metacity">
            <option name="vblank_mode" value="0"/>
        </application>
        <application name="compiz">
            <option name="vblank_mode" value="0"/>
        </application>
    </device>
</drirc>
EOF
    fi
    
    print_success "Optimización de rendimiento aplicada."
}

# Configurar panel de GNOME Flashback
configure_gnome_panel() {
    print_message "Configurando panel de GNOME Flashback..."

    # Si el panel quedó sin applets/menús o sin menu-bar, restaurar diseño base.
    PANEL_OBJECTS=$(run_as_user gsettings get org.gnome.gnome-panel.layout object-id-list 2>/dev/null || echo "[]")
    if echo "$PANEL_OBJECTS" | grep -q "\[\]" || ! echo "$PANEL_OBJECTS" | grep -q "menu-bar"; then
        print_warning "Panel incompleto detectado, restaurando menús de GNOME Flashback..."
        run_as_user dconf reset -f /org/gnome/gnome-panel/ 2>/dev/null || true
        run_as_user gsettings reset-recursively org.gnome.gnome-panel.layout 2>/dev/null || true
    fi
    
    # Mantener top y bottom panel para conservar menú/ventanas como en Flashback clásico
    run_as_user gsettings set org.gnome.gnome-panel.layout toplevel-id-list "['top-panel','bottom-panel']" 2>/dev/null || true
    
    # Configurar Metacity (window manager de Flashback)
    run_as_user gsettings set org.gnome.metacity.theme name "Adwaita" 2>/dev/null || true
    run_as_user gsettings set org.gnome.mutter center-new-windows true 2>/dev/null || true
    
    # Configurar bordes de ventanas
    run_as_user gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"
    run_as_user gsettings set org.gnome.desktop.wm.preferences titlebar-font "Cantarell Bold 11"

    # Reaplicar colores satánicos para asegurar contraste en panel y menús
    apply_satanic_themes

    # Reiniciar panel para aplicar layout y applets de menú inmediatamente
    if pgrep -u "$REAL_USER" -x gnome-panel >/dev/null 2>&1; then
        run_as_user gnome-panel --replace >/dev/null 2>&1 &
    else
        run_as_user gnome-panel >/dev/null 2>&1 &
    fi
    
    print_success "Panel de GNOME Flashback configurado."
}

# Instalar aplicaciones adicionales para mejorar experiencia
install_additional_apps() {
    print_message "Instalando aplicaciones adicionales..."
    
    # Aplicaciones útiles para GNOME
    apt install -y \
        nemo \
        nemo-fileroller \
        gthumb \
        rhythmbox \
        celluloid \
        gnome-software \
        flatpak \
        gnome-boxes
    
    # Instalar herramientas de desarrollo (opcional)
    apt install -y \
        git \
        curl \
        wget \
        htop \
        fastfetch  # reemplazo moderno de neofetch en Debian 13
    
    print_success "Aplicaciones adicionales instaladas."
}

# Crear shortcuts y configurar hotkeys
configure_shortcuts() {
    print_message "Configurando shortcuts personalizados..."
    
    # Configurar shortcuts globales (ejemplos) - claves compatibles con GNOME 46+
    run_as_user gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']" 2>/dev/null || true
    run_as_user gsettings set org.gnome.settings-daemon.plugins.media-keys www "['<Super>b']" 2>/dev/null || true
    run_as_user gsettings set org.gnome.settings-daemon.plugins.media-keys screen-recorder "['<Super><Shift>s']" 2>/dev/null || true
    
    print_success "Shortcuts configurados."
}

# Configuración final y limpieza
final_configuration() {
    print_message "Aplicando configuración final..."
    
    # Crear directorio para wallpapers personalizados
    WALLPAPER_DIR="/usr/share/backgrounds/custom"
    mkdir -p "$WALLPAPER_DIR"
    
    print_message "Descargando wallpapers de alta calidad..."
    
    # Wallpapers de Unsplash (alta resolución, licencia libre)
    declare -A WALLPAPERS=(
        ["nature-mountains.jpg"]="https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=3840&q=90"
        ["ocean-sunset.jpg"]="https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=3840&q=90"
        ["forest-mist.jpg"]="https://images.unsplash.com/photo-1448375240586-882707db888b?w=3840&q=90"
        ["night-stars.jpg"]="https://images.unsplash.com/photo-1519681393784-d120267933ba?w=3840&q=90"
        ["abstract-gradient.jpg"]="https://images.unsplash.com/photo-1557683316-973673baf926?w=3840&q=90"
        ["city-lights.jpg"]="https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?w=3840&q=90"
        ["aurora-borealis.jpg"]="https://images.unsplash.com/photo-1531366936337-7c912a4589a7?w=3840&q=90"
        ["minimal-desert.jpg"]="https://images.unsplash.com/photo-1509316785289-025f5b846b35?w=3840&q=90"
    )
    
    for name in "${!WALLPAPERS[@]}"; do
        url="${WALLPAPERS[$name]}"
        path="$WALLPAPER_DIR/$name"
        if [ ! -f "$path" ]; then
            wget -q --show-progress -O "$path" "$url" 2>/dev/null && \
                print_success "Descargado: $name" || \
                print_warning "No se pudo descargar: $name"
        fi
    done
    
    # Establecer wallpaper por defecto sin perder estética satánica
    DEFAULT_WALLPAPER="$WALLPAPER_DIR/nature-mountains.jpg"
    SATANIC_BG="$REAL_HOME/.local/share/backgrounds/satanic-dark.png"
    if [ -f "$SATANIC_BG" ]; then
        run_as_user gsettings set org.gnome.desktop.background picture-uri "file://$SATANIC_BG"
        run_as_user gsettings set org.gnome.desktop.background picture-uri-dark "file://$SATANIC_BG"
        run_as_user gsettings set org.gnome.desktop.background picture-options "zoom"
    elif [ -f "$DEFAULT_WALLPAPER" ]; then
        run_as_user gsettings set org.gnome.desktop.background picture-uri "file://$DEFAULT_WALLPAPER"
        run_as_user gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_DIR/night-stars.jpg"
        run_as_user gsettings set org.gnome.desktop.background picture-options "zoom"
    fi
    
    # Crear archivo XML para slideshow de fondos
    cat > /usr/share/gnome-background-properties/custom-backgrounds.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
<wallpapers>
  <wallpaper deleted="false">
    <name>Nature Mountains</name>
    <filename>/usr/share/backgrounds/custom/nature-mountains.jpg</filename>
    <options>zoom</options>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Ocean Sunset</name>
    <filename>/usr/share/backgrounds/custom/ocean-sunset.jpg</filename>
    <options>zoom</options>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Forest Mist</name>
    <filename>/usr/share/backgrounds/custom/forest-mist.jpg</filename>
    <options>zoom</options>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Night Stars</name>
    <filename>/usr/share/backgrounds/custom/night-stars.jpg</filename>
    <options>zoom</options>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Abstract Gradient</name>
    <filename>/usr/share/backgrounds/custom/abstract-gradient.jpg</filename>
    <options>zoom</options>
  </wallpaper>
  <wallpaper deleted="false">
    <name>City Lights</name>
    <filename>/usr/share/backgrounds/custom/city-lights.jpg</filename>
    <options>zoom</options>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Aurora Borealis</name>
    <filename>/usr/share/backgrounds/custom/aurora-borealis.jpg</filename>
    <options>zoom</options>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Minimal Desert</name>
    <filename>/usr/share/backgrounds/custom/minimal-desert.jpg</filename>
    <options>zoom</options>
  </wallpaper>
</wallpapers>
XMLEOF
    
    print_success "Wallpapers instalados y disponibles en Configuración > Fondo"
    
    # Forzar que al final se mantenga el tema satánico en todo el escritorio
    apply_satanic_themes
    
    # Reiniciar compositor Metacity (sin reiniciar sistema)
    print_message "Reiniciando compositor..."
    
    # Reiniciar Metacity si está corriendo
    if pgrep -x "metacity" > /dev/null; then
        run_as_user metacity --replace &
        print_warning "Metacity reiniciado. Puede tardar unos segundos."
    fi
    
    print_success "Configuración final aplicada."
}

# Configurar terminal con tema de desarrollo/IA
configure_terminal_theme() {
    print_message "Configurando terminal con tema de desarrollo..."
    
    # Instalar terminales y fuentes para desarrollo
    apt install -y fonts-firacode fonts-hack 2>/dev/null || true
    
    # Crear perfil de GNOME Terminal con tema cyberpunk/dev
    PROFILE_ID="ai-developer"
    PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/"
    
    # Crear directorio de configuración
    mkdir -p "$REAL_HOME/.config/gtk-3.0"
    
    # Configurar GNOME Terminal via dconf
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/list "['$PROFILE_ID']"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/visible-name "'AI Developer'"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/use-theme-colors "false"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/background-color "'#0D1117'"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/foreground-color "'#C9D1D9'"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/bold-color "'#58A6FF'"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/bold-color-same-as-fg "false"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/use-transparent-background "true"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/background-transparency-percent "10"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/font "'Fira Code 12'"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/use-system-font "false"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/audible-bell "false"
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/scrollback-unlimited "true"
    
    # Paleta de colores estilo GitHub Dark / Cyberpunk
    run_as_user dconf write /org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/palette "['#484F58', '#FF7B72', '#3FB950', '#D29922', '#58A6FF', '#BC8CFF', '#39C5CF', '#B1BAC4', '#6E7681', '#FFA198', '#56D364', '#E3B341', '#79C0FF', '#D2A8FF', '#56D4DD', '#F0F6FC']"
    
    # Configurar xfce4-terminal también (si está instalado)
    XFCE_TERM_DIR="$REAL_HOME/.config/xfce4/terminal"
    mkdir -p "$XFCE_TERM_DIR"
    
    cat > "$XFCE_TERM_DIR/terminalrc" << 'TERMEOF'
[Configuration]
FontName=Fira Code 12
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBellUrgent=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=TRUE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=120x35
MiscInheritGeometry=FALSE
MiscMenubarDefault=FALSE
MiscMouseAutohide=TRUE
MiscMouseWheelZoom=TRUE
MiscToolbarDefault=FALSE
MiscConfirmClose=TRUE
MiscCycleTabs=TRUE
MiscTabCloseButtons=TRUE
MiscTabCloseMiddleClick=TRUE
MiscTabPosition=GTK_POS_TOP
MiscHighlightUrls=TRUE
MiscMiddleClickOpensUri=FALSE
MiscCopyOnSelect=FALSE
MiscShowRelaunchDialog=TRUE
MiscRewrapOnResize=TRUE
MiscUseShiftArrowsToScroll=FALSE
MiscSlimTabs=TRUE
MiscNewTabAdjacent=FALSE
MiscSearchDialogOpacity=100
MiscShowUnsafePasteDialog=TRUE
MiscRightClickAction=TERMINAL_RIGHT_CLICK_ACTION_CONTEXT_MENU
ScrollingUnlimited=TRUE
BackgroundMode=TERMINAL_BACKGROUND_TRANSPARENT
BackgroundDarkness=0.92
ColorForeground=#c9c9d1d1d9d9
ColorBackground=#0d0d11111717
ColorCursor=#5858a6a6ffff
ColorBold=#5858a6a6ffff
ColorBoldUseDefault=FALSE
ColorPalette=#484f58;#ff7b72;#3fb950;#d29922;#58a6ff;#bc8cff;#39c5cf;#b1bac4;#6e7681;#ffa198;#56d364;#e3b341;#79c0ff;#d2a8ff;#56d4dd;#f0f6fc
TabActivityColor=#58a6ff
TERMEOF
    chown -R "$REAL_USER":"$REAL_USER" "$XFCE_TERM_DIR"
    
    # Configurar .bashrc con prompt personalizado estilo dev/IA
    BASHRC_CUSTOM="$REAL_HOME/.bashrc_ai_theme"
    cat > "$BASHRC_CUSTOM" << 'BASHEOF'
# ═══════════════════════════════════════════════════════════════
# 🤖 AI Developer Terminal Theme
# ═══════════════════════════════════════════════════════════════

# Colores ANSI extendidos
CYAN='\[\033[38;5;51m\]'
PURPLE='\[\033[38;5;141m\]'
GREEN='\[\033[38;5;82m\]'
YELLOW='\[\033[38;5;220m\]'
RED='\[\033[38;5;196m\]'
BLUE='\[\033[38;5;39m\]'
GRAY='\[\033[38;5;244m\]'
WHITE='\[\033[38;5;255m\]'
RESET='\[\033[0m\]'

# Función para obtener rama git
parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

# Función para mostrar estado de Python venv
parse_venv() {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo " 🐍 $(basename $VIRTUAL_ENV)"
    fi
}

# Función para mostrar si hay contenedores Docker corriendo
docker_status() {
    if command -v docker &>/dev/null; then
        local count=$(docker ps -q 2>/dev/null | wc -l)
        if [[ $count -gt 0 ]]; then
            echo " 🐳 $count"
        fi
    fi
}

# Prompt personalizado estilo cyberpunk/dev
PS1="${GRAY}╭─${CYAN}🤖 ${PURPLE}\u${GRAY}@${BLUE}\h ${GRAY}in ${GREEN}\w${YELLOW}\$(parse_git_branch)${PURPLE}\$(parse_venv)${BLUE}\$(docker_status)${RESET}\n${GRAY}╰─${CYAN}λ ${RESET}"

# Aliases útiles para desarrollo
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# Aliases para desarrollo web
alias serve='python3 -m http.server 8080'
alias npmdev='npm run dev'
alias npmbuild='npm run build'

# Aliases para Docker
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dlog='docker logs -f'
alias dexec='docker exec -it'
alias dstop='docker stop $(docker ps -q)'

# Aliases para Git
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph -10'
alias gd='git diff'

# Aliases para IA/ML
alias jupyter='jupyter-lab --ip=0.0.0.0 --no-browser'
alias ollama-models='ollama list'
alias ai-chat='curl http://localhost:3001'

# Mensaje de bienvenida
echo -e "\033[38;5;51m"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║  🤖 AI Developer Environment - $(hostname)           ║"
echo "  ║  📅 $(date '+%Y-%m-%d %H:%M')                              ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "\033[0m"

# Mostrar info del sistema
if command -v fastfetch &>/dev/null; then
    fastfetch --logo none --color cyan 2>/dev/null
fi
BASHEOF

    # Agregar source al .bashrc si no existe
    if ! grep -q "bashrc_ai_theme" "$REAL_HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$REAL_HOME/.bashrc"
        echo "# AI Developer Theme" >> "$REAL_HOME/.bashrc"
        echo "[ -f ~/.bashrc_ai_theme ] && source ~/.bashrc_ai_theme" >> "$REAL_HOME/.bashrc"
    fi
    
    chown "$REAL_USER":"$REAL_USER" "$BASHRC_CUSTOM"
    
    print_success "Terminal configurada con tema AI Developer"
}

# Configurar GRUB con tema de desarrollo/IA
configure_grub_theme() {
    print_message "Configurando tema de GRUB..."
    
    GRUB_THEMES_DIR="/boot/grub/themes"
    THEME_NAME="ai-developer"
    THEME_DIR="$GRUB_THEMES_DIR/$THEME_NAME"
    
    mkdir -p "$THEME_DIR"
    
    # Descargar fuente para GRUB
    apt install -y grub2-common fonts-dejavu 2>/dev/null || true
    
    # Crear tema de GRUB personalizado
    cat > "$THEME_DIR/theme.txt" << 'GRUBTHEME'
# AI Developer GRUB Theme
# Tema cyberpunk/desarrollo

# Configuración global
title-text: ""
desktop-color: "#0D1117"
desktop-image: "background.png"
terminal-font: "DejaVu Sans Mono Regular 14"
terminal-left: "10%"
terminal-top: "20%"
terminal-width: "80%"
terminal-height: "60%"

# Menú de arranque
+ boot_menu {
    left = 25%
    top = 30%
    width = 50%
    height = 50%
    item_font = "DejaVu Sans Mono Regular 16"
    item_color = "#C9D1D9"
    selected_item_color = "#58A6FF"
    item_height = 32
    item_padding = 10
    item_spacing = 8
    item_icon_space = 20
    selected_item_pixmap_style = "select_*.png"
    icon_width = 32
    icon_height = 32
}

# Barra de progreso
+ progress_bar {
    id = "__timeout__"
    left = 25%
    top = 85%
    width = 50%
    height = 16
    fg_color = "#58A6FF"
    bg_color = "#21262D"
    border_color = "#30363D"
    text_color = "#C9D1D9"
    font = "DejaVu Sans Mono Regular 12"
    text = "Iniciando en %d segundos..."
}

# Etiqueta inferior
+ label {
    left = 0
    top = 95%
    width = 100%
    height = 20
    text = "🤖 AI Developer System - Press 'e' to edit, 'c' for command line"
    color = "#6E7681"
    align = "center"
    font = "DejaVu Sans Mono Regular 12"
}
GRUBTHEME

    # Crear imagen de fondo con ImageMagick o descargar una
    if command -v convert &>/dev/null; then
        print_message "Generando fondo de GRUB..."
        convert -size 1920x1080 \
            -define gradient:angle=135 \
            gradient:'#0D1117-#161B22' \
            -font DejaVu-Sans-Mono \
            -pointsize 80 \
            -fill '#58A6FF' \
            -gravity center \
            -annotate +0-200 '🤖' \
            -pointsize 40 \
            -fill '#8B949E' \
            -annotate +0-50 'AI DEVELOPER SYSTEM' \
            -pointsize 20 \
            -fill '#6E7681' \
            -annotate +0+50 'Debian GNU/Linux' \
            "$THEME_DIR/background.png" 2>/dev/null || \
        # Fallback: crear imagen simple
        convert -size 1920x1080 xc:'#0D1117' "$THEME_DIR/background.png" 2>/dev/null
    else
        # Descargar fondo alternativo
        print_message "Descargando fondo de GRUB..."
        wget -q -O "$THEME_DIR/background.png" \
            "https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=1920&q=80" 2>/dev/null || \
        # Crear fondo sólido como fallback
        apt install -y imagemagick 2>/dev/null && \
        convert -size 1920x1080 xc:'#0D1117' "$THEME_DIR/background.png" 2>/dev/null
    fi
    
    # Crear imágenes de selección
    if command -v convert &>/dev/null; then
        convert -size 600x32 xc:'#58A6FF20' \
            -fill '#58A6FF' -draw "rectangle 0,0 4,32" \
            "$THEME_DIR/select_c.png" 2>/dev/null
        cp "$THEME_DIR/select_c.png" "$THEME_DIR/select_e.png" 2>/dev/null
        cp "$THEME_DIR/select_c.png" "$THEME_DIR/select_w.png" 2>/dev/null
    fi
    
    # Actualizar configuración de GRUB
    if [ -f /etc/default/grub ]; then
        # Backup
        cp /etc/default/grub /etc/default/grub.backup
        
        # Modificar configuración
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
        sed -i 's/^#\?GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
        
        # Agregar tema si no existe
        if ! grep -q "GRUB_THEME=" /etc/default/grub; then
            echo "GRUB_THEME=\"$THEME_DIR/theme.txt\"" >> /etc/default/grub
        else
            sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$THEME_DIR/theme.txt\"|" /etc/default/grub
        fi
        
        # Configurar resolución
        if ! grep -q "GRUB_GFXMODE=" /etc/default/grub; then
            echo 'GRUB_GFXMODE=1920x1080,1280x1024,auto' >> /etc/default/grub
        fi
        
        # Desactivar submenu
        if ! grep -q "GRUB_DISABLE_SUBMENU=" /etc/default/grub; then
            echo 'GRUB_DISABLE_SUBMENU=y' >> /etc/default/grub
        fi
        
        # Actualizar GRUB
        update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg
        
        print_success "Tema de GRUB instalado"
    else
        print_warning "No se encontró /etc/default/grub"
    fi
}

# Configurar Plymouth (splash de arranque)
configure_plymouth_theme() {
    print_message "Configurando Plymouth (splash de arranque)..."
    
    # Instalar Plymouth si no está
    apt install -y plymouth plymouth-themes 2>/dev/null || true
    
    PLYMOUTH_DIR="/usr/share/plymouth/themes"
    THEME_NAME="ai-developer"
    THEME_DIR="$PLYMOUTH_DIR/$THEME_NAME"
    
    mkdir -p "$THEME_DIR"
    
    # Crear tema de Plymouth
    cat > "$THEME_DIR/$THEME_NAME.plymouth" << PLYTHEME
[Plymouth Theme]
Name=AI Developer
Description=Cyberpunk theme for AI developers
ModuleName=script

[script]
ImageDir=$THEME_DIR
ScriptFile=$THEME_DIR/$THEME_NAME.script
PLYTHEME

    # Script de Plymouth para animación
    cat > "$THEME_DIR/$THEME_NAME.script" << 'PLYSCRIPT'
// AI Developer Plymouth Theme Script

// Configuración de pantalla
Window.SetBackgroundTopColor(0.05, 0.07, 0.09);     // #0D1117
Window.SetBackgroundBottomColor(0.08, 0.11, 0.13); // #161B22

// Cargar logo
logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth() / 2 - logo.image.GetWidth() / 2);
logo.sprite.SetY(Window.GetHeight() / 2 - logo.image.GetHeight() / 2 - 50);
logo.sprite.SetOpacity(1);

// Texto de carga
text_sprite = Sprite();
text_sprite.SetPosition(Window.GetWidth() / 2 - 100, Window.GetHeight() / 2 + 80, 1);

// Barra de progreso
progress_box.image = Image("progress_box.png");
progress_box.sprite = Sprite(progress_box.image);
progress_box.sprite.SetPosition(Window.GetWidth() / 2 - progress_box.image.GetWidth() / 2, Window.GetHeight() / 2 + 50, 0);

progress_bar.original_image = Image("progress_bar.png");
progress_bar.sprite = Sprite();
progress_bar.sprite.SetPosition(Window.GetWidth() / 2 - progress_box.image.GetWidth() / 2 + 2, Window.GetHeight() / 2 + 52, 1);

// Función de progreso
fun refresh_callback() {
    if (Plymouth.GetMode() == "boot") {
        // Animar logo
        logo.sprite.SetOpacity(0.8 + Math.Sin(time++ * 0.1) * 0.2);
    }
}

// Callback de progreso de arranque
fun boot_progress_callback(time, progress) {
    if (progress_bar.original_image) {
        progress_bar.image = progress_bar.original_image.Scale(progress * (progress_box.image.GetWidth() - 4), progress_bar.original_image.GetHeight());
        progress_bar.sprite.SetImage(progress_bar.image);
    }
}

// Callback de mensajes
fun message_callback(text) {
    my_image = Image.Text(text, 0.35, 0.65, 1.0);
    text_sprite.SetImage(my_image);
    text_sprite.SetPosition(Window.GetWidth() / 2 - my_image.GetWidth() / 2, Window.GetHeight() / 2 + 120, 1);
}

Plymouth.SetRefreshFunction(refresh_callback);
Plymouth.SetBootProgressFunction(boot_progress_callback);
Plymouth.SetMessageFunction(message_callback);
PLYSCRIPT

    # Crear imágenes para Plymouth
    if command -v convert &>/dev/null; then
        # Logo
        convert -size 200x200 xc:transparent \
            -font DejaVu-Sans-Mono-Bold \
            -pointsize 120 \
            -fill '#58A6FF' \
            -gravity center \
            -annotate 0 '🤖' \
            "$THEME_DIR/logo.png" 2>/dev/null || \
        convert -size 200x60 xc:transparent \
            -font DejaVu-Sans-Mono-Bold \
            -pointsize 40 \
            -fill '#58A6FF' \
            -gravity center \
            -annotate 0 'AI DEV' \
            "$THEME_DIR/logo.png" 2>/dev/null
        
        # Caja de progreso
        convert -size 400x20 xc:'#21262D' \
            -stroke '#30363D' -strokewidth 2 \
            -draw "rectangle 0,0 399,19" \
            "$THEME_DIR/progress_box.png" 2>/dev/null
        
        # Barra de progreso
        convert -size 396x16 xc:'#58A6FF' \
            "$THEME_DIR/progress_bar.png" 2>/dev/null
    else
        print_warning "ImageMagick no instalado - Plymouth usará imágenes por defecto"
    fi
    
    # Establecer tema por defecto
    if command -v plymouth-set-default-theme &>/dev/null; then
        plymouth-set-default-theme $THEME_NAME 2>/dev/null || \
        plymouth-set-default-theme -R $THEME_NAME 2>/dev/null || true
    fi
    
    # Actualizar initramfs para aplicar cambios
    if command -v update-initramfs &>/dev/null; then
        print_message "Actualizando initramfs..."
        update-initramfs -u 2>/dev/null || true
    fi
    
    print_success "Plymouth configurado con tema AI Developer"
}

# Función principal
main() {
    print_message "Iniciando script de actualización y personalización Ubuntu 24.04..."
    
    # Verificaciones iniciales
    check_ubuntu
    check_root
    
    # Paso 1: Actualizar sistema
    update_system
    
    # Paso 2: Detectar e instalar drivers de hardware
    install_hardware_drivers
    
    # Paso 2B: Aplicar temas satánicos
    apply_satanic_themes
    
    # Paso 3: Instalar GNOME Tweaks
    install_gnome_tweaks
    
    # Paso 4: Configurar temas y animaciones (incluye iconos modernos)
    configure_themes_and_animations
    
    # Paso 5: Optimizar rendimiento
    optimize_performance
    
    # Paso 6: Configurar panel de GNOME Flashback
    configure_gnome_panel
    
    # Paso 7: Instalar aplicaciones adicionales
    install_additional_apps
    
    # Paso 8: Configurar shortcuts
    configure_shortcuts
    
    # Paso 9: Configurar terminal con tema dev/IA
    configure_terminal_theme
    
    # Paso 10: Configurar GRUB con tema cyberpunk
    configure_grub_theme
    
    # Paso 11: Configurar Plymouth (splash de arranque)
    configure_plymouth_theme
    
    # Paso 12: Configuración final
    final_configuration
    
    print_success "¡Proceso completado!"
    echo ""
    print_message "════════════════════════════════════════════════════════"
    print_message "  🤖 UBUNTU 24.04 AI DEVELOPER - Configuración completada"
    print_message "════════════════════════════════════════════════════════"
    print_message ""
    print_message "Personalizaciones aplicadas:"
    print_message "  • Sistema: Ubuntu 24.04 LTS actualizado"
    print_message "  • Drivers: GPU (NVIDIA/AMD/Intel), WiFi, Audio (sin conflictos)"
    print_message "  • Temas: Satánicos (rojo/negro) en GNOME, Terminal, Fondos"
    print_message "  • Iconos: Tela/Reversal/Kora (modernos con gradientes)"
    print_message "  • Terminal: Tema cyberpunk con prompt personalizado"
    print_message "  • GRUB: Tema oscuro con estilo desarrollo"
    print_message "  • Plymouth: Splash de arranque AI Developer"
    print_message ""
    print_message "Recomendaciones:"
    print_message "  1. REINICIA tu sistema para ver todos los cambios"
    print_message "  2. Si tienes GPU NVIDIA, reinicia para cargar drivers"
    print_message "  3. Usa 'gnome-tweaks' y 'dconf-editor' para ajustes"
    print_message "  4. Ejecuta 'source ~/.bashrc' para aplicar terminal ahora"
    print_message "  5. Usa 'ccsm' (CompizConfig) para efectos de ventanas"
    print_message "  6. Ejecuta 'nvidia-smi' si tienes NVIDIA (verificar drivers)"
    print_message "  7. Ejecuta 'sensors' para ver temperaturas del sistema"
}

# Ejecutar función principal
main
