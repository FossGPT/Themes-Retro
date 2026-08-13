#!/bin/bash

set -e

SERVICE_NAME="amber-bar-gate.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
SCRIPT_FILE="/usr/local/sbin/amber-bar-gate"

echo "==> Instalando Amber Bar gate..."

# Comprobar root
if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta este instalador como root:"
    echo "sudo $0"
    exit 1
fi

# Comprobar archivos
if [ ! -f "$SERVICE_FILE" ]; then
    echo "ERROR: no existe:"
    echo "$SERVICE_FILE"
    exit 1
fi

if [ ! -x "$SCRIPT_FILE" ]; then
    echo "ERROR: no existe o no es ejecutable:"
    echo "$SCRIPT_FILE"
    exit 1
fi

# Recargar systemd
echo "==> Recargando systemd..."
systemctl daemon-reload

# Habilitar servicio
echo "==> Habilitando $SERVICE_NAME..."
systemctl enable "$SERVICE_NAME"

echo
echo "========================================"
echo " Amber Bar instalado correctamente"
echo "========================================"
echo
echo "Servicio:"
echo "  $SERVICE_NAME"
echo
echo "Estado:"
systemctl is-enabled "$SERVICE_NAME"