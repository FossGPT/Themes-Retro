#!/usr/bin/env bash

set -u
set -o pipefail

APP_NAME="Themes Retro"
APP_VERSION="2.2.0"

REPO_URL="https://github.com/FossGPT/Themes-Retro.git"

INSTALL_ROOT="/opt/themes-retro"
REPO_DIR="$INSTALL_ROOT/repository"

STATE_ROOT="/var/lib/themes-retro"
BACKUP_ROOT="/var/backups/themes-retro"

LOG_FILE="/var/log/themes-retro.log"

TARGET_USER=""
TARGET_HOME=""

BSPWMRC=""
SXHKDRC=""
POLYBAR_CONFIG=""

THEME_NAME=""
THEME_ID=""

C_RESET="\033[0m"
C_ORANGE="\033[38;5;208m"
C_GREEN="\033[38;5;82m"
C_RED="\033[38;5;196m"
C_CYAN="\033[38;5;51m"
C_AMBER="\033[38;5;214m"
C_WHITE="\033[1;37m"
C_GRAY="\033[38;5;245m"

declare -A DEP_LABEL=(
    [xorg]="Xorg"
    [xinit]="xinit / startx"
    [x11-xserver-utils]="X11 Utilities"
    [bspwm]="bspwm"
    [sxhkd]="sxhkd"
    [polybar]="Polybar"
    [rofi]="Rofi"
    [ranger]="Ranger"
    [htop]="htop"
    [plymouth]="Plymouth"
)

DEP_LIST=(
    xorg
    xinit
    x11-xserver-utils
    bspwm
    sxhkd
    polybar
    rofi
    ranger
    htop
    plymouth
)

clear_screen() {
    clear
}

log() {
    printf '[%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$1" >> "$LOG_FILE" 2>/dev/null || true
}

run_visible() {

    printf '\n%b[PROC]%b %s\n' \
        "$C_ORANGE" \
        "$C_RESET" \
        "$*"

    log "COMMAND: $*"

    "$@" 2>&1 | tee -a "$LOG_FILE"

    local status=${PIPESTATUS[0]}

    if [[ "$status" -eq 0 ]]; then
        printf '%b[ OK ]%b Comando completado.\n' \
            "$C_GREEN" \
            "$C_RESET"
    else
        printf '%b[FAIL]%b El comando terminó con código %s.\n' \
            "$C_RED" \
            "$C_RESET" \
            "$status"
    fi

    return "$status"
}

info() {
    printf '%b[INFO]%b %s\n' \
        "$C_CYAN" \
        "$C_RESET" \
        "$1"
}

success() {
    printf '%b[ OK ]%b %s\n' \
        "$C_GREEN" \
        "$C_RESET" \
        "$1"
}

warning() {
    printf '%b[WARN]%b %s\n' \
        "$C_AMBER" \
        "$C_RESET" \
        "$1"
}

error_msg() {
    printf '%b[ERROR]%b %s\n' \
        "$C_RED" \
        "$C_RESET" \
        "$1"
}

pause_screen() {
    echo
    read -r -p "Presiona ENTER para continuar..." _
}

draw_header() {

    clear_screen

    printf '%b╔══════════════════════════════════════════════════════════════╗%b\n' \
        "$C_ORANGE" \
        "$C_RESET"

    printf '%b║                       THEMES RETRO                          ║%b\n' \
        "$C_ORANGE" \
        "$C_RESET"

    printf '%b║                  INSTALLER v%-8s                     ║%b\n' \
        "$C_ORANGE" \
        "$APP_VERSION" \
        "$C_RESET"

    printf '%b╚══════════════════════════════════════════════════════════════╝%b\n\n' \
        "$C_ORANGE" \
        "$C_RESET"

    printf ' Usuario : %b%s%b\n' \
        "$C_GREEN" \
        "$TARGET_USER" \
        "$C_RESET"

    printf ' HOME    : %b%s%b\n' \
        "$C_GREEN" \
        "$TARGET_HOME" \
        "$C_RESET"

    printf ' Tema    : %b%s%b\n\n' \
        "$C_GREEN" \
        "$(current_theme)" \
        "$C_RESET"
}

require_root() {

    if [[ "$EUID" -ne 0 ]]; then
        exec sudo -E bash "$0" "$@"
    fi
}

check_ubuntu() {

    if [[ ! -f /etc/os-release ]]; then
        error_msg "No se pudo detectar el sistema operativo."
        exit 1
    fi

    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then

        error_msg "Este instalador solamente funciona en Ubuntu."

        echo
        echo "Sistema detectado:"
        echo "${PRETTY_NAME:-desconocido}"

        exit 1
    fi

    if [[ "${VERSION_ID:-}" != "22.04" ]]; then

        error_msg "Este instalador está diseñado para Ubuntu Server 22.04."

        echo
        echo "Versión detectada:"
        echo "${VERSION_ID:-desconocida}"

        exit 1
    fi
}

