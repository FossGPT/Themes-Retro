#!/bin/bash

# ============================================================
# AMBER BAR INSTALLER
# Ubuntu Server 22.04
#
# Opciones:
#   1 - Instalar / actualizar
#   2 - Reiniciar
#   3 - Desinstalar
#   4 - Salir
# ============================================================

set -u

# ------------------------------------------------------------
# CONFIGURACIÓN
# ------------------------------------------------------------

THEME_NAME="amber-bar"

THEME_DIR="/usr/share/plymouth/themes/${THEME_NAME}"

PLYMOUTH_FILE="${THEME_DIR}/${THEME_NAME}.plymouth"
PLYMOUTH_SCRIPT="${THEME_DIR}/${THEME_NAME}.script"

SERVICE_NAME="amber-bar-gate.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

GATE_SCRIPT="/usr/local/sbin/amber-bar-gate"

ALT_NAME="default.plymouth"

INITRAMFS_TIMEOUT=10

# Archivo donde guardamos la alternativa anterior
BACKUP_FILE="/var/lib/amber-bar/previous-plymouth"

# ------------------------------------------------------------
# COLORES
# ------------------------------------------------------------

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
RESET="\033[0m"

# ------------------------------------------------------------
# FUNCIONES
# ------------------------------------------------------------

pause()
{
    echo
    read -rp "Presiona ENTER para continuar..."
}

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

# ------------------------------------------------------------
# ROOT
# ------------------------------------------------------------

check_root()
{
    if [ "$EUID" -ne 0 ]; then
        error "Este programa debe ejecutarse como root."
        echo
        echo "Ejecuta:"
        echo
        echo "    sudo $0"
        echo
        exit 1
    fi
}

# ------------------------------------------------------------
# COMPROBAR PLYMOUTH
# ------------------------------------------------------------

check_plymouth()
{
    if ! command -v plymouth >/dev/null 2>&1; then

        error "Plymouth no está instalado."

        echo
        echo "Puedes instalarlo con:"
        echo
        echo "    sudo apt install plymouth plymouth-themes"
        echo

        return 1
    fi

    return 0
}

# ------------------------------------------------------------
# MOSTRAR TEMA ACTUAL
# ------------------------------------------------------------

show_current_theme()
{
    echo
    echo "----------------------------------------------"
    echo "Tema Plymouth actualmente seleccionado:"
    echo "----------------------------------------------"
    echo

    CURRENT_THEME=$(readlink -f \
        /usr/share/plymouth/themes/default.plymouth \
        2>/dev/null || true)

    if [ -n "$CURRENT_THEME" ]; then
        echo "    $CURRENT_THEME"
    else
        echo "    No determinado"
    fi

    echo
}

# ------------------------------------------------------------
# GUARDAR TEMA ANTERIOR
# ------------------------------------------------------------

save_previous_theme()
{
    mkdir -p /var/lib/amber-bar

    CURRENT_THEME=$(readlink -f \
        /usr/share/plymouth/themes/default.plymouth \
        2>/dev/null || true)

    if [ -n "$CURRENT_THEME" ] &&
       [ "$CURRENT_THEME" != "$PLYMOUTH_FILE" ]; then

        echo "$CURRENT_THEME" > "$BACKUP_FILE"

        info "Tema anterior guardado:"
        echo "    $CURRENT_THEME"

    fi
}

# ------------------------------------------------------------
# UPDATE INITRAMFS CON TIMEOUT
# ------------------------------------------------------------

update_initramfs_safe()
{
    echo
    echo "=============================================="
    echo "        ACTUALIZANDO INITRAMFS"
    echo "=============================================="
    echo
    echo "Tiempo máximo: ${INITRAMFS_TIMEOUT} segundos."
    echo

    info "Ejecutando update-initramfs -u -k all..."

    if timeout \
        --signal=TERM \
        --kill-after=2s \
        "${INITRAMFS_TIMEOUT}s" \
        update-initramfs -u -k all
    then

        ok "initramfs actualizado correctamente."

    else

        RESULT=$?

        if [ "$RESULT" -eq 124 ]; then

            warn "update-initramfs superó ${INITRAMFS_TIMEOUT} segundos."
            warn "El proceso fue detenido."
            warn "El instalador continuará."

        else

            warn "update-initramfs terminó con código ${RESULT}."
            warn "El instalador continuará."

        fi
    fi
}

