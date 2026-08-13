#!/bin/bash
set -u

THEME_NAME="amber-bar"
THEME_DIR="/usr/share/plymouth/themes/${THEME_NAME}"
PLYMOUTH_FILE="${THEME_DIR}/${THEME_NAME}.plymouth"
PLYMOUTH_SCRIPT="${THEME_DIR}/${THEME_NAME}.script"
SERVICE_NAME="amber-bar-gate.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
GATE_SCRIPT="/usr/local/sbin/amber-bar-gate"
BACKUP_DIR="/var/lib/amber-bar"
BACKUP_FILE="${BACKUP_DIR}/previous-plymouth"
LOG_FILE="/tmp/amber-bar-installer.log"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
RESET="\033[0m"

pause() {
    echo
    read -r -p "Presiona ENTER para continuar..."
}

info() {
    printf "%b[INFO]%b %s\n" "$CYAN" "$RESET" "$1"
}

ok() {
    printf "%b[ OK ]%b %s\n" "$GREEN" "$RESET" "$1"
}

warn() {
    printf "%b[WARN]%b %s\n" "$YELLOW" "$RESET" "$1"
}

error() {
    printf "%b[ERROR]%b %s\n" "$RED" "$RESET" "$1"
}

check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        error "Este programa debe ejecutarse como root."
        echo "Ejecuta: sudo bash \"$0\""
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

show_current_theme() {
    local current
    current="$(readlink -f /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true)"

    echo
    echo "Tema Plymouth actualmente seleccionado:"
    if [ -n "$current" ]; then
        echo "  $current"
    else
        echo "  No determinado"
    fi
    echo
}

run_with_spinner() {
    local label="$1"
    shift
    local spinner='|/-\'
    local index=0
    local elapsed=0
    local pid
    local result

    "$@" >>"$LOG_FILE" 2>&1 &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r[ %s ] %s %02ds" "${spinner:index:1}" "$label" "$elapsed"
        sleep 1
        elapsed=$((elapsed + 1))
        index=$(( (index + 1) % 4 ))
    done

    wait "$pid"
    result=$?
    printf "\r\033[K"

    return "$result"
}

install_packages() {
    echo
    echo "=============================================="
    echo "          INSTALANDO DEPENDENCIAS"
    echo "=============================================="
    echo

    if command_exists plymouth && dpkg-query -W -f='${Status}' plymouth-themes 2>/dev/null | grep -q "install ok installed"; then
        ok "Plymouth y plymouth-themes ya están instalados."
        return 0
    fi

    : >"$LOG_FILE"

    info "Actualizando información de paquetes..."
    if ! run_with_spinner "Actualizando paquetes..." apt-get update; then
        error "No se pudo actualizar la información de paquetes."
        tail -n 15 "$LOG_FILE" 2>/dev/null || true
        return 1
    fi

    info "Instalando Plymouth y plymouth-themes..."
    if ! run_with_spinner "Instalando paquetes..." apt-get install -y plymouth plymouth-themes; then
        error "No se pudieron instalar las dependencias."
        tail -n 15 "$LOG_FILE" 2>/dev/null || true
        return 1
    fi

    ok "Dependencias instaladas correctamente."
    return 0
}

check_plymouth() {
    if ! command_exists plymouth; then
        error "Plymouth no está instalado."
        return 1
    fi
    return 0
}