detect_user() {

    local user=""

    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then

        user="$SUDO_USER"

    elif [[ -n "${USER:-}" && "${USER}" != "root" ]]; then

        user="$USER"

    else

        user="$(
            awk -F: '
                $3 >= 1000 && $3 < 60000 {
                    print $1
                    exit
                }
            ' /etc/passwd
        )"

    fi

    if [[ -z "$user" ]]; then

        error_msg "No se pudo detectar el usuario."

        exit 1
    fi

    if ! id "$user" >/dev/null 2>&1; then

        error_msg "El usuario $user no existe."

        exit 1
    fi

    TARGET_USER="$user"

    TARGET_HOME="$(
        getent passwd "$TARGET_USER" |
        cut -d: -f6
    )"

    if [[ -z "$TARGET_HOME" ]]; then

        error_msg "No se encontró el HOME del usuario."

        exit 1
    fi
}

prepare_directories() {

    mkdir -p "$INSTALL_ROOT"
    mkdir -p "$STATE_ROOT"
    mkdir -p "$BACKUP_ROOT"

    touch "$LOG_FILE"

    touch "$STATE_ROOT/installed_packages"
    touch "$STATE_ROOT/created_files"
    touch "$STATE_ROOT/modified_files"
    touch "$STATE_ROOT/backups"
    touch "$STATE_ROOT/installed_themes"
}

pkg_installed() {

    dpkg-query \
        -W \
        -f='${Status}' \
        "$1" 2>/dev/null |
        grep -q '^install ok installed$'
}

ensure_whiptail() {

    if command -v whiptail >/dev/null 2>&1; then
        return 0
    fi

    apt-get update >> "$LOG_FILE" 2>&1 || return 1

    apt-get install \
        -y \
        whiptail \
        >> "$LOG_FILE" 2>&1
}

ensure_apt() {

    info "Actualizando los repositorios de Ubuntu..."

    if apt-get update >> "$LOG_FILE" 2>&1; then

        success "Repositorios actualizados."

        return 0

    fi

    error_msg "No se pudo actualizar APT."

    return 1
}

current_theme() {

    if [[ -f "$STATE_ROOT/current_theme" ]]; then

        cat "$STATE_ROOT/current_theme"

    else

        echo "Ninguno"

    fi
}

tui_msg() {

    whiptail \
        --title "$APP_NAME" \
        --msgbox "$1" \
        15 \
        78
}

tui_yesno() {

    whiptail \
        --title "$APP_NAME" \
        --yesno "$1" \
        15 \
        78
}