# ------------------------------------------------------------
# UPDATE GRUB
# ------------------------------------------------------------

update_grub_safe()
{
    echo
    info "Actualizando GRUB..."

    if update-grub; then
        ok "GRUB actualizado."
    else
        warn "update-grub terminó con errores."
    fi
}

# ============================================================
# INSTALAR
# ============================================================

install_amber_bar()
{
    clear

    echo
    echo "============================================================"
    echo "              INSTALANDO AMBER BAR"
    echo "============================================================"
    echo

    # --------------------------------------------------------
    # Comprobar Plymouth
    # --------------------------------------------------------

    if ! check_plymouth; then
        pause
        return
    fi

    # --------------------------------------------------------
    # Comprobar tema
    # --------------------------------------------------------

    if [ ! -d "$THEME_DIR" ]; then

        error "No existe:"
        echo
        echo "    $THEME_DIR"
        echo
        echo "Debes colocar primero el tema Amber Bar allí."

        pause
        return
    fi

    if [ ! -f "$PLYMOUTH_FILE" ]; then

        error "No existe:"
        echo
        echo "    $PLYMOUTH_FILE"

        pause
        return
    fi

    if [ ! -f "$PLYMOUTH_SCRIPT" ]; then

        error "No existe:"
        echo
        echo "    $PLYMOUTH_SCRIPT"

        pause
        return
    fi

    ok "Tema Amber Bar encontrado."

    # --------------------------------------------------------
    # Guardar alternativa anterior
    # --------------------------------------------------------

    save_previous_theme

    # --------------------------------------------------------
    # Registrar alternativa
    # --------------------------------------------------------

    echo
    info "Registrando Amber Bar..."

    update-alternatives \
        --install \
        /usr/share/plymouth/themes/default.plymouth \
        "$ALT_NAME" \
        "$PLYMOUTH_FILE" \
        200

    ok "Amber Bar registrado."

    # --------------------------------------------------------
    # FORZAR SELECCIÓN
    # --------------------------------------------------------

    info "Seleccionando Amber Bar..."

    update-alternatives \
        --set \
        "$ALT_NAME" \
        "$PLYMOUTH_FILE"

    CURRENT_THEME=$(readlink -f \
        /usr/share/plymouth/themes/default.plymouth)

    echo

    if [ "$CURRENT_THEME" = "$PLYMOUTH_FILE" ]; then

        ok "Amber Bar es ahora el tema activo."

    else

        error "No se pudo seleccionar Amber Bar."
        echo
        echo "Tema actual:"
        echo "$CURRENT_THEME"
        echo

        pause
        return
    fi

    # --------------------------------------------------------
    # CREAR GATE SCRIPT
    # --------------------------------------------------------

    echo
    info "Instalando Amber Bar Gate..."

    cat > "$GATE_SCRIPT" <<'EOF'
#!/bin/bash

set -u

PLYMOUTH="/usr/bin/plymouth"
FLAG="/run/amber-bar-enter"

rm -f "$FLAG"

if [ ! -x "$PLYMOUTH" ]; then
    exit 1
fi

# Avisar al tema Plymouth que el sistema está listo.

/usr/bin/plymouth display-message \
    --text="__VT320_READY__" || true

# Esperar ENTER.

/usr/bin/plymouth watch-keystroke \
    --keys=$'\n' \
    --command="/usr/bin/touch $FLAG" || true

# Esperar ENTER.

/usr/bin/plymouth watch-keystroke \
    --keys="ENTER" \
    --command="/usr/bin/touch $FLAG" || true

while [ ! -f "$FLAG" ]; do
    sleep 0.05
done

# Continuar.

/usr/bin/plymouth quit || true

exit 0
EOF

    chmod 755 "$GATE_SCRIPT"

    ok "Gate instalado."

    # --------------------------------------------------------
    # CREAR SERVICIO
    # --------------------------------------------------------

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

    ok "Servicio creado."

    # --------------------------------------------------------
    # SYSTEMD
    # --------------------------------------------------------

    info "Recargando systemd..."

    systemctl daemon-reload

    ok "systemd recargado."

    # --------------------------------------------------------
    # ENABLE
    # --------------------------------------------------------

    info "Habilitando Amber Bar Gate..."

    systemctl enable "$SERVICE_NAME"

    ok "Servicio habilitado."

    # --------------------------------------------------------
    # INITRAMFS
    # --------------------------------------------------------

    update_initramfs_safe

    # --------------------------------------------------------
    # GRUB
    # --------------------------------------------------------

    update_grub_safe

    # --------------------------------------------------------
    # VERIFICACIÓN
    # --------------------------------------------------------

    echo
    echo "============================================================"
    echo "                  INSTALACIÓN COMPLETA"
    echo "============================================================"
    echo

    echo "Tema activo:"
    echo
    readlink -f \
        /usr/share/plymouth/themes/default.plymouth
    echo

    echo "Servicio:"
    echo
    systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true

    echo
    echo "Archivos:"
    echo
    echo "  $PLYMOUTH_FILE"
    echo "  $PLYMOUTH_SCRIPT"
    echo "  $GATE_SCRIPT"
    echo "  $SERVICE_FILE"

    echo
    echo "============================================================"
    echo

    ok "Amber Bar quedó instalado."

    echo
    echo "Para probarlo selecciona:"
    echo
    echo "    2) Reiniciar"
    echo

    pause
}

