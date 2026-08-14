#!/bin/bash

set -u

APP_NAME="Themes Retro Installer"
APP_VERSION="1.0.0"
REPO_URL="https://github.com/FossGPT/Themes-Retro.git"
REPO_RAW="https://raw.githubusercontent.com/FossGPT/Themes-Retro/main"

INSTALL_DIR="/opt/themes-retro"
STATE_DIR="/var/lib/themes-retro"
BACKUP_DIR="/var/backups/themes-retro"
LOG_FILE="/var/log/themes-retro-installer.log"

CURRENT_THEME_FILE="${STATE_DIR}/current-theme"
INSTALLED_PACKAGES_FILE="${STATE_DIR}/installed-packages"
BACKUP_LIST_FILE="${STATE_DIR}/backups"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
BLUE="\033[0;34m"
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

header() {
    clear
    printf "%b╔══════════════════════════════════════════════════════╗%b\n" "$WHITE" "$RESET"
    printf "%b║              THEMES RETRO INSTALLER                 ║%b\n" "$WHITE" "$RESET"
    printf "%b║                    v%s                         ║%b\n" "$WHITE" "$APP_VERSION" "$RESET"
    printf "%b╚══════════════════════════════════════════════════════╝%b\n" "$WHITE" "$RESET"
    echo
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Este instalador debe ejecutarse como root."
        echo
        echo "Ejecuta:"
        echo "sudo bash $0"
        exit 1
    fi
}

check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        error "No se pudo determinar la distribución."
        exit 1
    fi

    . /etc/os-release

    if [ "${ID:-}" != "ubuntu" ]; then
        error "Este instalador está diseñado para Ubuntu."
        exit 1
    fi

    if [ "${VERSION_ID:-}" != "22.04" ]; then
        warn "Se detectó Ubuntu ${VERSION_ID:-desconocido}."
        warn "Este instalador fue diseñado para Ubuntu 22.04."
        echo
        read -r -p "¿Deseas continuar? [s/N]: " answer

        case "$answer" in
            s|S|si|SI|Si|sí|SÍ)
                ;;
            *)
                exit 1
                ;;
        esac
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

prepare_directories() {
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$STATE_DIR"
    mkdir -p "$BACKUP_DIR"

    touch "$LOG_FILE"
    touch "$INSTALLED_PACKAGES_FILE"
    touch "$BACKUP_LIST_FILE"
}

install_base_tools() {
    local packages=(
        git
        curl
        wget
        ca-certificates
        software-properties-common
        xz-utils
        unzip
        fontconfig
    )

    echo
    echo "Comprobando herramientas necesarias..."
    echo

    apt-get update >>"$LOG_FILE" 2>&1

    for package in "${packages[@]}"; do
        if package_installed "$package"; then
            ok "$package ya está instalado."
        else
            info "Instalando $package..."
            if apt-get install -y "$package" >>"$LOG_FILE" 2>&1; then
                ok "$package instalado."
            else
                error "No se pudo instalar $package."
                return 1
            fi
        fi
    done
}

install_desktop_packages() {
    local packages=(
        xorg
        xserver-xorg
        xserver-xorg-core
        bspwm
        sxhkd
        polybar
        rofi
        ranger
        htop
    )

    echo
    echo "======================================================"
    echo "              INSTALANDO COMPONENTES"
    echo "======================================================"
    echo

    for package in "${packages[@]}"; do
        if package_installed "$package"; then
            ok "$package ya está instalado. Saltando."
        else
            info "Instalando $package..."

            if apt-get install -y "$package" >>"$LOG_FILE" 2>&1; then
                ok "$package instalado."

                if ! grep -qxF "$package" "$INSTALLED_PACKAGES_FILE"; then
                    echo "$package" >>"$INSTALLED_PACKAGES_FILE"
                fi
            else
                error "No se pudo instalar $package."
                return 1
            fi
        fi
    done

    echo
    ok "Componentes principales instalados."
}

detect_user() {
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        TARGET_USER="$SUDO_USER"
    else
        TARGET_USER="$(logname 2>/dev/null || echo root)"
    fi

    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

    if [ -z "$TARGET_HOME" ]; then
        TARGET_HOME="/root"
    fi
}

backup_file() {
    local file="$1"

    if [ ! -e "$file" ]; then
        return 0
    fi

    local relative
    relative="${file#/}"

    local destination
    destination="${BACKUP_DIR}/${relative}"

    mkdir -p "$(dirname "$destination")"

    cp -a "$file" "$destination"

    if ! grep -qxF "$file" "$BACKUP_LIST_FILE"; then
        echo "$file" >>"$BACKUP_LIST_FILE"
    fi

    ok "Copia de seguridad: $file"
}