backup_file() {

    local source="$1"

    [[ -e "$source" || -L "$source" ]] || return 0

    local relative
    local destination

    if [[ "$source" == "$TARGET_HOME/"* ]]; then

        relative="home/${TARGET_USER}/${source#"$TARGET_HOME/"}"

    elif [[ "$source" == /usr/share/* ]]; then

        relative="usr/share/${source#/usr/share/}"

    elif [[ "$source" == /etc/* ]]; then

        relative="etc/${source#/etc/}"

    else

        relative="other/${source#/}"

    fi

    destination="$BACKUP_ROOT/$relative"

    mkdir -p "$(dirname "$destination")"

    rm -rf "$destination"

    cp -a "$source" "$destination"

    printf '%s|%s\n' \
        "$source" \
        "$destination" \
        >> "$STATE_ROOT/backups"
}

record_created() {

    grep -Fxq "$1" \
        "$STATE_ROOT/created_files" 2>/dev/null ||
        echo "$1" >> "$STATE_ROOT/created_files"
}

record_modified() {

    grep -Fxq "$1" \
        "$STATE_ROOT/modified_files" 2>/dev/null ||
        echo "$1" >> "$STATE_ROOT/modified_files"
}

copy_file_safe() {

    local source="$1"
    local destination="$2"
    local mode="${3:-0644}"

    if [[ ! -f "$source" ]]; then

        warning "Archivo no encontrado: $source"

        return 1
    fi

    mkdir -p "$(dirname "$destination")"

    if [[ -e "$destination" || -L "$destination" ]]; then

        backup_file "$destination"

        record_modified "$destination"

    else

        record_created "$destination"

    fi

    install \
        -m "$mode" \
        "$source" \
        "$destination"

    success "$destination"
}

copy_directory_contents() {

    local source="$1"
    local destination="$2"

    if [[ ! -d "$source" ]]; then

        warning "Directorio no encontrado: $source"

        return 1
    fi

    mkdir -p "$destination"

    shopt -s dotglob nullglob

    local item
    local name
    local target

    for item in "$source"/*; do

        name="$(basename "$item")"

        target="$destination/$name"

        if [[ -e "$target" || -L "$target" ]]; then

            backup_file "$target"

            record_modified "$target"

        else

            record_created "$target"

        fi

        cp -a "$item" "$target"

    done

    shopt -u dotglob nullglob

    chown \
        -R \
        "$TARGET_USER:$TARGET_USER" \
        "$destination" \
        2>/dev/null || true
}

find_example_file() {

    local filename="$1"
    shift

    local path

    for path in "$@"; do

        if [[ -f "$path" ]]; then

            echo "$path"

            return 0

        fi

    done

    local found

    found="$(
        find /usr/share/doc \
            -type f \
            -name "$filename" \
            -print \
            2>/dev/null |
        head -n1
    )"

    if [[ -n "$found" ]]; then

        echo "$found"

        return 0

    fi

    return 1
}

install_bspwm_dependency_config() {

    local destination="$TARGET_HOME/.config/bspwm/bspwmrc"

    mkdir -p \
        "$TARGET_HOME/.config/bspwm"

    BSPWMRC="$(
        find_example_file \
            "bspwmrc" \
            "/usr/share/doc/bspwm/examples/bspwmrc" \
            "/usr/share/doc/bspwm/examples/bspwmrc.gz"
    )" || true

    if [[ -n "$BSPWMRC" ]]; then

        if [[ "$BSPWMRC" == *.gz ]]; then

            if [[ -e "$destination" ]]; then
                backup_file "$destination"
                record_modified "$destination"
            else
                record_created "$destination"
            fi

            gzip -cd "$BSPWMRC" > "$destination"

            chmod 755 "$destination"

        else

            copy_file_safe \
                "$BSPWMRC" \
                "$destination" \
                0755

        fi

        chown \
            "$TARGET_USER:$TARGET_USER" \
            "$destination"

        success "Configuración base de bspwm instalada."

    else

        if [[ ! -e "$destination" ]]; then

            record_created "$destination"

            cat > "$destination" <<'EOF'
#!/usr/bin/env sh

sxhkd &
EOF

            chmod 755 "$destination"

            chown \
                "$TARGET_USER:$TARGET_USER" \
                "$destination"

            success "Se creó un bspwmrc básico."

        fi
    fi
}

install_sxhkd_dependency_config() {

    local destination="$TARGET_HOME/.config/sxhkd/sxhkdrc"

    mkdir -p \
        "$TARGET_HOME/.config/sxhkd"

    SXHKDRC="$(
        find_example_file \
            "sxhkdrc" \
            "/usr/share/doc/sxhkd/examples/sxhkdrc" \
            "/usr/share/doc/sxhkd/examples/sxhkdrc.gz"
    )" || true

    if [[ -n "$SXHKDRC" ]]; then

        if [[ "$SXHKDRC" == *.gz ]]; then

            if [[ -e "$destination" ]]; then
                backup_file "$destination"
                record_modified "$destination"
            else
                record_created "$destination"
            fi

            gzip -cd "$SXHKDRC" > "$destination"

            chmod 644 "$destination"

        else

            copy_file_safe \
                "$SXHKDRC" \
                "$destination" \
                0644

        fi

        chown \
            "$TARGET_USER:$TARGET_USER" \
            "$destination"

        success "Configuración base de sxhkd instalada."

    else

        if [[ ! -e "$destination" ]]; then

            record_created "$destination"

            cat > "$destination" <<'EOF'
# Themes Retro - sxhkd

super + Return
    xterm

super + d
    rofi -show drun

super + shift + q
    bspc node -c

super + alt + q
    bspc quit
EOF

            chmod 644 "$destination"

            chown \
                "$TARGET_USER:$TARGET_USER" \
                "$destination"

            success "Se creó un sxhkdrc básico."

        fi
    fi
}

install_polybar_dependency_config() {

    local destination="$TARGET_HOME/.config/polybar/config.ini"

    mkdir -p \
        "$TARGET_HOME/.config/polybar"

    POLYBAR_CONFIG="$(
        find_example_file \
            "config.ini" \
            "/usr/share/doc/polybar/examples/config.ini" \
            "/usr/share/doc/polybar/examples/config.ini.gz"
    )" || true

    if [[ -n "$POLYBAR_CONFIG" ]]; then

        if [[ "$POLYBAR_CONFIG" == *.gz ]]; then

            if [[ -e "$destination" ]]; then
                backup_file "$destination"
                record_modified "$destination"
            else
                record_created "$destination"
            fi

            gzip -cd "$POLYBAR_CONFIG" > "$destination"

            chmod 644 "$destination"

        else

            copy_file_safe \
                "$POLYBAR_CONFIG" \
                "$destination" \
                0644

        fi

        chown \
            "$TARGET_USER:$TARGET_USER" \
            "$destination"

        success "Configuración base de Polybar instalada."

    else

        if [[ ! -e "$destination" ]]; then

            record_created "$destination"

            cat > "$destination" <<'EOF'
[bar/main]
width = 100%
height = 24
bottom = false

background = #00000000
foreground = #FFFFFF

modules-left = xworkspaces
modules-right = date

[module/xworkspaces]
type = internal/xworkspaces

[module/date]
type = internal/date
date = %Y-%m-%d
time = %H:%M:%S
label = %date% %time%

[settings]
screenchange-reload = true
pseudo-transparency = true
EOF

            chmod 644 "$destination"

            chown \
                "$TARGET_USER:$TARGET_USER" \
                "$destination"

            success "Se creó un config.ini básico de Polybar."

        fi
    fi
}

install_xinitrc() {

    local destination="$TARGET_HOME/.xinitrc"

    if [[ -e "$destination" ]]; then

        backup_file "$destination"

        record_modified "$destination"

    else

        record_created "$destination"

    fi

    cat > "$destination" <<'EOF'
#!/usr/bin/env sh

if command -v xrdb >/dev/null 2>&1; then
    if [ -f "$HOME/.Xresources" ]; then
        xrdb -merge "$HOME/.Xresources"
    fi
fi

if command -v sxhkd >/dev/null 2>&1; then
    pgrep -x sxhkd >/dev/null 2>&1 || sxhkd &
fi

if command -v polybar >/dev/null 2>&1; then
    if [ -x "$HOME/.config/polybar/launch.sh" ]; then
        "$HOME/.config/polybar/launch.sh" &
    fi
fi

exec bspwm
EOF

    chmod 700 "$destination"

    chown \
        "$TARGET_USER:$TARGET_USER" \
        "$destination"

    success "Creado $destination"
}

install_dependency_configs() {

    info "Creando configuraciones base..."

    install_bspwm_dependency_config

    install_sxhkd_dependency_config

    install_polybar_dependency_config

    install_xinitrc

    mkdir -p \
        "$TARGET_HOME/.config/bspwm" \
        "$TARGET_HOME/.config/sxhkd" \
        "$TARGET_HOME/.config/polybar"

    chown \
        -R \
        "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.config" \
        2>/dev/null || true

    success "Configuraciones base creadas."
}

install_dependencies() {

    local selected=("$@")
    local packages=()
    local p
    local text=""

    for p in "${selected[@]}"; do

        [[ -n "$p" ]] || continue

        if ! pkg_installed "$p"; then

            packages+=("$p")

        fi

    done

    if ((${#packages[@]} == 0)); then

        tui_msg \
            "Todas las dependencias seleccionadas ya están instaladas."

        return
    fi

    for p in "${packages[@]}"; do

        text+="• ${DEP_LABEL[$p]}\n"
    done

    if ! tui_yesno \
        "Se instalarán las siguientes dependencias:\n\n$text\n¿Continuar?"
    then

        return

    fi

    ensure_apt || return

    for p in "${packages[@]}"; do

        info "Instalando ${DEP_LABEL[$p]}..."

        if apt-get install \
            -y \
            "$p" \
            >> "$LOG_FILE" 2>&1
        then

            success "${DEP_LABEL[$p]} instalado."

            grep -Fxq \
                "$p" \
                "$STATE_ROOT/installed_packages" ||
                echo "$p" >> "$STATE_ROOT/installed_packages"

        else

            error_msg \
                "No se pudo instalar ${DEP_LABEL[$p]}."

        fi

    done

    install_dependency_configs

    tui_msg \
        "Instalación terminada.\n\nLas configuraciones base fueron colocadas en:\n\n$TARGET_HOME/.config/bspwm/\n$TARGET_HOME/.config/sxhkd/\n$TARGET_HOME/.config/polybar/\n$TARGET_HOME/.xinitrc"
}

dependencies_menu() {

    while true; do

        draw_header

        local choices=()
        local p
        local status
        local result

        for p in "${DEP_LIST[@]}"; do

            status="OFF"

            if pkg_installed "$p"; then
                status="ON"
            fi

            choices+=(
                "$p"
                "${DEP_LABEL[$p]}"
                "$status"
            )

        done

        result="$(
            whiptail \
                --title "Instalar dependencias" \
                --checklist \
                "Selecciona las dependencias que deseas instalar." \
                24 \
                82 \
                12 \
                "${choices[@]}" \
                3>&1 \
                1>&2 \
                2>&3
        )" || return

        result="${result//\"/}"

        # shellcheck disable=SC2086
        install_dependencies $result

        if ! tui_yesno \
            "¿Quieres volver al menú de dependencias?"
        then

            return

        fi

    done
}

theme_paths() {

    case "$1" in

        vt330)

            THEME_ID="vt330"
            THEME_NAME="DEC VT330 Basic"

            BSPWM_THEME="$REPO_DIR/bspwm/theme_DEV_VT330_basic"

            POLYBAR_THEME="$REPO_DIR/polybar/theme_DEV_VT330_basic_polybar"

            STARTUP_THEME="$REPO_DIR/system_startup/theme_DEC_VT330_basic_startup"

            SYSTEM_THEME="$REPO_DIR/system/theme_DEC_VT330_basic"

            ;;

        gridcase)

            THEME_ID="gridcase"
            THEME_NAME="GRIDcase 1520 Basic"

            BSPWM_THEME="$REPO_DIR/bspwm/theme_GRIDcase_1520_basic"

            POLYBAR_THEME="$REPO_DIR/polybar/theme_GRIDcase_1520_basic_polybar"

            STARTUP_THEME="$REPO_DIR/system_startup/theme_GRIDcase_1520__basic_startup"

            SYSTEM_THEME="$REPO_DIR/system/theme_GRIDcase_1520_basic"

            ;;

        *)

            return 1

            ;;

    esac
}

update_repository() {

    printf '\n%b══════════════════════════════════════════════════════%b\n' \
        "$C_ORANGE" \
        "$C_RESET"

    printf '%b Actualizando Themes-Retro desde GitHub%b\n' \
        "$C_ORANGE" \
        "$C_RESET"

    printf '%b══════════════════════════════════════════════════════%b\n\n' \
        "$C_ORANGE" \
        "$C_RESET"

    if [[ -d "$REPO_DIR/.git" ]]; then

        run_visible \
            git \
            -C "$REPO_DIR" \
            fetch \
            origin \
            main || return 1

        run_visible \
            git \
            -C "$REPO_DIR" \
            reset \
            --hard \
            origin/main || return 1

    else

        if [[ -d "$REPO_DIR" ]]; then
            run_visible rm -rf "$REPO_DIR" || return 1
        fi

        run_visible \
            git \
            clone \
            --depth=1 \
            "$REPO_URL" \
            "$REPO_DIR" || return 1
    fi

    success "Repositorio actualizado."

    return 0
}

theme_dependencies_ready() {

    local missing=()
    local p
    local text=""

    for p in "${DEP_LIST[@]}"; do

        if ! pkg_installed "$p"; then

            missing+=("$p")

        fi

    done

    if ((${#missing[@]} == 0)); then

        return 0

    fi

    for p in "${missing[@]}"; do

        text+="• ${DEP_LABEL[$p]}\n"

    done

    if tui_yesno \
        "El tema necesita estas dependencias:\n\n$text\n\nNo están instaladas.\n\n¿Quieres instalarlas?"
    then

        install_dependencies \
            "${missing[@]}"

    else

        if ! tui_yesno \
            "Las dependencias siguen faltando.\n\n¿Quieres instalar el tema de todas formas?"
        then

            return 1

        fi

    fi

    return 0
}

install_theme_bspwm() {

    local destination="$TARGET_HOME/.config/bspwm"

    if [[ ! -d "$BSPWM_THEME" ]]; then

        error_msg \
            "No existe la carpeta bspwm del tema."

        return 1
    fi

    mkdir -p "$destination"

    info "Instalando configuración bspwm..."

    copy_directory_contents \
        "$BSPWM_THEME" \
        "$destination"

    if [[ -f "$destination/bspwm" &&
          ! -f "$destination/bspwmrc" ]]
    then

        mv \
            "$destination/bspwm" \
            "$destination/bspwmrc"

    fi

    if [[ -f "$destination/bspwmrc" ]]; then

        chmod 755 \
            "$destination/bspwmrc"

        sed -i \
            "s#/home/[^/]*/.config/polybar/config.ini#$TARGET_HOME/.config/polybar/config.ini#g" \
            "$destination/bspwmrc"

        chown \
            "$TARGET_USER:$TARGET_USER" \
            "$destination/bspwmrc"

        success \
            "bspwmrc del tema instalado."

    fi
}

install_theme_polybar() {

    local destination="$TARGET_HOME/.config/polybar"

    if [[ ! -d "$POLYBAR_THEME" ]]; then

        error_msg \
            "No existe la carpeta Polybar del tema."

        return 1
    fi

    mkdir -p "$destination"

    info "Instalando configuración Polybar..."

    copy_directory_contents \
        "$POLYBAR_THEME" \
        "$destination"

    if [[ -f "$destination/config.ini" ]]; then

        chmod 644 \
            "$destination/config.ini"

        chown \
            "$TARGET_USER:$TARGET_USER" \
            "$destination/config.ini"

        success \
            "config.ini del tema instalado."

    fi

    create_polybar_launcher
}

create_polybar_launcher() {

    local launcher="$TARGET_HOME/.config/polybar/launch.sh"

    if [[ -e "$launcher" ]]; then

        backup_file "$launcher"

        record_modified "$launcher"

    else

        record_created "$launcher"

    fi

    cat > "$launcher" <<'EOF'
#!/usr/bin/env sh

CONFIG="$HOME/.config/polybar/config.ini"

if ! command -v polybar >/dev/null 2>&1; then
    exit 0
fi

if [ ! -f "$CONFIG" ]; then
    exit 0
fi

NETWORK_INTERFACE="$(
    ip route 2>/dev/null |
    awk '$1 == "default" {print $5; exit}'
)"

export NETWORK_INTERFACE="${NETWORK_INTERFACE:-eth0}"

pkill -x polybar 2>/dev/null || true

sleep 0.2

polybar \
    --config="$CONFIG" \
    main &
EOF

    chmod 755 "$launcher"

    chown \
        "$TARGET_USER:$TARGET_USER" \
        "$launcher"
}

install_theme_startup() {

    local source="$STARTUP_THEME"
    local destination="/usr/share/plymouth/themes"
    local plymouth_theme_dir=""
    local plymouth_file=""

    printf '\n%b══════════════════════════════════════════════════════%b\n' \
        "$C_ORANGE" \
        "$C_RESET"

    printf '%b Instalación del tema de arranque Plymouth%b\n' \
        "$C_ORANGE" \
        "$C_RESET"

    printf '%b══════════════════════════════════════════════════════%b\n\n' \
        "$C_ORANGE" \
        "$C_RESET"

    if [[ ! -d "$source" ]]; then

        error_msg \
            "No existe el tema Plymouth:"

        echo
        echo "$source"

        return 1
    fi

    mkdir -p "$destination"

    printf '%b[PROC]%b Buscando carpeta Plymouth...\n' \
        "$C_ORANGE" \
        "$C_RESET"

    plymouth_theme_dir="$(
        find "$source" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print \
            -quit
    )"

    if [[ -z "$plymouth_theme_dir" ]]; then

        error_msg \
            "No se encontró ninguna carpeta dentro de system_startup."

        return 1
    fi

    local theme_folder_name

    theme_folder_name="$(
        basename "$plymouth_theme_dir"
    )"

    local final_destination

    final_destination="$destination/$theme_folder_name"

    echo
    echo "Origen:"
    echo "  $plymouth_theme_dir"
    echo
    echo "Destino:"
    echo "  $final_destination"
    echo

    if [[ -e "$final_destination" ]]; then

        warning \
            "Ya existe una instalación anterior."

        if ! tui_yesno \
            "El tema Plymouth ya existe en:\n\n$final_destination\n\n¿Quieres reemplazarlo?"
        then

            return 1
        fi

        backup_file "$final_destination"

        run_visible \
            rm \
            -rf \
            "$final_destination" || return 1
    fi

    printf '\n%b[PROC]%b Copiando archivos Plymouth...\n\n' \
        "$C_ORANGE" \
        "$C_RESET"

    run_visible \
        cp \
        -a \
        "$plymouth_theme_dir" \
        "$destination/" || return 1

    chown \
        -R \
        root:root \
        "$final_destination"

    chmod \
        -R \
        a+rX \
        "$final_destination"

    printf '\n%b[ OK ]%b Tema copiado correctamente.\n' \
        "$C_GREEN" \
        "$C_RESET"

    plymouth_file="$(
        find "$final_destination" \
            -maxdepth 1 \
            -type f \
            -name '*.plymouth' \
            -print \
            -quit
    )"

    if [[ -z "$plymouth_file" ]]; then

        error_msg \
            "No se encontró ningún archivo .plymouth."

        return 1
    fi

    printf '\n%b[PROC]%b Archivo Plymouth detectado:%b\n' \
        "$C_ORANGE" \
        "$C_RESET" \
        "$C_WHITE"

    echo "  $plymouth_file"

    printf '\n%b[PROC]%b Registrando Plymouth mediante update-alternatives...%b\n\n' \
        "$C_ORANGE" \
        "$C_RESET" \
        "$C_WHITE"

    run_visible \
        update-alternatives \
        --install \
        /usr/share/plymouth/themes/default.plymouth \
        default.plymouth \
        "$plymouth_file" \
        100 || return 1

    printf '\n%b[PROC]%b Seleccionando el tema Plymouth...%b\n\n' \
        "$C_ORANGE" \
        "$C_RESET" \
        "$C_WHITE"

    run_visible \
        update-alternatives \
        --set \
        default.plymouth \
        "$plymouth_file" || return 1

    printf '\n%b[PROC]%b Actualizando initramfs...%b\n\n' \
        "$C_ORANGE" \
        "$C_RESET" \
        "$C_WHITE"

    run_visible \
        update-initramfs \
        -u || return 1

    printf '\n%b[PROC]%b Actualizando GRUB...%b\n\n' \
        "$C_ORANGE" \
        "$C_RESET" \
        "$C_WHITE"

    run_visible \
        update-grub || return 1

    echo
    printf '%b══════════════════════════════════════════════════════%b\n' \
        "$C_GREEN" \
        "$C_RESET"

    printf '%b[ OK ] Plymouth instalado y configurado.%b\n' \
        "$C_GREEN" \
        "$C_RESET"

    printf '%b══════════════════════════════════════════════════════%b\n' \
        "$C_GREEN" \
        "$C_RESET"

    echo
    echo "Tema:"
    echo "  $theme_folder_name"
    echo
    echo "Archivo:"
    echo "  $plymouth_file"
    echo
}

