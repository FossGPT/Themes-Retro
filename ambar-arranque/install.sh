#!/bin/bash

set -u

# ============================================================
# AMBER BAR
# Plymouth Theme + Systemd Boot Gate
# Ubuntu Server 22.04
# ============================================================

THEME_NAME="amber-bar"

THEME_DIR="/usr/share/plymouth/themes/${THEME_NAME}"

PLYMOUTH_FILE="${THEME_DIR}/${THEME_NAME}.plymouth"
PLYMOUTH_SCRIPT="${THEME_DIR}/${THEME_NAME}.script"

SERVICE_NAME="amber-bar-gate.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

GATE_SCRIPT="/usr/local/sbin/amber-bar-gate"

ALT_NAME="default.plymouth"

INITRAMFS_TIMEOUT=10

# ============================================================
# COLORES
# ============================================================

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

# ============================================================
# FUNCIONES
# ============================================================

info()
{
    echo -e "${CYAN}[INFO]${RESET} $1"
}

ok()
{
    echo -e "${GREEN}[ OK ]${RESET} $1"
}

warn()
{
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

error()
{
    echo -e "${RED}[ERROR]${RESET} $1"
}

# ============================================================
# ROOT
# ============================================================

if [ "$EUID" -ne 0 ]; then
    error "Este instalador debe ejecutarse como root."
    echo
    echo "Usa:"
    echo
    echo "    sudo $0"
    echo
    exit 1
fi

clear

echo
echo "============================================================"
echo "                 AMBER BAR INSTALLER"
echo "============================================================"
echo
echo "Plymouth theme : ${THEME_NAME}"
echo "Service        : ${SERVICE_NAME}"
echo "Initramfs      : ${INITRAMFS_TIMEOUT}s timeout"
echo
echo "============================================================"
echo

# ============================================================
# COMPROBAR UBUNTU
# ============================================================

if [ -f /etc/os-release ]; then

    . /etc/os-release

    info "Sistema detectado: ${PRETTY_NAME}"

    if [ "${ID:-}" != "ubuntu" ]; then
        warn "Este instalador está diseñado para Ubuntu."
    fi

fi

# ============================================================
# COMPROBAR PLYMOUTH
# ============================================================

if ! command -v plymouth >/dev/null 2>&1; then

    error "Plymouth no está instalado."

    echo
    echo "Instala Plymouth con:"
    echo
    echo "    sudo apt install plymouth plymouth-themes"
    echo

    exit 1

fi

ok "Plymouth encontrado."

# ============================================================
# COMPROBAR TEMA
# ============================================================

info "Comprobando tema Amber Bar..."

if [ ! -d "$THEME_DIR" ]; then

    error "No existe el directorio:"
    echo
    echo "    $THEME_DIR"
    echo

    exit 1

fi

if [ ! -f "$PLYMOUTH_FILE" ]; then

    error "No existe:"
    echo
    echo "    $PLYMOUTH_FILE"
    echo

    exit 1

fi

if [ ! -f "$PLYMOUTH_SCRIPT" ]; then

    error "No existe:"
    echo
    echo "    $PLYMOUTH_SCRIPT"
    echo

    exit 1

fi

ok "Tema Amber Bar encontrado."

# ============================================================
# MOSTRAR ALTERNATIVA ACTUAL
# ============================================================

echo
info "Alternativa Plymouth actual:"
echo

update-alternatives --display "$ALT_NAME" 2>/dev/null || true

echo

# ============================================================
# REGISTRAR AMBER BAR
# ============================================================

info "Registrando Amber Bar en update-alternatives..."

update-alternatives \
    --install \
    /usr/share/plymouth/themes/default.plymouth \
    "$ALT_NAME" \
    "$PLYMOUTH_FILE" \
    200

ok "Amber Bar registrado."

# ============================================================
# SELECCIONAR AMBER BAR
# ============================================================

info "Seleccionando Amber Bar como tema Plymouth..."

update-alternatives \
    --set \
    "$ALT_NAME" \
    "$PLYMOUTH_FILE"

ok "Amber Bar seleccionado."

# ============================================================
# VERIFICAR SELECCIÓN
# ============================================================

echo
info "Tema Plymouth seleccionado:"

CURRENT_THEME=$(readlink -f /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true)

echo
echo "    ${CURRENT_THEME}"
echo

if [ "$CURRENT_THEME" = "$PLYMOUTH_FILE" ]; then

    ok "Amber Bar es el tema Plymouth activo."

else

    warn "La alternativa no apunta exactamente a Amber Bar."
    warn "Revisa la salida anterior."

fi

# ============================================================
# CREAR GATE SCRIPT
# ============================================================

echo
info "Instalando Amber Bar Gate..."

cat > "$GATE_SCRIPT" <<'EOF'
#!/bin/bash

set -u

PLYMOUTH="/usr/bin/plymouth"
FLAG="/run/amber-bar-enter"

# ------------------------------------------------------------
# Limpiar estado anterior
# ------------------------------------------------------------

rm -f "$FLAG"

# ------------------------------------------------------------
# Comprobar Plymouth
# ------------------------------------------------------------

if [ ! -x "$PLYMOUTH" ]; then
    exit 1
fi

# ------------------------------------------------------------
# Avisar al tema de Plymouth
#
# Amber Bar debe detectar:
#
#     __VT320_READY__
#
# y cambiar:
#
#     WAIT
#
# por:
#
#     VT320 OK
# ------------------------------------------------------------

"$PLYMOUTH" display-message \
    --text="__VT320_READY__" || true

# ------------------------------------------------------------
# Esperar ENTER
# ------------------------------------------------------------

"$PLYMOUTH" watch-keystroke \
    --keys=$'\n' \
    --command="/usr/bin/touch $FLAG" || true

# ------------------------------------------------------------
# Esperar hasta que llegue ENTER
# ------------------------------------------------------------

while [ ! -f "$FLAG" ]; do
    sleep 0.05
done

# ------------------------------------------------------------
# ENTER recibido
# ------------------------------------------------------------

"$PLYMOUTH" quit || true

exit 0
EOF

chmod 755 "$GATE_SCRIPT"

ok "Gate instalado:"
echo "    $GATE_SCRIPT"

# ============================================================
# CREAR SERVICIO SYSTEMD
# ============================================================

info "Creando servicio systemd..."

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

ok "Servicio creado:"
echo "    $SERVICE_FILE"

# ============================================================
# SYSTEMD DAEMON RELOAD
# ============================================================

info "Recargando configuración de systemd..."

systemctl daemon-reload

ok "systemd recargado."

# ============================================================
# ENABLE
# ============================================================

info "Habilitando Amber Bar Gate..."

systemctl enable "$SERVICE_NAME"

ok "Amber Bar Gate habilitado."

# ============================================================
# COMPROBAR SERVICIO
# ============================================================

echo
info "Estado del servicio:"

systemctl is-enabled "$SERVICE_NAME" || true

# ============================================================
# UPDATE-INITRAMFS
# ============================================================

echo
echo "============================================================"
echo "             ACTUALIZANDO INITRAMFS"
echo "============================================================"
echo
echo "Tiempo máximo: ${INITRAMFS_TIMEOUT} segundos"
echo

info "Ejecutando update-initramfs -u..."

# ------------------------------------------------------------
# timeout:
#
# 10 segundos máximo.
#
# Si tarda más:
#
#   TERM
#
# después de 2 segundos:
#
#   KILL
#
# y el instalador continúa.
# ------------------------------------------------------------

if timeout \
    --signal=TERM \
    --kill-after=2s \
    "${INITRAMFS_TIMEOUT}s" \
    update-initramfs -u
then

    ok "initramfs actualizado correctamente."

else

    RESULT=$?

    if [ "$RESULT" -eq 124 ]; then

        warn "update-initramfs superó ${INITRAMFS_TIMEOUT} segundos."

        warn "El proceso fue detenido."

        warn "Continuando con el instalador..."

    else

        warn "update-initramfs terminó con código: ${RESULT}"

        warn "Continuando con el instalador..."

    fi

fi

# ============================================================
# UPDATE-GRUB
# ============================================================

echo
info "Actualizando GRUB..."

if update-grub; then

    ok "GRUB actualizado."

else

    warn "update-grub terminó con un error."

fi

# ============================================================
# VERIFICACIÓN FINAL
# ============================================================

echo
echo "============================================================"
echo "                    VERIFICACIÓN"
echo "============================================================"
echo

info "Tema seleccionado:"

readlink -f \
    /usr/share/plymouth/themes/default.plymouth \
    2>/dev/null || true

echo

info "Servicio:"

systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true

echo

info "Archivos Amber Bar:"

echo "    $PLYMOUTH_FILE"
echo "    $PLYMOUTH_SCRIPT"
echo "    $GATE_SCRIPT"
echo "    $SERVICE_FILE"

echo

# ============================================================
# FINAL
# ============================================================

echo "============================================================"
echo "              AMBER BAR INSTALADO"
echo "============================================================"
echo
echo "Tema seleccionado:"
echo
echo "    $PLYMOUTH_FILE"
echo
echo "Servicio:"
echo
echo "    $SERVICE_NAME"
echo
echo "El servicio está habilitado para el próximo arranque."
echo
echo "No necesitas ejecutar manualmente:"
echo
echo "    update-alternatives --set ..."
echo "    update-initramfs -u"
echo "    update-grub"
echo
echo "Para probar Amber Bar:"
echo
echo "    sudo reboot"
echo
echo "============================================================"
echo