install_theme_files() {
    local installer_dir source_dir

    installer_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    source_dir="${installer_dir}/${THEME_NAME}"

    if [ ! -d "$source_dir" ]; then
        error "No se encontró la carpeta:"
        echo "  $source_dir"
        echo
        echo "La estructura debe ser:"
        echo "  amber-bar-installer.sh"
        echo "  amber-bar/"
        echo "    amber-bar.plymouth"
        echo "    amber-bar.script"
        return 1
    fi

    if [ ! -f "${source_dir}/${THEME_NAME}.plymouth" ] || [ ! -f "${source_dir}/${THEME_NAME}.script" ]; then
        error "La carpeta amber-bar no contiene los archivos necesarios."
        echo "Se requieren:"
        echo "  ${THEME_NAME}.plymouth"
        echo "  ${THEME_NAME}.script"
        return 1
    fi

    info "Instalando archivos de Amber Bar..."
    mkdir -p "$THEME_DIR"
    cp -a "$source_dir"/. "$THEME_DIR"/
    chmod -R a+rX "$THEME_DIR"

    if [ ! -f "$PLYMOUTH_FILE" ] || [ ! -f "$PLYMOUTH_SCRIPT" ]; then
        error "No se pudieron instalar correctamente los archivos del tema."
        return 1
    fi

    ok "Amber Bar instalado en $THEME_DIR."
}

save_previous_theme() {
    local current
    mkdir -p "$BACKUP_DIR"
    current="$(readlink -f /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true)"

    if [ -n "$current" ] && [ "$current" != "$PLYMOUTH_FILE" ]; then
        printf '%s\n' "$current" >"$BACKUP_FILE"
    fi
}

select_theme() {
    update-alternatives --install \
        /usr/share/plymouth/themes/default.plymouth \
        default.plymouth \
        "$PLYMOUTH_FILE" \
        100

    update-alternatives --set default.plymouth "$PLYMOUTH_FILE"

    local current
    current="$(readlink -f /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true)"

    if [ "$current" != "$PLYMOUTH_FILE" ]; then
        error "No se pudo seleccionar Amber Bar."
        echo "Tema actual: ${current:-desconocido}"
        return 1
    fi

    ok "Amber Bar es ahora el tema activo."
}

create_gate() {
    cat >"$GATE_SCRIPT" <<'EOF'
#!/bin/bash
set -u

PLYMOUTH="/usr/bin/plymouth"
FLAG="/run/amber-bar-enter"

rm -f "$FLAG"

[ -x "$PLYMOUTH" ] || exit 1

"$PLYMOUTH" display-message --text="__VT320_READY__" >/dev/null 2>&1 || true

"$PLYMOUTH" watch-keystroke \
    --keys="ENTER" \
    --command="/usr/bin/touch $FLAG" >/dev/null 2>&1 || true

while [ ! -f "$FLAG" ]; do
    sleep 0.05
done

"$PLYMOUTH" quit >/dev/null 2>&1 || true
exit 0
EOF

    chmod 755 "$GATE_SCRIPT"
    ok "Gate instalado."
}

create_service() {
    cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Amber Bar Plymouth Boot Gate
After=plymouth-start.service systemd-user-sessions.service
Before=plymouth-quit.service plymouth-quit-wait.service display-manager.service

[Service]
Type=oneshot
ExecStart=${GATE_SCRIPT}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null
    ok "Servicio Amber Bar Gate instalado y habilitado."
}

update_initramfs_safe() {
    echo
    echo "=============================================="
    echo "             ACTUALIZANDO INITRAMFS"
    echo "=============================================="
    echo

    : >"$LOG_FILE"
    info "Ejecutando update-initramfs -u -k all..."

    if run_with_spinner "Actualizando initramfs..." update-initramfs -u -k all; then
        ok "initramfs actualizado correctamente."
        return 0
    fi

    warn "update-initramfs terminó con errores."
    tail -n 15 "$LOG_FILE" 2>/dev/null || true
    return 1
}

update_grub_safe() {
    echo
    info "Actualizando GRUB..."

    if ! command_exists update-grub; then
        warn "update-grub no está disponible."
        return 1
    fi

    if update-grub; then
        ok "GRUB actualizado."
        return 0
    fi

    warn "update-grub terminó con errores."
    return 1
}

