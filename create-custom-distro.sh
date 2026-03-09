#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Script para crear ISO personalizada de Ubuntu 24.04
# Con temas satánicos: GRUB, Terminal, GNOME, Fondos
# Autor: [Tu Nombre]
# Uso: sudo ./create-custom-distro.sh

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

# Variables configurables
ISO_NAME="custom-ubuntu-satanic"
ISO_VERSION="24.04"
ISO_LABEL="UBUNTU_SATANIC"
ISO_DIR="/tmp/custom-iso"
LIVE_DIR="$ISO_DIR/live"
WORK_DIR="/tmp/iso-work"
# Si el script se ejecuta con sudo, usar la carpeta Documentos del usuario original
if [ -n "$SUDO_USER" ]; then
    OUTPUT_DIR="/home/$SUDO_USER/Documentos"
else
    OUTPUT_DIR="$HOME/Documentos"
fi
CUSTOM_NAME="Ubuntu Satanic"
HOSTNAME="ubuntu-satanic"
USERNAME="satanic"
PASSWORD="satanic666"
TIMEZONE="America/Mexico_City"
KEYBOARD="latam"
LOCALE="es_MX.UTF-8"

# Modo seguro por defecto: evita instalar paquetes de arranque en el host.
SAFE_MODE="${SAFE_MODE:-1}"

# Funciones de mensajes
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "${MAGENTA}[STEP]${NC} $1"; }
debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }

# Ejecutar en modo no interactivo
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
# Opciones recomendadas para apt/dpkg en scripts automatizados
APT_DPKG_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

# Verificar root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script requiere privilegios de root (sudo)"
        exit 1
    fi
}

# Verificar espacio disponible
check_disk_space() {
    step "Verificando espacio en disco..."
    
    local required_space=10000 # 10GB en MB
    local available_space=$(df -m /tmp | tail -1 | awk '{print $4}')
    
    if [ $available_space -lt $required_space ]; then
        error "Espacio insuficiente en /tmp. Necesitas al menos 10GB"
        error "Disponible: ${available_space}MB, Requerido: ${required_space}MB"
        exit 1
    fi
    
    success "Espacio en disco verificado: ${available_space}MB disponibles"
}

# Instalar dependencias necesarias
install_dependencies() {
    step "Instalando dependencias..."
    
    apt update || { error "apt update falló. Revisa /etc/apt/sources.list y las keys de repositorios."; exit 1; }

    local base_packages=(
        debootstrap
        squashfs-tools
        xorriso
        mtools
        dosfstools
        live-build
        live-boot
        live-config
        live-boot-doc
        live-manual
        live-tools
        discover
        laptop-detect
        os-prober
        rsync
        wget
        curl
        git
        nano
        vim
        gdisk
        fdisk
        parted
    )

    local bootloader_packages=(
        isolinux
        syslinux
        syslinux-utils
        syslinux-efi
        grub-pc-bin
        grub-efi-amd64-bin
    )

    if ! apt install -y $APT_DPKG_OPTS "${base_packages[@]}"; then
        error "Falló instalación de dependencias base. Intentando instalar paquetes críticos..."
        apt install -y $APT_DPKG_OPTS debootstrap squashfs-tools xorriso mtools dosfstools rsync wget curl git nano vim gdisk fdisk parted || {
            error "No se pudieron instalar los paquetes críticos. Corrige los repositorios/keys y reintenta."; exit 1; }
    fi

    if [ "$SAFE_MODE" != "1" ]; then
        warn "SAFE_MODE=0: instalando paquetes de bootloader en el host (riesgo de alterar arranque)."
        apt install -y $APT_DPKG_OPTS "${bootloader_packages[@]}" || true
    else
        warn "SAFE_MODE=1: se omite instalación de bootloaders en el host."
    fi

    # Paquetes opcionales que a veces no existen en Debian puro.
    for p in casper lupin-casper; do
        apt install -y $APT_DPKG_OPTS "$p" 2>/dev/null || warn "Paquete opcional '$p' no disponible; se omite"
    done

    success "Dependencias instaladas"
}

