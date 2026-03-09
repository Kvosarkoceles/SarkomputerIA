#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERR]${NC} $*"; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  err "Ejecuta como root: sudo bash $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
APT_OPTS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

log "1) Reparando estado de paquetes..."
dpkg --configure -a || true
apt-get -f install -y || true
apt-get update
apt-get check

log "2) Verificando EFI y reparando GRUB..."
if [[ -d /sys/firmware/efi ]]; then
  mkdir -p /boot/efi
  if ! findmnt /boot/efi >/dev/null 2>&1; then
    warn "/boot/efi no montado. Intentando montar por fstab..."
    mount /boot/efi || warn "No se pudo montar /boot/efi automáticamente."
  fi

  if findmnt /boot/efi >/dev/null 2>&1; then
    EFI_PART=$(findmnt -n -o SOURCE /boot/efi || true)
    EFI_DISK=""
    if [[ -n "$EFI_PART" ]]; then
      EFI_DISK="/dev/$(lsblk -no pkname "$EFI_PART" 2>/dev/null || true)"
    fi

    apt-get install -y $APT_OPTS grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed shim-signed efibootmgr
    if [[ -n "$EFI_DISK" && -b "$EFI_DISK" ]]; then
      grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck "$EFI_DISK" || grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
    else
      grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
    fi
    update-grub
    log "GRUB UEFI reparado"
  else
    warn "No se pudo montar /boot/efi; omito reparación de GRUB por seguridad"
  fi
else
  warn "Sistema no UEFI; omito bloque UEFI"
fi

log "3) Reparando pila NVIDIA..."
apt-get install -y $APT_OPTS dkms linux-headers-$(uname -r) nvidia-driver nvidia-kernel-dkms nvidia-persistenced || true

if modprobe nvidia 2>/dev/null; then
  systemctl enable --now nvidia-persistenced || true
  log "Módulo NVIDIA cargado y persistenced activo"
else
  warn "No se pudo cargar módulo nvidia; reconstruyendo DKMS"
  dkms autoinstall -k "$(uname -r)" || true
  update-initramfs -u -k "$(uname -r)" || true
  if modprobe nvidia 2>/dev/null; then
    systemctl enable --now nvidia-persistenced || true
    log "NVIDIA recuperado tras DKMS"
  else
    warn "Sigue sin cargar NVIDIA. Deshabilitando persistenced para limpiar errores de systemd"
    systemctl disable --now nvidia-persistenced || true
    systemctl reset-failed nvidia-persistenced || true
  fi
fi

log "4) Limpieza final..."
apt-get autoremove -y || true
apt-get autoclean -y || true

log "5) Estado final"
systemctl --failed --no-pager || true
apt-get check || true

log "Reparación terminada. Recomendado: reiniciar el sistema."