install_amber_bar() {
    clear

    echo "============================================================"
    echo "              INSTALANDO AMBER BAR"
    echo "============================================================"
    echo

    if ! install_packages; then
        pause
        return
    fi

    if ! check_plymouth; then
        pause
        return
    fi

    save_previous_theme

    if ! install_theme_files; then
        pause
        return
    fi

    if ! select_theme; then
        pause
        return
    fi

    create_gate
    create_service

    if ! update_initramfs_safe; then
        warn "La actualización de initramfs falló."
        pause
        return
    fi

    update_grub_safe || true

    echo
    echo "============================================================"
    echo "              INSTALACIÓN COMPLETA"
    echo "============================================================"
    echo
    echo "Tema activo:"
    readlink -f /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true
    echo
    echo "Servicio:"
    systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true
    echo
    ok "Amber Bar quedó instalado."
    echo
    pause
}

restart_system() {
    clear
    echo
    echo "El sistema se reiniciará en 3 segundos..."
    sleep 3
    reboot
}

uninstall_amber_bar() {
    clear

    echo "============================================================"
    echo "              DESINSTALANDO AMBER BAR"
    echo "============================================================"
    echo

    read -r -p "¿Seguro que quieres desinstalar Amber Bar? [s/N]: " answer

    case "$answer" in
        s|S|si|SI|Si|sí|SÍ)
            ;;
        *)
            info "Desinstalación cancelada."
            pause
            return
            ;;
    esac

    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true

    rm -f "$SERVICE_FILE" "$GATE_SCRIPT"
    rm -f /run/amber-bar-enter
    systemctl daemon-reload

    update-alternatives --remove default.plymouth "$PLYMOUTH_FILE" >/dev/null 2>&1 || true

    if [ -f "$BACKUP_FILE" ]; then
        local previous
        previous="$(cat "$BACKUP_FILE")"

        if [ -f "$previous" ]; then
            update-alternatives --set default.plymouth "$previous" >/dev/null 2>&1 || true
        else
            update-alternatives --auto default.plymouth >/dev/null 2>&1 || true
        fi
    else
        update-alternatives --auto default.plymouth >/dev/null 2>&1 || true
    fi

    rm -rf "$THEME_DIR"
    rm -rf "$BACKUP_DIR"

    update_initramfs_safe || true
    update_grub_safe || true

    echo
    echo "============================================================"
    echo "            DESINSTALACIÓN COMPLETA"
    echo "============================================================"
    echo
    ok "Amber Bar ha sido eliminado."
    echo
    echo "Tema Plymouth actual:"
    readlink -f /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true
    echo

    pause
}

main_menu() {
    while true; do
        clear

        echo
        printf "%b╔══════════════════════════════════════════════╗%b\n" "$WHITE" "$RESET"
        printf "%b║              AMBER BAR INSTALLER            ║%b\n" "$WHITE" "$RESET"
        printf "%b╠══════════════════════════════════════════════╣%b\n" "$WHITE" "$RESET"
        printf "%b║                                              ║%b\n" "$WHITE" "$RESET"
        printf "%b║  %b1%b) Instalar / actualizar Amber Bar          %b║%b\n" "$WHITE" "$GREEN" "$WHITE" "$WHITE" "$RESET"
        printf "%b║  %b2%b) Reiniciar sistema                       %b║%b\n" "$WHITE" "$CYAN" "$WHITE" "$WHITE" "$RESET"
        printf "%b║  %b3%b) Desinstalar Amber Bar                    %b║%b\n" "$WHITE" "$RED" "$WHITE" "$WHITE" "$RESET"
        printf "%b║  %b4%b) Salir                                    %b║%b\n" "$WHITE" "$YELLOW" "$WHITE" "$WHITE" "$RESET"
        printf "%b║                                              ║%b\n" "$WHITE" "$RESET"
        printf "%b╚══════════════════════════════════════════════╝%b\n" "$WHITE" "$RESET"

        show_current_theme

        read -r -p "Selecciona una opción [1-4]: " option

        case "$option" in
            1) install_amber_bar ;;
            2) restart_system ;;
            3) uninstall_amber_bar ;;
            4) clear; exit 0 ;;
            *) error "Opción inválida."; sleep 1 ;;
        esac
    done
}

check_root
main_menu