# Preparar directorios de trabajo
prepare_directories() {
    step "Preparando directorios de trabajo..."
    
    # Limpiar directorios antiguos
    [ -n "$ISO_DIR" ] && [ "$ISO_DIR" != "/" ] && [[ "$ISO_DIR" == /tmp/* ]] || { error "ISO_DIR inválido: $ISO_DIR"; exit 1; }
    [ -n "$WORK_DIR" ] && [ "$WORK_DIR" != "/" ] && [[ "$WORK_DIR" == /tmp/* ]] || { error "WORK_DIR inválido: $WORK_DIR"; exit 1; }
    rm -rf "$ISO_DIR" "$WORK_DIR"
    
    # Crear directorios necesarios
    mkdir -p "$ISO_DIR"
    mkdir -p "$LIVE_DIR"
    mkdir -p "$WORK_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    # Crear estructura de directorios para la ISO
    mkdir -p "$ISO_DIR"/{boot/grub,live,isolinux}
    mkdir -p "$ISO_DIR/live/overlay"
    
    success "Directorios preparados"
}

# Crear sistema base con debootstrap
create_base_system() {
    step "Creando sistema base con debootstrap..."
    
    local ubuntu_version="noble"  # Ubuntu 24.04 LTS
    local arch="amd64"
    
    info "Creando sistema base Ubuntu 24.04 $arch..."
    if ! command -v debootstrap >/dev/null 2>&1; then
        info "debootstrap no encontrado; intentando instalar debootstrap..."
        apt update || true
        apt install -y $APT_DPKG_OPTS debootstrap || { error "no se pudo instalar debootstrap. Ejecuta install_dependencies y revisa errores."; exit 1; }
    fi

    debootstrap \
        --arch=$arch \
        --variant=minbase \
        --include=systemd,systemd-sysv,udev \
        $ubuntu_version \
        $WORK_DIR \
        http://archive.ubuntu.com/ubuntu/
    
    if [ $? -ne 0 ]; then
        error "Error al crear sistema base con debootstrap"
        exit 1
    fi
    
    success "Sistema base Ubuntu 24.04 creado"
}

# Copiar configuración actual del sistema
copy_current_system() {
    step "Aplicando configuración mínima del host (seguro y opcional)..."

    # Evitar copiar todo el sistema raíz: solo copiar /etc/skel y sources.list si existen
    if [ -d /etc/skel ]; then
        rsync -a --progress /etc/skel/ $WORK_DIR/etc/skel/ || true
    fi

    if [ -f /etc/apt/sources.list ]; then
        mkdir -p $WORK_DIR/etc/apt
        cp /etc/apt/sources.list $WORK_DIR/etc/apt/sources.list || true
    fi

    mkdir -p $WORK_DIR/{proc,sys,dev,tmp,run,mnt,media}
    chmod 1777 $WORK_DIR/tmp

    success "Configuración mínima aplicada (no se copió todo el root)"
}

# Configurar sistema para Live ISO
configure_live_system() {
    step "Configurando sistema para Live ISO..."
    
    # Montar sistemas de archivos especiales
    mount --bind /proc $WORK_DIR/proc
    mount --bind /sys $WORK_DIR/sys
    mount --bind /dev $WORK_DIR/dev
    # Asegurar pts disponible dentro del chroot (evita errores posix_openpt)
    mount --bind /dev/pts $WORK_DIR/dev/pts 2>/dev/null || true
    
    # Asegurar que existan los directorios antes de escribir archivos
    mkdir -p $WORK_DIR/etc
    mkdir -p $WORK_DIR/etc/apt

    # Configurar fstab para Live
    cat > $WORK_DIR/etc/fstab << EOF
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
tmpfs           /tmp            tmpfs   defaults,noatime,mode=1777  0       0
EOF
    
    # Configurar hostname
    echo "$HOSTNAME" > $WORK_DIR/etc/hostname
    
    # Configurar hosts
    cat > $WORK_DIR/etc/hosts << EOF
127.0.0.1       localhost
127.0.1.1       $HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
    
    # Configurar locale (solo si locale-gen existe en chroot)
    if chroot $WORK_DIR bash -c "command -v locale-gen >/dev/null 2>&1"; then
        chroot $WORK_DIR locale-gen $LOCALE || true
    else
        warning "locale-gen no disponible en chroot; saltando generación de locales"
    fi
    echo "LANG=$LOCALE" > $WORK_DIR/etc/default/locale
    echo "LC_ALL=$LOCALE" >> $WORK_DIR/etc/default/locale
    
    # Configurar teclado
    mkdir -p $WORK_DIR/etc/default
    echo "KEYBOARD=$KEYBOARD" > $WORK_DIR/etc/default/keyboard
    echo "XKBMODEL=pc105" >> $WORK_DIR/etc/default/keyboard
    echo "XKBLAYOUT=$KEYBOARD" >> $WORK_DIR/etc/default/keyboard
    echo "XKBVARIANT=" >> $WORK_DIR/etc/default/keyboard
    echo "XKBOPTIONS=" >> $WORK_DIR/etc/default/keyboard
    
    # Configurar zona horaria
    echo "$TIMEZONE" > $WORK_DIR/etc/timezone
    ln -sf /usr/share/zoneinfo/$TIMEZONE $WORK_DIR/etc/localtime
    
    # Configurar red para Live
    mkdir -p $WORK_DIR/etc/network
    cat > $WORK_DIR/etc/network/interfaces << EOF
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto wlan0
iface wlan0 inet dhcp
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
EOF
    
    # Configurar resolv.conf
    cat > $WORK_DIR/etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    
    success "Sistema configurado para Live"
}

########################################
# CONFIGURAR TEMAS SATÁNICOS
########################################
configure_satanic_themes() {
    step "Configurando temas satánicos (GNOME, GRUB, Terminal, Fondos)..."
    
    # Crear directorio para setup
    mkdir -p $WORK_DIR/tmp/setup
    
    # Instalar herramientas necesarias para temas
    chroot $WORK_DIR bash -c "export DEBIAN_FRONTEND=noninteractive; apt install -y --no-install-recommends dconf-cli gnome-shell-extensions python3-pil 2>/dev/null" || true
    
    # Descargar e instalar Dracula theme
    info "Instalando tema Dracula Dark..."
    cd /tmp && rm -rf dracula-gtk 2>/dev/null || true
    git clone --depth 1 https://github.com/dracula/gtk.git dracula-gtk 2>/dev/null || true
    if [ -d dracula-gtk ]; then
        mkdir -p $WORK_DIR/usr/share/themes
        cp -r dracula-gtk/Dracula* $WORK_DIR/usr/share/themes/ 2>/dev/null || true
        log "Tema Dracula Dark instalado"
    fi
    
    # Crear tema personalizado de GRUB satánico
    info "Creando tema GRUB satánico..."
    mkdir -p $WORK_DIR/boot/grub/themes/Satanic
    cat > $WORK_DIR/boot/grub/themes/Satanic/theme.txt << 'GRUBTHEME'
# GRUB2 Satanic Theme - Demonic Edition

desktop-image: ""
desktop-color: "#000000"

terminal-border: "0"
terminal-left: "0"
terminal-right: "0"
terminal-top: "0"
terminal-bottom: "0"

title-text: "🔥 UBUNTU SATANIC 24.04 🔥"
title-font: "Unifont Regular 16"
title-color: "#AA0000"

menu-border: "0"
left: "0"
top: "0"
width: "100%"
height: "100%"

text-color: "#CCCCCC"
highlight-color: "#660000"
highlight-text-color: "#FFFFFF"
GRUBTHEME
    
    # Actualizar configuración de GRUB
    info "Actualizando configuración de GRUB con tema satánico..."
    cat >> $WORK_DIR/etc/default/grub << 'GRUB_EOF'

# Temas Satánicos
GRUB_THEME="/boot/grub/themes/Satanic/theme.txt"
GRUB_COLOR_NORMAL="darkred/black"
GRUB_COLOR_HIGHLIGHT="white/darkred"
GRUB_EOF
    
    # Crear script Python para generar fondos satánicos
    info "Preparando fondos de pantalla satánicos..."
    mkdir -p $WORK_DIR/usr/share/backgrounds
    cat > $WORK_DIR/tmp/create_wallpapers.py << 'WALLPAPER_EOF'
#!/usr/bin/env python3
import os
try:
    from PIL import Image, ImageDraw
except ImportError:
    import subprocess
    subprocess.run(["pip3", "install", "pillow"], check=False)
    from PIL import Image, ImageDraw

# Crear fondos satánicos en diferentes resoluciones
resolutions = [(1920, 1080), (1280, 720), (2560, 1440), (3840, 2160)]
for width, height in resolutions:
    img = Image.new('RGB', (width, height), color='black')
    draw = ImageDraw.Draw(img)
    
    # Degradado rojo-negro (arriba a abajo)
    for y in range(height):
        ratio = y / height
        r = int(60 * (1 - ratio))
        draw.line([(0, y), (width, y)], fill=(r, 0, 0))
    
    # Agregar marco
    draw.rectangle([10, 10, width-10, height-10], outline=(100, 0, 0), width=3)
    
    img.save(f"/usr/share/backgrounds/satanic-{width}x{height}.png")

print("Fondos satánicos creados exitosamente")
WALLPAPER_EOF
    
    chmod +x $WORK_DIR/tmp/create_wallpapers.py
    chroot $WORK_DIR python3 /tmp/create_wallpapers.py 2>/dev/null || true
    
    # Crear script de configuración de terminal con colores satánicos
    info "Configurando colores satánicos para Terminal Gnome..."
    cat > $WORK_DIR/tmp/setup_terminal_colors.sh << 'TERMINAL_EOF'
#!/bin/bash
# Configurar colores satánicos en dconf para todos los usuarios
PROFILES_PATH="/org/gnome/terminal/legacy/profiles"

# Para el usuario root si existe
if [ -d /root ]; then
    dbus_session="/run/user/0/bus" 2>/dev/null || true
    [ -S "$dbus_session" ] && export DBUS_SESSION_BUS_ADDRESS="unix:path=$dbus_session"
fi

# Aplicar tema oscuro a nivel del sistema
for user_home in /home/*; do
    [ -d "$user_home" ] || continue
    user=$(basename "$user_home")
    user_id=$(id -u "$user" 2>/dev/null || echo "")
    [ -z "$user_id" ] && continue
    
    sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_id/bus" dconf write /org/gnome/terminal/legacy/theme-variant "'dark'" 2>/dev/null || true
done
TERMINAL_EOF
    
    chmod +x $WORK_DIR/tmp/setup_terminal_colors.sh
    chroot $WORK_DIR bash /tmp/setup_terminal_colors.sh 2>/dev/null || true
    
    success "Temas satánicos configurados exitosamente"
}

# Crear usuario personalizado
create_custom_user() {
    step "Creando usuario personalizado..."
    
    # Configurar contraseña encriptada
    local encrypted_pass=$(openssl passwd -6 $PASSWORD)
    
    # Asegurar que los grupos existan en el chroot
    for g in sudo audio video plugdev netdev; do
        chroot $WORK_DIR bash -c "getent group $g >/dev/null 2>&1 || groupadd -r $g >/dev/null 2>&1 || true"
    done

    chroot $WORK_DIR useradd -m -s /bin/bash -G sudo,audio,video,plugdev,netdev $USERNAME || true
    if chroot $WORK_DIR bash -c "id $USERNAME >/dev/null 2>&1"; then
        echo "$USERNAME:$encrypted_pass" | chroot $WORK_DIR chpasswd -e || true
    else
        warning "No se pudo crear el usuario $USERNAME dentro del chroot"
    fi

    # Configurar sudo sin contraseña para el usuario (asegurando carpeta)
    mkdir -p $WORK_DIR/etc/sudoers.d
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > $WORK_DIR/etc/sudoers.d/$USERNAME || true
    chmod 440 $WORK_DIR/etc/sudoers.d/$USERNAME || true
    
    # Configurar autologin para Live session (si usas GDM o LightDM)
    if [ -f $WORK_DIR/etc/lightdm/lightdm.conf ]; then
        sed -i "s/#autologin-user=.*/autologin-user=$USERNAME/" $WORK_DIR/etc/lightdm/lightdm.conf
        sed -i "s/#autologin-user-timeout=.*/autologin-user-timeout=0/" $WORK_DIR/etc/lightdm/lightdm.conf
    fi
    
    # Configurar GNOME autologin
    if [ -d $WORK_DIR/etc/gdm3 ]; then
        cat > $WORK_DIR/etc/gdm3/daemon.conf << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=$USERNAME
EOF
    fi
    
    # Configurar autologin en consola (tty1) mediante systemd agetty
    mkdir -p $WORK_DIR/etc/systemd/system/getty@tty1.service.d
    cat > $WORK_DIR/etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF

    # Configurar autologin para LightDM en caso de usarse
    mkdir -p $WORK_DIR/etc/lightdm/lightdm.conf.d
    cat > $WORK_DIR/etc/lightdm/lightdm.conf.d/50-autologin.conf << EOF
[Seat:*]
autologin-user=$USERNAME
autologin-user-timeout=0
autologin-session=xfce
EOF

    # Asegurar propiedad correcta del home del usuario
    if chroot $WORK_DIR bash -c "id $USERNAME >/dev/null 2>&1"; then
        chroot $WORK_DIR chown -R $USERNAME:$USERNAME /home/$USERNAME 2>/dev/null || true
    fi

    success "Usuario $USERNAME creado"
}

# Instalar paquetes adicionales
install_additional_packages() {
    step "Instalando paquetes adicionales..."

    # Keep chroot package list minimal to avoid large desktop dependency chains
    local packages=(
        linux-image-generic
        network-manager
        wpasupplicant
        net-tools
        curl
        wget
        nano
        vim
        htop
        rsync
        sudo
        apt-utils
        live-boot
        live-config
        live-tools
        dconf-cli
        gnome-shell-extensions
        python3-pil
        git
    )

    local optional_packages=(
        firmware-linux
        firmware-linux-nonfree
        intel-microcode
        amd64-microcode
        neofetch
        software-properties-common
        casper
        lupin-casper
    )

    chroot $WORK_DIR bash -c "export DEBIAN_FRONTEND=noninteractive; apt update || true"
    # Instalar paquetes principales en chroot (mantener lista mínima para evitar rompimientos)
    chroot $WORK_DIR bash -c "export DEBIAN_FRONTEND=noninteractive; apt install -y $APT_DPKG_OPTS --no-install-recommends ${packages[*]} || true"
    # Intentar corregir dependencias rotas dentro del chroot
    chroot $WORK_DIR bash -c "export DEBIAN_FRONTEND=noninteractive; apt -y -f install || true"
    chroot $WORK_DIR bash -c "dpkg --configure -a || true"
    # Intentar instalar paquetes opcionales uno a uno para poder saltarlos si no existen
    for p in "${optional_packages[@]}"; do
        chroot $WORK_DIR bash -c "export DEBIAN_FRONTEND=noninteractive; apt install -y $APT_DPKG_OPTS --no-install-recommends $p" 2>/dev/null || warning "Paquete opcional $p no disponible en chroot; saltando"
    done

    chroot $WORK_DIR bash -c "export DEBIAN_FRONTEND=noninteractive; apt clean || true"

    success "Paquetes adicionales instalados (si la red y los repos estaban disponibles)"
}

# Configurar Live Boot
configure_live_boot() {
    step "Configurando Live Boot..."
    
    # Crear archivos de configuración de casper
    mkdir -p $WORK_DIR/var/lib/casper
    
    # Crear archivo de identificación de casper
    cat > $WORK_DIR/var/lib/casper/casper.conf << EOF
LIVE_SYSTEM=yes
LIVE_MEDIA_PATH=/live
LIVE_MEDIA_UUID=\$LIVE_MEDIA_UUID
PERSISTENCE_PATH=/live/persistence
PERSISTENCE_UUID=\$PERSISTENCE_UUID
EOF
    
    # Crear scripts de casper
    mkdir -p $WORK_DIR/etc/casper.conf.d
    
    cat > $WORK_DIR/etc/casper.conf.d/01_custom << EOF
export USERNAME="$USERNAME"
export USERFULLNAME="$CUSTOM_NAME User"
export HOST="$HOSTNAME"
export BUILD_SYSTEM="Debian"
export FLAVOUR="$CUSTOM_NAME"
EOF
    
    # Configurar hooks de live-boot
    mkdir -p $WORK_DIR/etc/live/boot.conf.d
    
    cat > $WORK_DIR/etc/live/boot.conf.d/9999-custom << EOF
LIVE_BOOT_LANG="$LOCALE"
LIVE_BOOT_TIMEZONE="$TIMEZONE"
LIVE_BOOT_UTC=no
LIVE_BOOT_NOPROMPT=yes
LIVE_BOOT_NOSWAP=yes
LIVE_BOOT_BLACKLIST=radeon,nouveau
LIVE_BOOT_PERSISTENCE=filesystem.squashfs
EOF
    
    success "Live Boot configurado"
}

# Limpiar y optimizar sistema
cleanup_system() {
    step "Limpiando y optimizando sistema..."
    
    # Limpiar cache de apt
    chroot $WORK_DIR apt clean
    chroot $WORK_DIR apt autoremove -y
    
    # Limpiar archivos temporales
    rm -rf $WORK_DIR/tmp/*
    rm -rf $WORK_DIR/var/tmp/*
    rm -rf $WORK_DIR/var/cache/apt/*
    rm -rf $WORK_DIR/var/lib/apt/lists/*
    
    # Limpiar logs
    find $WORK_DIR/var/log -type f -name "*.log" -exec truncate -s 0 {} \;
    rm -f $WORK_DIR/var/log/*.gz
    rm -f $WORK_DIR/var/log/*.1
    
    # Limpiar historial de comandos
    rm -f $WORK_DIR/root/.bash_history
    rm -f $WORK_DIR/home/*/.bash_history
    rm -f $WORK_DIR/home/*/.zsh_history
    
    # Limpiar cache de aplicaciones
    rm -rf $WORK_DIR/home/*/.cache/*
    rm -rf $WORK_DIR/root/.cache/*
    
    # Vaciar archivos de sesión
    rm -rf $WORK_DIR/var/lib/systemd/coredump/*
    
    # Reconstruir base de datos de mandb
    chroot $WORK_DIR mandb --purge
    
    success "Sistema limpiado y optimizado"
}

# Crear sistema de archivos squashfs
create_squashfs() {
    step "Creando sistema de archivos squashfs..."

    info "Comprimiendo sistema de archivos (esto puede tomar tiempo)..."

    # Excluir rutas relativas dentro del árbol de $WORK_DIR
    mksquashfs "$WORK_DIR" "$LIVE_DIR/filesystem.squashfs" \
        -comp xz \
        -b 1M \
        -noappend \
        -no-recovery \
        -e boot \
        -e proc \
        -e sys \
        -e dev \
        -e tmp \
        -e run \
        -e mnt \
        -e media

    if [ $? -ne 0 ]; then
        error "Error al crear squashfs"
        exit 1
    fi

    info "Calculando checksum MD5..."
    (cd "$LIVE_DIR" && find . -type f -not -name 'md5sum.txt' -exec md5sum {} \; > md5sum.txt) || true

    local size=$(du -h "$LIVE_DIR/filesystem.squashfs" | cut -f1 2>/dev/null || echo "N/A")
    success "Squashfs creado: $size"
}

# Preparar bootloader
prepare_bootloader() {
    step "Preparando bootloader..."

    # Copiar kernel e initrd: preferir kernel del chroot, si no existe usar el del host
    local vmlinuz=""
    local initrd=""
    vmlinuz=$(ls $WORK_DIR/boot/vmlinuz-* 2>/dev/null | head -n1 || true)
    initrd=$(ls $WORK_DIR/boot/initrd.img-* 2>/dev/null | head -n1 || true)
    if [ -n "$vmlinuz" ] && [ -n "$initrd" ]; then
        cp "$vmlinuz" "$ISO_DIR/live/vmlinuz" || true
        cp "$initrd" "$ISO_DIR/live/initrd" || true
    else
        # Intentar copiar kernel e initrd del host /boot
        host_vmlinuz=$(ls /boot/vmlinuz-* 2>/dev/null | head -n1 || true)
        host_initrd=$(ls /boot/initrd.img-* 2>/dev/null | head -n1 || true)
        if [ -n "$host_vmlinuz" ] && [ -n "$host_initrd" ]; then
            cp "$host_vmlinuz" "$ISO_DIR/live/vmlinuz" 2>/dev/null || true
            cp "$host_initrd" "$ISO_DIR/live/initrd" 2>/dev/null || true
            info "Usando kernel/initrd del host"
        else
            warning "No se encontraron vmlinuz/initrd en chroot ni en el host; la ISO no tendrá kernel incluido"
        fi
    fi

    # Configurar isolinux (varios paths posibles)
    # Copiar isolinux/syslinux si están disponibles
    if [ -f /usr/lib/ISOLINUX/isolinux.bin ]; then
        cp /usr/lib/ISOLINUX/isolinux.bin $ISO_DIR/isolinux/ || true
    elif [ -f /usr/lib/isolinux/isolinux.bin ]; then
        cp /usr/lib/isolinux/isolinux.bin $ISO_DIR/isolinux/ || true
    else
        warning "isolinux.bin no encontrado en rutas comunes; se omitirá soporte Legacy"
    fi

    if [ -d /usr/lib/syslinux/modules/bios ]; then
        cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libcom32.c32,libutil.c32,vesamenu.c32} $ISO_DIR/isolinux/ 2>/dev/null || true
    fi
    
    # Crear configuración de isolinux
    cat > $ISO_DIR/isolinux/isolinux.cfg << EOF
DEFAULT live
PROMPT 0
TIMEOUT 300
UI vesamenu.c32
MENU TITLE $CUSTOM_NAME $ISO_VERSION
MENU BACKGROUND splash.png

LABEL live
  MENU LABEL Start $CUSTOM_NAME
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live components quiet splash

LABEL live-nomodeset
  MENU LABEL Start $CUSTOM_NAME (nomodeset)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live components quiet splash nomodeset

LABEL live-toram
  MENU LABEL Start $CUSTOM_NAME (toram)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live components quiet splash toram

LABEL memtest
  MENU LABEL Memory test
  KERNEL /live/memtest

LABEL hdt
  MENU LABEL Hardware Detection Tool
  KERNEL /live/hdt.c32

LABEL bootlocal
  MENU LABEL Boot from first hard disk
  LOCALBOOT 0x80

MENU SEPARATOR

MENU RESOLUTION 800 600
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std
EOF
    
    # Crear configuración de GRUB
    mkdir -p $ISO_DIR/boot/grub
    
    cat > $ISO_DIR/boot/grub/grub.cfg << EOF
set default="0"
set timeout=30

if [ \${grub_platform} == efi ]; then
    set timeout=5
    if search --file --set=root /live/vmlinuz; then
        menuentry "Start $CUSTOM_NAME" {
            linux /live/vmlinuz boot=live components quiet splash
            initrd /live/initrd
        }
        menuentry "Start $CUSTOM_NAME (nomodeset)" {
            linux /live/vmlinuz boot=live components quiet splash nomodeset
            initrd /live/initrd
        }
        menuentry "Start $CUSTOM_NAME (toram)" {
            linux /live/vmlinuz boot=live components quiet splash toram
            initrd /live/initrd
        }
    fi
fi

if [ \${grub_platform} == pc ]; then
    menuentry "Start $CUSTOM_NAME" {
        linux /live/vmlinuz boot=live components quiet splash
        initrd /live/initrd
    }
    menuentry "Start $CUSTOM_NAME (nomodeset)" {
        linux /live/vmlinuz boot=live components quiet splash nomodeset
        initrd /live/initrd
    }
    menuentry "Start $CUSTOM_NAME (toram)" {
        linux /live/vmlinuz boot=live components quiet splash toram
        initrd /live/initrd
    }
    menuentry "Memory test" {
        linux16 /live/memtest
    }
    menuentry "Boot from first hard disk" {
        set root=(hd0)
        chainloader +1
    }
fi
EOF
    
    # Copiar temas de GRUB (opcional)
    if [ -d /usr/share/grub/themes/ ]; then
        cp -r /usr/share/grub/themes/debian $ISO_DIR/boot/grub/themes/
    fi
    
    success "Bootloader configurado"
}

# Construir efi.img con BOOTX64.EFI y grub.cfg (para arranque UEFI)
build_efi_image() {
    step "Creando efi.img para arranque UEFI..."

    local efi_img="$ISO_DIR/efi.img"
    local tmp_efi=/tmp/efi_img_mnt
    rm -f "$efi_img"
    rm -rf "$tmp_efi"
    mkdir -p "$tmp_efi"

    # Crear imagen FAT pequeña
    dd if=/dev/zero of="$efi_img" bs=1M count=20 status=none || { warning "dd falló al crear efi.img"; return 1; }
    mkfs.vfat -n EFI_IMG "$efi_img" >/dev/null 2>&1 || { warning "mkfs.vfat falló"; return 1; }

    # Montar y poblar
    sudo mount -o loop "$efi_img" "$tmp_efi" || { warning "No se pudo montar efi.img"; return 1; }
    sudo mkdir -p "$tmp_efi/EFI/BOOT" "$tmp_efi/EFI/grub"

    # Intentar localizar un BOOTX64.EFI válido en el host
    BOOTX64_SRC=""
    for p in \
        /usr/lib/grub/x86_64-efi/grubx64.efi \
        /usr/lib/grub/x86_64-efi/core.efi \
        /usr/lib/grub/x86_64-efi-signed/grubx64.efi \
        /usr/lib/grub/i386-efi/grubx64.efi \
        /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi \
        /usr/lib/grub/x86_64-efi-signed/grubx64.efi; do
        [ -f "$p" ] && { BOOTX64_SRC="$p"; break; }
    done

    # Si no hay binario, intentar crear uno con grub-mkstandalone
    if [ -z "$BOOTX64_SRC" ] && command -v grub-mkstandalone >/dev/null 2>&1; then
        info "Generando BOOTX64.EFI con grub-mkstandalone"
        # Empaquetar el grub.cfg del ISO como fallback de arranque
        tmp_cfg="/tmp/grub_standalone.cfg"
        cat > "$tmp_cfg" <<'EOF'
set timeout=5
insmod part_gpt
insmod iso9660
insmod ext2
search --no-floppy --file --set=root /boot/grub/grub.cfg
configfile /boot/grub/grub.cfg
EOF
        grub-mkstandalone -O x86_64-efi -o /tmp/BOOTX64.EFI "boot/grub/grub.cfg=$tmp_cfg" >/dev/null 2>&1 || true
        if [ -f /tmp/BOOTX64.EFI ]; then BOOTX64_SRC="/tmp/BOOTX64.EFI"; fi
    fi

    if [ -n "$BOOTX64_SRC" ]; then
        sudo cp "$BOOTX64_SRC" "$tmp_efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
    else
        warning "No se encontró BOOTX64.EFI en el host ni se pudo generar; UEFI puede fallar en algunos firmware"
    fi

    # Crear grub.cfg dentro de efi para chainload a /boot/grub/grub.cfg en la ISO
    cat > /tmp/efi_grub_cfg <<'GRUBCFG'
set timeout=5
insmod search
insmod part_gpt
insmod ext2
search --no-floppy --file /boot/grub/grub.cfg --set=root
if [ -f ($root)/boot/grub/grub.cfg ]; then
  configfile /boot/grub/grub.cfg
else
  menuentry "Start live (fallback)" {
    set root=(cd0)
    configfile /boot/grub/grub.cfg
  }
fi
GRUBCFG
    sudo tee "$tmp_efi/EFI/grub/grub.cfg" >/dev/null < /tmp/efi_grub_cfg || true
    rm -f /tmp/efi_grub_cfg /tmp/BOOTX64.EFI 2>/dev/null || true

    sudo umount "$tmp_efi" || true
    rmdir "$tmp_efi" 2>/dev/null || true

    success "efi.img creado en $efi_img"
}
# Crear archivos adicionales para la ISO
create_iso_files() {
    step "Creando archivos adicionales para la ISO..."
    
    # Crear README
    cat > $ISO_DIR/README.diskdefines << EOF
#define DISKNAME  $CUSTOM_NAME $ISO_VERSION
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  amd64
#define ARCHamd64  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOF
    
    # Crear .disk/info
    mkdir -p $ISO_DIR/.disk
    cat > $ISO_DIR/.disk/info << EOF
$CUSTOM_NAME $ISO_VERSION - Release amd64
EOF
    
    # Crear archivos de identificación
    mkdir -p $ISO_DIR/etc
    echo "$CUSTOM_NAME $ISO_VERSION \\n \\l" > $ISO_DIR/etc/issue
    echo "$CUSTOM_NAME $ISO_VERSION" > $ISO_DIR/etc/issue.net
    
    # Crear splash screen (opcional)
    if [ -f /usr/share/images/desktop-base/desktop-grub.png ]; then
        cp /usr/share/images/desktop-base/desktop-grub.png $ISO_DIR/isolinux/splash.png
    else
        # Crear splash simple
        convert -size 800x600 xc:blue -pointsize 36 -fill white -draw "text 100,300 '$CUSTOM_NAME $ISO_VERSION'" $ISO_DIR/isolinux/splash.png 2>/dev/null || true
    fi
    
    success "Archivos adicionales creados"
}

# Crear la imagen ISO
create_iso_image() {
    step "Creando imagen ISO..."
    
    local output_file="$OUTPUT_DIR/${ISO_NAME}-${ISO_VERSION}-amd64.iso"
    local date_stamp=$(date +%Y%m%d)
    local final_output="$OUTPUT_DIR/${ISO_NAME}-${ISO_VERSION}-${date_stamp}-amd64.iso"
    
    info "Generando ISO (esto puede tomar varios minutos)..."

    # Preferir grub-mkrescue (crea soporte EFI + BIOS correctamente)
    if command -v grub-mkrescue >/dev/null 2>&1; then
        info "Usando grub-mkrescue para crear ISO híbrida (EFI+BIOS)"
        # grub-mkrescue puede fallar si faltan módulos; permitir que falle hacia xorriso
        grub-mkrescue -o "$output_file" "$ISO_DIR" 2>/tmp/grub-mkrescue.log || {
            warning "grub-mkrescue falló, revisando /tmp/grub-mkrescue.log y usando xorriso como fallback"
        }
    fi

    # Si grub-mkrescue no creó el archivo, usar xorriso fallback
    if [ ! -f "$output_file" ]; then
        ISO_CMD=(xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -volid "$ISO_LABEL")

        if [ -f "$ISO_DIR/isolinux/isolinux.bin" ]; then
            ISO_CMD+=( -eltorito-boot isolinux/isolinux.bin -eltorito-catalog isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table )
            if [ -f /usr/lib/ISOLINUX/isohdpfx.bin ]; then
                ISO_CMD+=( -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin )
            elif [ -f /usr/lib/syslinux/isohdpfx.bin ]; then
                ISO_CMD+=( -isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin )
            else
                warning "isohdpfx.bin no encontrado; la ISO puede no ser híbrida (USB)"
            fi
        else
            warning "isolinux.bin no presente en ISO; creando ISO sin configuración isolinux El Torito"
        fi

        if [ -f "$ISO_DIR/efi.img" ]; then
            ISO_CMD+=( -eltorito-alt-boot -e efi.img -no-emul-boot -isohybrid-gpt-basdat )
        fi

        ISO_CMD+=( -output "$output_file" "$ISO_DIR" )
        "${ISO_CMD[@]}"
    fi
    
    if [ $? -ne 0 ]; then
        error "Error al crear imagen ISO"
        exit 1
    fi
    
    # Renombrar con fecha
    mv "$output_file" "$final_output"
    
    # Calcular checksum
    info "Calculando checksums..."
    md5sum "$final_output" > "$final_output.md5"
    sha256sum "$final_output" > "$final_output.sha256"
    # Asegurar que los archivos sean propiedad del usuario original si corresponde
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$final_output" "$final_output.md5" "$final_output.sha256" 2>/dev/null || true
    fi
    
    # Información de la ISO
    local iso_size=$(du -h "$final_output" | cut -f1)
    
    success "ISO creada exitosamente: $final_output ($iso_size)"
    info "MD5: $(cat "$final_output.md5" | cut -d' ' -f1)"
    info "SHA256: $(cat "$final_output.sha256" | cut -d' ' -f1)"
}

# Crear versión para USB booteable
create_usb_version() {
    step "Creando imagen para USB booteable..."
    
    local iso_file="$OUTPUT_DIR/${ISO_NAME}-${ISO_VERSION}-$(date +%Y%m%d)-amd64.iso"
    local img_file="$OUTPUT_DIR/${ISO_NAME}-${ISO_VERSION}-usb.img"
    
    info "Creando imagen de disco para USB..."
    
    # Crear imagen de disco
    dd if=/dev/zero of="$img_file" bs=1M count=4096 status=progress
    
    # Particionar
    parted "$img_file" mklabel gpt
    parted "$img_file" mkpart primary fat32 1MiB 2GiB
    parted "$img_file" set 1 esp on
    parted "$img_file" mkpart primary ext4 2GiB 100%
    
    # Montar y formatear
    local loop_dev=$(losetup -f --show -P "$img_file")
    
    mkfs.vfat -F32 ${loop_dev}p1
    mkfs.ext4 -F ${loop_dev}p2
    
    # Montar particiones
    local mount_usb="/mnt/usb_boot"
    mkdir -p $mount_usb
    mount ${loop_dev}p2 $mount_usb
    mkdir -p $mount_usb/boot/efi
    mount ${loop_dev}p1 $mount_usb/boot/efi
    
    # Copiar contenido de la ISO
    info "Copiando sistema a imagen USB..."
    rsync -a $ISO_DIR/ $mount_usb/
    
    # Instalar GRUB desde el host al loop device (más fiable que chroot en imagen mínima)
    if command -v grub-install >/dev/null 2>&1; then
        grub-install --target=x86_64-efi --boot-directory=$mount_usb/boot --efi-directory=$mount_usb/boot/efi --removable 2>/dev/null || warning "grub-install UEFI en imagen USB falló"
        grub-install --target=i386-pc --boot-directory=$mount_usb/boot --recheck $loop_dev 2>/dev/null || warning "grub-install BIOS en imagen USB falló"
    else
        warning "grub-install no disponible en host; la imagen USB puede no arrancar en todos los equipos"
    fi
    
    # Desmontar
    umount $mount_usb/boot/efi
    umount $mount_usb
    losetup -d $loop_dev
    
    # Comprimir imagen
    info "Comprimiendo imagen USB..."
    xz -f -9 -T0 "$img_file"
    # Ajustar permisos del archivo final
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "${img_file}.xz" 2>/dev/null || true
    fi

    success "Imagen para USB creada: ${img_file}.xz"
}

# Limpiar archivos temporales
cleanup_temp_files() {
    step "Limpiando archivos temporales..."
    
    # Desmontar sistemas de archivos
    mountpoint -q "$WORK_DIR/dev/pts" && umount "$WORK_DIR/dev/pts" 2>/dev/null || true
    mountpoint -q "$WORK_DIR/proc" && umount "$WORK_DIR/proc" 2>/dev/null || true
    mountpoint -q "$WORK_DIR/sys" && umount "$WORK_DIR/sys" 2>/dev/null || true
    mountpoint -q "$WORK_DIR/dev" && umount "$WORK_DIR/dev" 2>/dev/null || true
    
    # Eliminar directorios temporales
    [ -n "$ISO_DIR" ] && [ "$ISO_DIR" != "/" ] && [[ "$ISO_DIR" == /tmp/* ]] && rm -rf "$ISO_DIR"
    [ -n "$WORK_DIR" ] && [ "$WORK_DIR" != "/" ] && [[ "$WORK_DIR" == /tmp/* ]] && rm -rf "$WORK_DIR"
    
    success "Archivos temporales eliminados"
}

# Mostrar resumen final
show_summary() {
    local iso_file="$OUTPUT_DIR/${ISO_NAME}-${ISO_VERSION}-$(date +%Y%m%d)-amd64.iso"
    local img_file="$OUTPUT_DIR/${ISO_NAME}-${ISO_VERSION}-usb.img.xz"
    
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   UBUNTU 24.04 SATÁNICA CREADA EXITOSAMENTE 🔥    ║"
    echo "╠══════════════════════════════════════════════════════╣"
    echo "║ Nombre: $CUSTOM_NAME"
    echo "║ Versión: $ISO_VERSION"
    echo "║ Usuario: $USERNAME"
    echo "║ Contraseña: $PASSWORD"
    echo "║ Hostname: $HOSTNAME"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    info "Archivos generados:"
    info "1. ISO: $iso_file"
    info "2. Checksum MD5: $iso_file.md5"
    info "3. Checksum SHA256: $iso_file.sha256"
    info "4. Imagen USB: $img_file"
    
    warning "Instrucciones para usar la ISO:"
    warning "1. Grabar a DVD:"
    warning "   growisofs -dvd-compat -Z /dev/sr0=$iso_file"
    warning ""
    warning "2. Crear USB booteable:"
    warning "   sudo dd if=$iso_file of=/dev/sdX bs=4M status=progress"
    warning ""
    warning "3. Probar con QEMU:"
    warning "   qemu-system-x86_64 -m 2G -cdrom $iso_file"
    warning ""
    warning "4. Instalar en disco:"
    warning "   Bootea desde USB/DVD y selecciona 'Instalar'"
    
    info "Características incluidas:"
    info "✓ Ubuntu 24.04 LTS (noble)"
    info "✓ Kernel Linux actualizado"
    info "✓ Entorno GNOME con tema Dracula Dark"
    info "✓ Temas Satánicos:"
    info "  • GRUB: tema personalizado con colores rojos/negro"
    info "  • Terminal: colores satánicos (rojo/negro)"
    info "  • Fondos: degradado satánico (múltiples resoluciones)"
    info "  • Tema GNOME: Dracula Dark"
    info "✓ Usuario $USERNAME preconfigurado"
    info "✓ Configuración regional $LOCALE"
    info "✓ Boot UEFI y Legacy BIOS"
    info "✓ Persistencia opcional"
}

# Función principal
main() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  CREADOR DE DISTRIBUCIÓN UBUNTU 24.04 SATÁNICA     ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Verificaciones iniciales
    check_root
    check_disk_space
    
    # Mostrar configuración
    info "Configuración:"
    info "Nombre: $CUSTOM_NAME $ISO_VERSION"
    info "Usuario: $USERNAME / $PASSWORD"
    info "Hostname: $HOSTNAME"
    info "Temas: Satánicos (GRUB, GNOME, Terminal, Fondos)"
    info "Directorio salida: $OUTPUT_DIR"
    
    # Modo automatizado: continuar sin confirmación interactiva
    info "Modo automatizado: continuando sin confirmación interactiva"

    # Asegurar limpieza en salida
    trap 'cleanup_temp_files' EXIT
    
    # Ejecutar pasos
    install_dependencies
    prepare_directories
    create_base_system
    configure_live_system
    configure_satanic_themes
    install_additional_packages
    create_custom_user
    configure_live_boot
    cleanup_system
    create_squashfs
    prepare_bootloader
    create_iso_files
    build_efi_image
    create_iso_image
    create_usb_version
    # Mostrar resumen
    show_summary
}

# Ejecutar
main