# ============================================================
# REINICIAR
# ============================================================

restart_system()
{
    clear

    echo
    echo "============================================================"
    echo "                    REINICIAR"
    echo "============================================================"
    echo

    echo "El sistema se reiniciará en 3 segundos..."
    echo

    sleep 3

    reboot
}

# ============================================================
# DESINSTALAR
# ============================================================

uninstall_amber_bar()
{
    clear

    echo
    echo "============================================================"
    echo "              DESINSTALANDO AMBER BAR"
    echo "============================================================"
    echo

    read -rp "¿Seguro que quieres desinstalar Amber Bar? [s/N]: " ANSWER

    case "$ANSWER" in
        s|S|si|SI|Si)
            ;;
        *)
            echo
            info "Desinstalación cancelada."
            pause
            return
            ;;
    esac

    # --------------------------------------------------------
    # DETENER/DESHABILITAR SERVICIO
    # --------------------------------------------------------

    echo
    info "Deshabilitando Amber Bar Gate..."

    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    ok "Servicio deshabilitado."

    # --------------------------------------------------------
    # ELIMINAR SERVICIO
    # --------------------------------------------------------

    if [ -f "$SERVICE_FILE" ]; then

        rm -f "$SERVICE_FILE"

        ok "Servicio eliminado."

    fi

    # --------------------------------------------------------
    # ELIMINAR GATE
    # --------------------------------------------------------

    if [ -f "$GATE_SCRIPT" ]; then

        rm -f "$GATE_SCRIPT"

        ok "Amber Bar Gate eliminado."

    fi

    # --------------------------------------------------------
    # DAEMON RELOAD
    # --------------------------------------------------------

    info "Recargando systemd..."

    systemctl daemon-reload

    ok "systemd recargado."

    # --------------------------------------------------------
    # ELIMINAR ALTERNATIVA AMBER BAR
    # --------------------------------------------------------

    info "Eliminando Amber Bar de update-alternatives..."

    update-alternatives \
        --remove \
        "$ALT_NAME" \
        "$PLYMOUTH_FILE" \
        2>/dev/null || true

    ok "Amber Bar eliminado de update-alternatives."

    # --------------------------------------------------------
    # RESTAURAR TEMA ANTERIOR
    # --------------------------------------------------------

    if [ -f "$BACKUP_FILE" ]; then

        PREVIOUS_THEME=$(cat "$BACKUP_FILE")

        if [ -f "$PREVIOUS_THEME" ]; then

            info "Restaurando tema anterior..."

            update-alternatives \
                --set \
                "$ALT_NAME" \
                "$PREVIOUS_THEME" \
                2>/dev/null || true

            ok "Tema anterior restaurado."

        else

            warn "El tema anterior ya no existe:"
            echo "    $PREVIOUS_THEME"

            warn "Se dejará que update-alternatives seleccione otro tema."

            update-alternatives \
                --auto \
                "$ALT_NAME" \
                2>/dev/null || true
        fi

    else

        info "No hay tema anterior guardado."
        info "Seleccionando automáticamente otro tema..."

        update-alternatives \
            --auto \
            "$ALT_NAME" \
            2>/dev/null || true
    fi

    # --------------------------------------------------------
    # ELIMINAR TEMA
    # --------------------------------------------------------

    if [ -d "$THEME_DIR" ]; then

        info "Eliminando archivos de Amber Bar..."

        rm -rf "$THEME_DIR"

        ok "Tema Amber Bar eliminado."

    fi

    # --------------------------------------------------------
    # ACTUALIZAR INITRAMFS
    # --------------------------------------------------------

    update_initramfs_safe

    # --------------------------------------------------------
    # ACTUALIZAR GRUB
    # --------------------------------------------------------

    update_grub_safe

    # --------------------------------------------------------
    # ELIMINAR BACKUP
    # --------------------------------------------------------

    rm -rf /var/lib/amber-bar

    # --------------------------------------------------------
    # RESULTADO
    # --------------------------------------------------------

    echo
    echo "============================================================"
    echo "              DESINSTALACIÓN COMPLETA"
    echo "============================================================"
    echo

    echo "Tema Plymouth actual:"
    echo

    readlink -f \
        /usr/share/plymouth/themes/default.plymouth \
        2>/dev/null || true

    echo

    ok "Amber Bar ha sido eliminado."

    echo
    echo "Para comprobar el resultado, reinicia el sistema."
    echo

    pause
}