install_theme_xresources() {

    local source=""

    if [[ -d "$SYSTEM_THEME" ]]; then

        source="$(
            find \
                "$SYSTEM_THEME" \
                -type f \
                -name '.Xresources' \
                -print \
                -quit \
                2>/dev/null ||
                true
        )"

    fi

    if [[ -z "$source" ]]; then

        warning \
            "No se encontró .Xresources para $THEME_NAME."

        return 0
    fi

    info "Instalando .Xresources..."

    copy_file_safe \
        "$source" \
        "$TARGET_HOME/.Xresources" \
        0644

    chown \
        "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.Xresources"

    success \
        "$TARGET_HOME/.Xresources instalado."
}

install_theme() {

    local id="$1"

    theme_paths "$id" ||
        return 1

    if ! theme_dependencies_ready; then

        return

    fi

    if ! tui_yesno \
        "Tema seleccionado:\n\n$THEME_NAME\n\nSe instalarán sus configuraciones de:\n\n• bspwm\n• polybar\n• Plymouth/startup\n• .Xresources\n\n¿Continuar?"
    then

        return

    fi

    update_repository ||
        return

    theme_paths "$id"

    if [[ ! -d "$BSPWM_THEME" ]]; then

        tui_msg \
            "No se encontró:\n\n$BSPWM_THEME"

        return
    fi

    install_theme_bspwm

    install_theme_polybar

    install_theme_startup || return 1

    install_theme_xresources

    install_xinitrc

    echo "$THEME_NAME" \
        > "$STATE_ROOT/current_theme"

    echo "$THEME_ID" \
        > "$STATE_ROOT/theme_id"

    grep -Fxq \
        "$THEME_ID" \
        "$STATE_ROOT/installed_themes" ||
        echo "$THEME_ID" \
            >> "$STATE_ROOT/installed_themes"

    chown \
        "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.xinitrc" \
        "$TARGET_HOME/.Xresources" \
        2>/dev/null || true

    tui_msg \
        "Tema instalado correctamente.\n\n$THEME_NAME\n\nArchivos instalados:\n\n~/.config/bspwm/\n~/.config/sxhkd/\n~/.config/polybar/\n~/.xinitrc\n~/.Xresources\n\n/usr/share/plymouth/themes/$THEME_ID/"

    if tui_yesno \
        "La instalación terminó.\n\n¿Quieres reiniciar ahora?"
    then

        clear_screen

        reboot

    fi
}

