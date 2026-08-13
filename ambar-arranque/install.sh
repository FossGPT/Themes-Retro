#!/bin/bash

set -e

# ============================================================
# Amber Bar - Plymouth Boot Gate Installer
# Ubuntu Server 22.04
# ============================================================

SERVICE_NAME="amber-bar-gate.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
GATE_SCRIPT="/usr/local/sbin/amber-bar-gate"

PLYMOUTH_THEME_DIR="/usr/share/plymouth/themes/amber-bar"

echo
echo "=============================================="
echo "        AMBER BAR BOOT GATE INSTALLER"
echo "=============================================="
echo

# ------------------------------------------------------------
# Comprobar root
# ------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Este instalador debe ejecutarse como root."
    echo
    echo "Usa:"
    echo "  sudo $0"
    echo
    exit 1
fi

# ------------------------------------------------------------
# Comprobar Ubuntu
# ------------------------------------------------------------

if [ -f /etc/os-release ]; then
    . /etc/os-release

    echo "[INFO] Sistema: $PRETTY_NAME"

    if [ "$ID" != "ubuntu" ]; then
        echo
        echo "[ADVERTENCIA] Este instalador está diseñado para Ubuntu."
        echo
    fi
fi

# ------------------------------------------------------------
# Comprobar Plymouth
# ------------------------------------------------------------

if ! command -v plymouth >/dev/null 2>&1; then
    echo
    echo "[ERROR] Plymouth no está instalado."
    echo
    echo "Instálalo con:"
    echo
    echo "  sudo apt install plymouth plymouth-themes"
    echo
    exit 1
fi

echo "[OK] Plymouth encontrado."

# ------------------------------------------------------------
# Comprobar tema Amber Bar
# ------------------------------------------------------------

if [ ! -d "$PLYMOUTH_THEME_DIR" ]; then
    echo
    echo "[ERROR] No existe el tema Amber Bar:"
    echo
    echo "  $PLYMOUTH_THEME_DIR"
    echo
    echo "Primero instala el tema Amber Bar."
    echo
    exit 1
fi

echo "[OK] Tema Amber Bar encontrado."

# ------------------------------------------------------------
# Mostrar alternativa actual
# ------------------------------------------------------------

echo
echo "[INFO] Alternativa Plymouth actualmente seleccionada:"
echo

if command -v update-alternatives >/dev/null 2>&1; then
    update-alternatives --display default.plymouth 2>/dev/null || true
fi

echo

# ------------------------------------------------------------
# Crear script Amber Bar Gate
# ------------------------------------------------------------

echo "[1/6] Creando Amber Bar Gate..."

cat > "$GATE_SCRIPT" <<'EOF'
#!/bin/bash

set -u

PLYMOUTH="/usr/bin/plymouth"

# ------------------------------------------------------------
# Comprobar Plymouth
# ------------------------------------------------------------

if [ ! -x "$PLYMOUTH" ]; then
    exit 1
fi

# ------------------------------------------------------------
# Avisar al tema Amber Bar
#
# El script de Plymouth debe interpretar:
#
#     __VT320_READY__
#
# como:
#
#     WAIT -> pantalla final
# ------------------------------------------------------------

"$PLYMOUTH" display-message \
    --text="__VT320_READY__" || true


# ------------------------------------------------------------
# Esperar ENTER
#
# Plymouth se encarga de recibir la tecla.
# ------------------------------------------------------------

FLAG="/run/amber-bar-enter"

rm -f "$FLAG"


"$PLYMOUTH" watch-keystroke \
    --keys=$'\n' \
    --command="/usr/bin/touch $FLAG" || true


# ------------------------------------------------------------
# Esperar hasta recibir ENTER
# ------------------------------------------------------------

while [ ! -f "$FLAG" ]; do
    sleep 0.05
done


# ------------------------------------------------------------
# ENTER recibido
#
# Permitir que el sistema continúe.
# ------------------------------------------------------------

"$PLYMOUTH" quit || true

exit 0
EOF

chmod 755 "$GATE_SCRIPT"

echo "[OK] $GATE_SCRIPT creado."

# ------------------------------------------------------------
# Crear servicio systemd
# ------------------------------------------------------------

echo
echo "[2/6] Creando servicio systemd..."

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Amber Bar Plymouth Boot Gate

After=plymouth-start.service
After=systemd-user-sessions.service

Before=plymouth-quit.service
Before=plymouth-quit-wait.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/amber-bar-gate
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"

echo "[OK] $SERVICE_FILE creado."

# ------------------------------------------------------------
# Recargar systemd
# ------------------------------------------------------------

echo
echo "[3/6] Recargando systemd..."

systemctl daemon-reload

echo "[OK] systemd recargado."

# ------------------------------------------------------------
# Habilitar servicio
# ------------------------------------------------------------

echo
echo "[4/6] Habilitando Amber Bar Gate..."

systemctl enable "$SERVICE_NAME"

echo "[OK] Servicio habilitado."

# ------------------------------------------------------------
# Actualizar initramfs
# ------------------------------------------------------------

echo
echo "[5/6] Actualizando initramfs..."

update-initramfs -u

echo "[OK] initramfs actualizado."

# ------------------------------------------------------------
# Verificación
# ------------------------------------------------------------

echo
echo "[6/6] Verificando instalación..."

echo
echo "Servicio:"
systemctl is-enabled "$SERVICE_NAME"

echo
echo "Archivo del servicio:"
ls -l "$SERVICE_FILE"

echo
echo "Script:"
ls -l "$GATE_SCRIPT"

echo
echo "Tema:"
ls -ld "$PLYMOUTH_THEME_DIR"

echo
echo "=============================================="
echo "        AMBER BAR INSTALADO"
echo "=============================================="
echo
echo "Servicio:"
echo "  $SERVICE_NAME"
echo
echo "Gate:"
echo "  $GATE_SCRIPT"
echo
echo "Tema:"
echo "  $PLYMOUTH_THEME_DIR"
echo
echo "El servicio está habilitado para el próximo"
echo "arranque."
echo
echo "IMPORTANTE:"
echo "  No se ha modificado update-alternatives."
echo
echo "Para probar:"
echo
echo "  sudo reboot"
echo
echo "=============================================="
echo