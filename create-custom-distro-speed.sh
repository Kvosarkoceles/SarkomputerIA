#!/bin/bash

# Script rápido para crear ISO del sistema actual
# sudo ./create-quick-iso.sh

set -e

# Configuración
ISO_NAME="my-system-backup"
OUTPUT_DIR="$HOME/Desktop"
WORK_DIR="/tmp/live-iso-work"
ISO_DIR="$WORK_DIR/iso"

# Crear directorios
mkdir -p $ISO_DIR/live $WORK_DIR/chroot

# Copiar sistema excluyendo lo innecesario
echo "Copiando sistema..."
rsync -a --delete \
    --exclude=/proc \
    --exclude=/sys \
    --exclude=/dev \
    --exclude=/tmp \
    --exclude=/run \
    --exclude=/mnt \
    --exclude=/media \
    --exclude=/home/*/.cache \
    --exclude=/var/cache \
    --exclude=/var/tmp \
    / \
    $WORK_DIR/chroot/

# Preparar sistema Live
echo "Preparando sistema Live..."
mount --bind /proc $WORK_DIR/chroot/proc
mount --bind /sys $WORK_DIR/chroot/sys
mount --bind /dev $WORK_DIR/chroot/dev

# Crear squashfs
echo "Creando squashfs..."
mksquashfs $WORK_DIR/chroot $ISO_DIR/live/filesystem.squashfs -comp xz

# Copiar kernel
cp $WORK_DIR/chroot/boot/vmlinuz-* $ISO_DIR/live/vmlinuz
cp $WORK_DIR/chroot/boot/initrd.img-* $ISO_DIR/live/initrd

# Configurar bootloader
mkdir -p $ISO_DIR/boot/grub
cat > $ISO_DIR/boot/grub/grub.cfg << EOF
set timeout=10
menuentry "Live System" {
    linux /live/vmlinuz boot=live components
    initrd /live/initrd
}
EOF

# Crear ISO
echo "Creando ISO..."
grub-mkrescue -o $OUTPUT_DIR/$ISO_NAME.iso $ISO_DIR

# Limpiar
umount $WORK_DIR/chroot/{proc,sys,dev}
rm -rf $WORK_DIR

echo "ISO creada: $OUTPUT_DIR/$ISO_NAME.iso"