theme_menu() {

    while true; do

        draw_header

        local choice

        choice="$(
            whiptail \
                --title "Instalar temas" \
                --menu \
                "Selecciona el tema que quieres instalar." \
                16 \
                78 \
                4 \
                "1" "DEC VT330 Basic" \
                "2" "GRIDcase 1520 Basic" \
                "3" "Volver" \
                3>&1 \
                1>&2 \
                2>&3
        )" || return

        case "$choice" in

            1)
                install_theme vt330
                ;;

            2)
                install_theme gridcase
                ;;

            3)
                return
                ;;

        esac

    done
}

versions_menu() {

    while true; do

        draw_header

        local choice
        local commit="No disponible"

        choice="$(
            whiptail \
                --title "Versiones" \
                --menu \
                "Información de Themes Retro." \
                18 \
                78 \
                5 \
                "1" "Temas disponibles" \
                "2" "Versión del instalador" \
                "3" "Versión actual de Git" \
                "4" "Actualizar información desde Git" \
                "5" "Volver" \
                3>&1 \
                1>&2 \
                2>&3
        )" || return

        case "$choice" in

            1)

                tui_msg \
                    "TEMAS DISPONIBLES\n\nDEC VT330 Basic\nGRIDcase 1520 Basic"

                ;;

            2)

                tui_msg \
                    "Themes Retro\n\nInstaller version:\n$APP_VERSION"

                ;;

            3)

                if [[ -d "$REPO_DIR/.git" ]]; then

                    commit="$(
                        git \
                            -C "$REPO_DIR" \
                            rev-parse \
                            --short \
                            HEAD \
                            2>/dev/null ||
                            echo "No disponible"
                    )"

                fi

                tui_msg \
                    "Commit actual:\n\n$commit"

                ;;

            4)

                update_repository ||
                    true

                if [[ -d "$REPO_DIR/.git" ]]; then

                    commit="$(
                        git \
                            -C "$REPO_DIR" \
                            rev-parse \
                            --short \
                            HEAD \
                            2>/dev/null ||
                            echo "No disponible"
                    )"

                fi

                tui_msg \
                    "Repositorio actualizado.\n\nCommit:\n$commit"

                ;;

            5)

                return

                ;;

        esac

    done
}