backup_user_configuration() {
    echo
    echo "======================================================"
    echo "             CREANDO COPIAS DE SEGURIDAD"
    echo "======================================================"
    echo

    backup_file "$TARGET_HOME/.config/bspwm"
    backup_file "$TARGET_HOME/.config/sxhkd"
    backup_file "$TARGET_HOME/.config/polybar"
    backup_file "$TARGET_HOME/.config/rofi"
    backup_file "$TARGET_HOME/.config/ranger"
}

clone_repository() {
    rm -rf "$INSTALL_DIR/repository"

    info "Descargando Themes-Retro..."

    if git clone --depth=1 "$REPO_URL" "$INSTALL_DIR/repository" >>"$LOG_FILE" 2>&1; then
        ok "Repositorio descargado correctamente."
        return 0
    fi

    error "No se pudo descargar el repositorio."
    return 1
}

copy_directory_if_exists() {
    local source="$1"
    local destination="$2"

    if [ ! -d "$source" ]; then
        warn "No existe: $source"
        return 0
    fi

    mkdir -p "$destination"
    cp -a "$source"/. "$destination"/

    chown -R "$TARGET_USER:$TARGET_USER" "$destination" 2>/dev/null || true

    ok "Configuración instalada en $destination"
}

install_bspwm() {
    local source="$INSTALL_DIR/repository/bspwm"
    local destination="$TARGET_HOME/.config/bspwm"

    if [ ! -d "$source" ]; then
        warn "No se encontró configuración de bspwm en el repositorio."
        return 0
    fi

    copy_directory_if_exists "$source" "$destination"
}

install_polybar() {
    local source="$INSTALL_DIR/repository/polybar"
    local destination="$TARGET_HOME/.config/polybar"

    if [ ! -d "$source" ]; then
        warn "No se encontró configuración de polybar en el repositorio."
        return 0
    fi

    copy_directory_if_exists "$source" "$destination"
}

install_sxhkd() {
    local source="$INSTALL_DIR/repository/sxhkd"
    local destination="$TARGET_HOME/.config/sxhkd"

    if [ ! -d "$source" ]; then
        warn "No se encontró configuración de sxhkd en el repositorio."
        return 0
    fi

    copy_directory_if_exists "$source" "$destination"
}

install_rofi() {
    local source="$INSTALL_DIR/repository/rofi"
    local destination="$TARGET_HOME/.config/rofi"

    if [ !d "$source" ]; then
        return 0
    fi

    copy_directory_if_exists "$source" "$destination"
}

install_ranger() {
    local source="$INSTALL_DIR/repository/ranger"
    local destination="$TARGET_HOME/.config/ranger"

    if [ ! -d "$source" ]; then
        return 0
    fi

    copy_directory_if_exists "$source" "$destination"
}

install_system_files() {
    local source="$INSTALL_DIR/repository/system"

    if [ ! -d "$source" ]; then
        warn "No existe la carpeta system del repositorio."
        return 0
    fi

    if [ -d "$source/etc" ]; then
        cp -a "$source/etc"/. /etc/
        ok "Archivos de sistema instalados."
    fi

    if [ -d "$source/usr" ]; then
        cp -a "$source/usr"/. /usr/
        ok "Archivos /usr instalados."
    fi
}

install_startup_files() {
    local source="$INSTALL_DIR/repository/system_startup"

    if [ ! -d "$source" ]; then
        warn "No existe system_startup."
        return 0
    fi

    if [ -d "$source/etc" ]; then
        cp -a "$source/etc"/. /etc/
        ok "Configuración de inicio instalada."
    fi

    if [ -d "$source/usr" ]; then
        cp -a "$source/usr"/. /usr/
        ok "Archivos de inicio instalados."
    fi
}

set_permissions() {
    if [ -d "$TARGET_HOME/.config" ]; then
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config" 2>/dev/null || true
    fi

    find "$TARGET_HOME/.config" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

    ok "Permisos configurados."
}

set_bspwm_session() {
    local session_file="/usr/share/xsessions/bspwm.desktop"

    cat >"$session_file" <<EOF
[Desktop Entry]
Name=bspwm
Comment=Binary Space Partitioning Window Manager
Exec=bspwm
Type=Application
DesktopNames=bspwm
EOF

    chmod 644 "$session_file"

    ok "Sesión bspwm registrada."
}

enable_services() {
    systemctl daemon-reload

    if systemctl list-unit-files 2>/dev/null | grep -q "^system_startup.service"; then
        systemctl enable system_startup.service >/dev/null 2>&1 || true
    fi

    ok "Servicios actualizados."
}