# ============================================================
# MENÚ
# ============================================================

main_menu()
{
    while true; do

        clear

        echo
        echo -e "${WHITE}╔══════════════════════════════════════════════╗${RESET}"
        echo -e "${WHITE}║              AMBER BAR INSTALLER            ║${RESET}"
        echo -e "${WHITE}╠══════════════════════════════════════════════╣${RESET}"
        echo -e "${WHITE}║                                              ║${RESET}"
        echo -e "${WHITE}║  ${GREEN}1${WHITE}) Instalar / actualizar Amber Bar          ║${RESET}"
        echo -e "${WHITE}║  ${CYAN}2${WHITE}) Reiniciar sistema                       ║${RESET}"
        echo -e "${WHITE}║  ${RED}3${WHITE}) Desinstalar Amber Bar                    ║${RESET}"
        echo -e "${WHITE}║  ${YELLOW}4${WHITE}) Salir                                    ║${RESET}"
        echo -e "${WHITE}║                                              ║${RESET}"
        echo -e "${WHITE}╚══════════════════════════════════════════════╝${RESET}"
        echo

        show_current_theme

        read -rp "Selecciona una opción [1-4]: " OPTION

        case "$OPTION" in

            1)
                install_amber_bar
                ;;

            2)
                restart_system
                ;;

            3)
                uninstall_amber_bar
                ;;

            4)
                clear
                echo
                echo "Saliendo..."
                echo
                exit 0
                ;;

            *)
                error "Opción inválida."
                sleep 1
                ;;

        esac

    done
}

# ============================================================
# START
# ============================================================

check_root

main_menu