restore_backups() {

    [[ -f "$STATE_ROOT/backups" ]] ||
        return

    local original
    local backup

    while IFS='|' read -r original backup; do

        [[ -n "$original" ]] ||
            continue

        [[ -e "$backup" ]] ||
            continue

        rm -rf "$original"

        mkdir -p \
            "$(dirname "$original")"

        cp -a \
            "$backup" \
            "$original"

        chown \
            -R \
            "$TARGET_USER:$TARGET_USER" \
            "$original" \
            2>/dev/null ||
            true

    done < "$STATE_ROOT/backups"
}

remove_plymouth_theme() {

    local theme_id=""

    if [[ -f "$STATE_ROOT/theme_id" ]]; then
        theme_id="$(cat "$STATE_ROOT/theme_id")"
    fi

    if [[ -z "$theme_id" ]]; then
        warning "No hay un tema Plymouth registrado."
        return 0
    fi

    local plymouth_path=""

    case "$theme_id" in

        vt330|gridcase)

            plymouth_path="$(
                find \
                    /usr/share/plymouth/themes \
                    -mindepth 2 \
                    -maxdepth 2 \
                    -type f \
                    -name '*.plymouth' \
                    -print \
                    2>/dev/null |
                while read -r file; do

                    if grep -q \
                        "ModuleName" \
                        "$file" 2>/dev/null
                    then
                        echo "$file"
                        break
                    fi

                done
            )"

            ;;

    esac

    if [[ -n "$plymouth_path" ]]; then

        printf '\n%b[PROC]%b Eliminando Plymouth de update-alternatives...\n\n' \
            "$C_ORANGE" \
            "$C_RESET"

        run_visible \
            update-alternatives \
            --remove \
            default.plymouth \
            "$plymouth_path" || true

    fi

    # El nombre real de la carpeta del repositorio actualmente es
    # amber-system-startup.
    if [[ -d "/usr/share/plymouth/themes/amber-system-startup" ]]; then

        printf '\n%b[PROC]%b Eliminando archivos del tema Plymouth...\n\n' \
            "$C_ORANGE" \
            "$C_RESET"

        run_visible \
            rm \
            -rf \
            "/usr/share/plymouth/themes/amber-system-startup"
    fi

    printf '\n%b[PROC]%b Actualizando initramfs después de la eliminación...\n\n' \
        "$C_ORANGE" \
        "$C_RESET"

    run_visible \
        update-initramfs \
        -u || true

    printf '\n%b[PROC]%b Actualizando GRUB después de la eliminación...\n\n' \
        "$C_ORANGE" \
        "$C_RESET"

    run_visible \
        update-grub || true
}