save_theme() {
    local theme="$1"

    echo "$theme" >"$CURRENT_THEME_FILE"

    chmod 644 "$CURRENT_THEME_FILE"
}

get_current_theme() {
    if [ -f "$CURRENT_THEME_FILE" ]; then
        cat "$CURRENT_THEME_FILE"
    else
        echo "Ninguno"
    fi
}

install_theme() {
    local theme="$1"
    local theme_name="$2"

    header

    echo "Tema seleccionado:"
    echo
    printf "%b%s%b\n" "$CYAN" "$theme_name" "$RESET"
    echo

    read -r -p "¿Deseas instalar este tema? [s/N]: " answer

    case "$answer" in
        s|S|si|SI|Si|sí|SÍ)
            ;;
        *)
            info "Instalación cancelada."
            pause
            return
            ;;
    esac

    prepare_directories
    detect_user

    echo
    info "Usuario objetivo: $TARGET_USER"
    info "Directorio HOME: $TARGET_HOME"
    echo

    if ! install_base_tools; then
        error "Falló la instalación de herramientas base."
        pause
        return
    fi

    if ! install_desktop_packages; then
        error "Falló la instalación de componentes."
        pause
        return
    fi

    backup_user_configuration

    if ! clone_repository; then
        pause
        return
    fi

    echo
    echo "======================================================"
    echo "               INSTALANDO CONFIGURACIÓN"
    echo "======================================================"
    echo

    case "$theme" in
        "dec-vt330")
            install_bspwm
            install_sxhkd
            install_polybar
            install_rofi
            install_ranger
            ;;
        "gridcase-1520")
            install_bspwm
            install_sxhkd
            install_polybar
            install_rofi
            install_ranger
            ;;
    esac

    install_system_files
    install_startup_files

    set_permissions
    set_bspwm_session
    enable_services

    save_theme "$theme_name"

    echo
    echo "======================================================"
    echo "             INSTALACIÓN COMPLETADA"
    echo "======================================================"
    echo
    ok "Tema instalado: $theme_name"
    echo
    echo "Usuario: $TARGET_USER"
    echo "Entorno: bspwm"
    echo
    warn "Es recomendable reiniciar el sistema antes de utilizar"
    warn "el nuevo entorno gráfico."
    echo

    pause
}

install_menu() {
    while true; do
        header

        echo "1) DEC VT330 Basic"
        echo "2) GRIDcase 1520 Basic"
        echo "3) Volver"
        echo

        read -r -p "Selecciona una opción [1-3]: " option

        case "$option" in
            1)
                install_theme "dec-vt330" "DEC VT330 Basic"
                ;;
            2)
                install_theme "gridcase-1520" "GRIDcase 1520 Basic"
                ;;
            3)
                return
                ;;
            *)
                error "Opción inválida."
                sleep 1
                ;;
        esac
    done
}

show_theme_versions() {
    header

    echo "======================================================"
    echo "                  TEMAS DISPONIBLES"
    echo "======================================================"
    echo

    echo "DEC VT330 Basic"
    echo "Color principal: #FFB000"
    echo
    echo "GRIDcase 1520 Basic"
    echo "Color principal: #FF5A00"
    echo

    pause
}

show_version() {
    header

    echo "======================================================"
    echo "                    VERSIÓN"
    echo "======================================================"
    echo

    echo "Installer: $APP_VERSION"
    echo "Repositorio:"
    echo "$REPO_URL"
    echo
    echo "Tema instalado:"
    echo "$(get_current_theme)"
    echo

    if [ -d "$INSTALL_DIR/repository/.git" ]; then
        echo "Commit instalado:"
        git -C "$INSTALL_DIR/repository" rev-parse --short HEAD 2>/dev/null || echo "No disponible"
        echo
    fi

    pause
}

versions_menu() {
    while true; do
        header

        echo "1) Temas versiones"
        echo "2) Revisar versión"
        echo "3) Volver"
        echo

        read -r -p "Selecciona una opción [1-3]: " option

        case "$option" in
            1)
                show_theme_versions
                ;;
            2)
                show_version
                ;;
            3)
                return
                ;;
            *)
                error "Opción inválida."
                sleep 1
                ;;
        esac
    done
}