remove_theme_configuration() {

    local path

    if [[ -f "$STATE_ROOT/created_files" ]]; then

        while IFS= read -r path; do

            [[ -n "$path" ]] || \
                continue

            rm -rf "$path"

        done < "$STATE_ROOT/created_files"

    fi

    restore_backups

    rm -rf \
        "$TARGET_HOME/.config/bspwm" \
        "$TARGET_HOME/.config/sxhkd" \
        "$TARGET_HOME/.config/polybar"

    rm -f \
        "$TARGET_HOME/.xinitrc"

    remove_plymouth_theme

    rm -f \
        "$STATE_ROOT/current_theme" \
        "$STATE_ROOT/theme_id"

    : > "$STATE_ROOT/backups"
    : > "$STATE_ROOT/created_files"
    : > "$STATE_ROOT/modified_files"
    : > "$STATE_ROOT/installed_themes"
}

uninstall_theme_only() {

    if ! tui_yesno \
        "Se eliminará la configuración de Themes Retro y se restaurarán los backups disponibles.\n\n¿Continuar?"
    then

        return

    fi

    remove_theme_configuration

    tui_msg \
        "Configuración de los temas eliminada."
}

uninstall_dependencies_only() {

    local packages=()
    local p
    local text=""

    if [[ ! -s "$STATE_ROOT/installed_packages" ]]; then

        tui_msg \
            "No hay dependencias registradas como instaladas por Themes Retro."

        return
    fi

    while IFS= read -r p; do

        if [[ -n "$p" ]] &&
           pkg_installed "$p"
        then

            packages+=("$p")

        fi

    done < "$STATE_ROOT/installed_packages"

    if ((${#packages[@]} == 0)); then

        tui_msg \
            "No hay dependencias que desinstalar."

        return
    fi

    for p in "${packages[@]}"; do

        text+="• ${DEP_LABEL[$p]:-$p}\n"

    done

    if ! tui_yesno \
        "Se eliminarán únicamente los paquetes que Themes Retro registró como instalados.\n\n$text\n¿Continuar?"
    then

        return

    fi

    for p in "${packages[@]}"; do

        info "Eliminando ${DEP_LABEL[$p]:-$p}..."

        apt-get remove \
            -y \
            "$p" \
            >> "$LOG_FILE" 2>&1 ||
            warning "No se pudo eliminar $p."

    done

    apt-get autoremove \
        -y \
        >> "$LOG_FILE" 2>&1 ||
        true

    : > "$STATE_ROOT/installed_packages"

    tui_msg \
        "Dependencias eliminadas."
}

uninstall_everything() {

    if ! tui_yesno \
        "ATENCIÓN\n\nEsto eliminará la configuración, los temas y las dependencias instaladas por Themes Retro.\n\n¿Estás completamente seguro?"
    then

        return

    fi

    remove_theme_configuration

    uninstall_dependencies_only

    rm -rf \
        "$INSTALL_ROOT" \
        "$STATE_ROOT"

    tui_msg \
        "Themes Retro ha sido eliminado completamente."
}

uninstall_menu() {

    while true; do

        draw_header

        local choice

        choice="$(
            whiptail \
                --title "Desinstalar" \
                --menu \
                "Selecciona qué deseas eliminar." \
                18 \
                82 \
                5 \
                "1" "Solo configuración de los temas" \
                "2" "Solo dependencias" \
                "3" "Todo en general" \
                "4" "Volver" \
                3>&1 \
                1>&2 \
                2>&3
        )" || return

        case "$choice" in

            1)
                uninstall_theme_only
                ;;

            2)
                uninstall_dependencies_only
                ;;

            3)
                uninstall_everything
                return
                ;;

            4)
                return
                ;;

        esac

    done
}

restart_menu() {

    if ! tui_yesno \
        "¿Estás seguro de que quieres reiniciar el sistema?"
    then

        return

    fi

    clear_screen

    echo
    echo "Reiniciando en 3 segundos..."
    echo

    sleep 3

    reboot
}

main_menu() {

    while true; do

        draw_header

        local choice

        choice="$(
            whiptail \
                --title "Menú principal" \
                --menu \
                "Selecciona una opción." \
                18 \
                82 \
                6 \
                "1" "Instalar dependencias" \
                "2" "Instalar temas" \
                "3" "Versiones" \
                "4" "Reiniciar" \
                "5" "Desinstalar" \
                "6" "Salir" \
                3>&1 \
                1>&2 \
                2>&3
        )" || exit 0

        case "$choice" in

            1)
                dependencies_menu
                ;;

            2)
                theme_menu
                ;;

            3)
                versions_menu
                ;;

            4)
                restart_menu
                ;;

            5)
                uninstall_menu
                ;;

            6)
                clear_screen
                exit 0
                ;;

        esac

    done
}

main() {

    require_root "$@"

    check_ubuntu

    detect_user

    prepare_directories

    ensure_whiptail || {

        error_msg \
            "No se pudo instalar whiptail."

        exit 1
    }

    main_menu
}

main "$@"