restore_backups() {
    if [ ! -f "$BACKUP_LIST_FILE" ]; then
        return
    fi

    echo
    info "Restaurando configuraciones anteriores..."

    while IFS= read -r file; do
        [ -z "$file" ] && continue

        local relative
        relative="${file#/}"

        local backup
        backup="${BACKUP_DIR}/${relative}"

        if [ -e "$backup" ]; then
            rm -rf "$file"
            mkdir -p "$(dirname "$file")"
            cp -a "$backup" "$file"

            ok "Restaurado: $file"
        fi
    done <"$BACKUP_LIST_FILE"
}

remove_theme_configuration() {
    echo
    info "Eliminando configuraciones del tema..."

    rm -rf "$TARGET_HOME/.config/bspwm"
    rm -rf "$TARGET_HOME/.config/sxhkd"
    rm -rf "$TARGET_HOME/.config/polybar"
    rm -rf "$TARGET_HOME/.config/rofi"
    rm -rf "$TARGET_HOME/.config/ranger"

    if [ -d "/etc/systemd/system" ]; then
        find /etc/systemd/system -type f -iname "*themes-retro*" -delete 2>/dev/null || true
    fi

    systemctl daemon-reload

    ok "Configuraciones del tema eliminadas."
}

remove_installed_packages() {
    if [ ! -f "$INSTALLED_PACKAGES_FILE" ]; then
        return
    fi

    echo
    echo "Paquetes instalados por Themes Retro:"
    echo

    cat "$INSTALLED_PACKAGES_FILE"

    echo
    read -r -p "¿También quieres eliminar estos paquetes? [s/N]: " answer

    case "$answer" in
        s|S|si|SI|Si|sí|SÍ)
            while IFS= read -r package; do
                [ -z "$package" ] && continue

                if package_installed "$package"; then
                    info "Eliminando $package..."
                    apt-get remove -y "$package" >>"$LOG_FILE" 2>&1 || true
                fi
            done <"$INSTALLED_PACKAGES_FILE"

            apt-get autoremove -y >>"$LOG_FILE" 2>&1 || true

            ok "Paquetes eliminados."
            ;;
        *)
            info "Los paquetes no serán eliminados."
            ;;
    esac
}

uninstall_theme() {
    header

    echo "======================================================"
    echo "                  DESINSTALAR"
    echo "======================================================"
    echo

    echo "1) ¿Estas seguro que quieres desinstalar?"
    echo "2) Volver"
    echo

    read -r -p "Selecciona una opción [1-2]: " option

    case "$option" in
        1)
            ;;
        2)
            return
            ;;
        *)
            error "Opción inválida."
            sleep 1
            return
            ;;
    esac

    echo
    read -r -p "Esta acción eliminará la configuración del tema. ¿Continuar? [s/N]: " answer

    case "$answer" in
        s|S|si|SI|Si|sí|SÍ)
            ;;
        *)
            info "Desinstalación cancelada."
            pause
            return
            ;;
    esac

    detect_user
    prepare_directories

    remove_theme_configuration
    restore_backups
    remove_installed_packages

    rm -rf "$INSTALL_DIR"
    rm -f "$CURRENT_THEME_FILE"

    echo
    echo "======================================================"
    echo "           DESINSTALACIÓN COMPLETADA"
    echo "======================================================"
    echo

    ok "Themes Retro ha sido desinstalado."
    echo
    echo "Las copias de seguridad permanecen en:"
    echo "$BACKUP_DIR"
    echo

    pause
}

restart_menu() {
    header

    echo "======================================================"
    echo "                    REINICIAR"
    echo "======================================================"
    echo

    echo "1) ¿Estas seguro que quieres reiniciar?"
    echo "2) Volver"
    echo

    read -r -p "Selecciona una opción [1-2]: " option

    case "$option" in
        1)
            clear
            echo
            echo "El sistema se reiniciará en 5 segundos..."
            echo
            sleep 5
            reboot
            ;;
        2)
            return
            ;;
        *)
            error "Opción inválida."
            sleep 1
            ;;
    esac
}

main_menu() {
    while true; do
        header

        echo "Tema instalado:"
        printf "%b%s%b\n" "$CYAN" "$(get_current_theme)" "$RESET"
        echo

        echo "1) Instalar"
        echo "2) Versiones"
        echo "3) Desinstalar"
        echo "4) Reiniciar"
        echo "5) Salir"
        echo

        read -r -p "Selecciona una opción [1-5]: " option

        case "$option" in
            1)
                install_menu
                ;;
            2)
                versions_menu
                ;;
            3)
                uninstall_theme
                ;;
            4)
                restart_menu
                ;;
            5)
                clear
                exit 0
                ;;
            *)
                error "Opción inválida."
                sleep 1
                ;;
        esac
    done
}

check_root
check_ubuntu
prepare_directories
main_menu