#!/usr/bin/env bash

set -u
set -o pipefail

APP_NAME="Themes Retro"
APP_VERSION="2.1.0"

REPO_URL="https://github.com/FossGPT/Themes-Retro.git"

INSTALL_ROOT="/opt/themes-retro"
STATE_ROOT="/var/lib/themes-retro"
BACKUP_ROOT="/var/backups/themes-retro"
LOG_FILE="/var/log/themes-retro.log"

C_RESET="\033[0m"
C_ORANGE="\033[38;5;208m"
C_GREEN="\033[38;5;82m"
C_RED="\033[38;5;196m"
C_CYAN="\033[38;5;51m"
C_AMBER="\033[38;5;214m"
C_WHITE="\033[1;37m"

TARGET_USER=""
TARGET_HOME=""

declare -A DEP_LABEL=(
    [git]="Git"
    [xorg]="Xorg"
    [xinit]="xinit / startx"
    [x11-xserver-utils]="X11 utilities / xrdb"
    [bspwm]="bspwm"
    [sxhkd]="sxhkd"
    [polybar]="Polybar"
    [rofi]="Rofi"
    [ranger]="Ranger"
    [htop]="htop"
    [xterm]="XTerm"
)

DEP_LIST=(
    git
    xorg
    xinit
    x11-xserver-utils
    bspwm
    sxhkd
    polybar
    rofi
    ranger
    htop
    xterm
)

log_msg() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

msg() {
    printf '%b%s%b\n' "$C_CYAN" "$1" "$C_RESET"
}

ok() {
    printf '%b[ OK ]%b %s\n' "$C_GREEN" "$C_RESET" "$1"
}

warn() {
    printf '%b[WARN]%b %s\n' "$C_AMBER" "$C_RESET" "$1"
}

err() {
    printf '%b[ERROR]%b %s\n' "$C_RED" "$C_RESET" "$1"
}

require_root() {

    if [[ $EUID -ne 0 ]]; then
        exec sudo -E bash "$0" "$@"
    fi
}

detect_user() {

    local candidate=""

    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        candidate="$SUDO_USER"

    elif [[ -n "${USER:-}" && "$USER" != "root" ]]; then
        candidate="$USER"

    else
        candidate="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)"
    fi

    if [[ -z "$candidate" ]] || ! id "$candidate" >/dev/null 2>&1; then
        err "No se pudo determinar el usuario gráfico."
        exit 1
    fi

    TARGET_USER="$candidate"

    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

    if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
        err "No existe HOME para $TARGET_USER."
        exit 1
    fi
}

prepare_state() {

    mkdir -p "$STATE_ROOT"
    mkdir -p "$BACKUP_ROOT"
    mkdir -p "$INSTALL_ROOT"

    touch "$LOG_FILE"

    touch "$STATE_ROOT/installed_packages"
    touch "$STATE_ROOT/backups"
    touch "$STATE_ROOT/created_files"
    touch "$STATE_ROOT/modified_files"
    touch "$STATE_ROOT/installed_themes"
}

pkg_installed() {

    dpkg-query \
        -W \
        -f='${Status}' \
        "$1" 2>/dev/null |
        grep -q '^install ok installed$'
}

ensure_apt_updated() {

    if [[ ! -f "$STATE_ROOT/apt_updated" ]] ||
       find "$STATE_ROOT/apt_updated" -mmin +60 -print -quit 2>/dev/null | grep -q .
    then

        msg "Actualizando índices de APT..."

        if apt-get update >> "$LOG_FILE" 2>&1; then

            touch "$STATE_ROOT/apt_updated"

            ok "APT actualizado."

        else

            err "No se pudo actualizar APT."

            echo
            echo "Revisa:"
            echo "$LOG_FILE"

            return 1
        fi
    fi
}

backup_path() {

    local path="$1"
    local rel
    local dest

    [[ -e "$path" || -L "$path" ]] || return 0

    if [[ "$path" == "$TARGET_HOME/"* ]]; then

        rel="home/${TARGET_USER}/${path#"$TARGET_HOME/"}"

    elif [[ "$path" == /etc/* ]]; then

        rel="etc/${path#/etc/}"

    else

        rel="other/${path#/}"

    fi

    dest="$BACKUP_ROOT/$rel"

    mkdir -p "$(dirname "$dest")"

    rm -rf "$dest"

    cp -a "$path" "$dest"

    printf '%s|%s\n' \
        "$path" \
        "$dest" >> "$STATE_ROOT/backups"
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

safe_install_file() {

    local source="$1"
    local dest="$2"
    local mode="${3:-0644}"

    if [[ ! -f "$source" ]]; then

        warn "No existe: $source"

        return 1
    fi

    mkdir -p "$(dirname "$dest")"

    if [[ -e "$dest" || -L "$dest" ]]; then

        backup_path "$dest"

        record_modified "$dest"

    else

        record_created "$dest"

    fi

    install \
        -m "$mode" \
        "$source" \
        "$dest"
}

ensure_whiptail() {

    if command -v whiptail >/dev/null 2>&1; then
        return 0
    fi

    ensure_apt_updated || return 1

    msg "Instalando whiptail para la interfaz TUI..."

    apt-get install \
        -y \
        whiptail \
        >> "$LOG_FILE" 2>&1
}

tui_msgbox() {

    whiptail \
        --title "$APP_NAME" \
        --msgbox "$1" \
        12 \
        76
}

tui_yesno() {

    whiptail \
        --title "$APP_NAME" \
        --yesno "$1" \
        14 \
        76
}

pause_screen() {

    echo

    read -r \
        -p "Presiona ENTER para continuar..." _
}

current_theme() {

    if [[ -f "$STATE_ROOT/current_theme" ]]; then

        cat "$STATE_ROOT/current_theme"

    else

        echo "Ninguno"

    fi
}

draw_header() {

    clear

    printf '%b╔══════════════════════════════════════════════════════════════╗%b\n' \
        "$C_ORANGE" "$C_RESET"

    printf '%b║                       THEMES RETRO                          ║%b\n' \
        "$C_ORANGE" "$C_RESET"

    printf '%b║                    Installer v%-8s                    ║%b\n' \
        "$C_ORANGE" \
        "$APP_VERSION" \
        "$C_RESET"

    printf '%b╚══════════════════════════════════════════════════════════════╝%b\n\n' \
        "$C_ORANGE" "$C_RESET"

    printf ' Usuario: %b%s%b\n' \
        "$C_GREEN" \
        "$TARGET_USER" \
        "$C_RESET"

    printf ' Home:    %b%s%b\n' \
        "$C_GREEN" \
        "$TARGET_HOME" \
        "$C_RESET"

    printf ' Tema:    %b%s%b\n\n' \
        "$C_GREEN" \
        "$(current_theme)" \
        "$C_RESET"
}

install_selected_dependencies() {

    local selected=( "$@" )

    local packages=()
    local p
    local summary=""

    for p in "${selected[@]}"; do

        [[ -n "$p" ]] || continue

        if ! pkg_installed "$p"; then
            packages+=( "$p" )
        fi

    done

    if ((${#packages[@]} == 0)); then

        tui_msgbox \
            "No hay dependencias nuevas que instalar."

        return
    fi

    for p in "${packages[@]}"; do

        summary+="• ${DEP_LABEL[$p]}\n"

    done

    if ! tui_yesno \
        "Se instalarán:\n\n$summary\n¿Continuar?"
    then
        return
    fi

    ensure_apt_updated || return 1

    for p in "${packages[@]}"; do

        msg "Instalando ${DEP_LABEL[$p]}..."

        if apt-get install \
            -y \
            "$p" \
            >> "$LOG_FILE" 2>&1
        then

            ok "${DEP_LABEL[$p]} instalado."

            grep -Fxq \
                "$p" \
                "$STATE_ROOT/installed_packages" ||
                echo "$p" >> "$STATE_ROOT/installed_packages"

        else

            err "No se pudo instalar $p."

        fi

    done

    tui_msgbox \
        "Proceso terminado.\n\nLos paquetes que ya estaban instalados no fueron reinstalados."
}

dependencies_menu() {

    while true; do

        draw_header

        local choices=()
        local p
        local state
        local output

        for p in "${DEP_LIST[@]}"; do

            state="OFF"

            if pkg_installed "$p"; then
                state="ON"
            fi

            choices+=(
                "$p"
                "${DEP_LABEL[$p]}"
                "$state"
            )

        done

        output="$(
            whiptail \
                --title "Instalar dependencias" \
                --checklist \
                "Selecciona los componentes.\nLos ya instalados aparecen marcados." \
                24 \
                84 \
                12 \
                "${choices[@]}" \
                3>&1 \
                1>&2 \
                2>&3
        )" || return

        output="${output//\"/}"

        # shellcheck disable=SC2086
        install_selected_dependencies $output

        if ! tui_yesno \
            "¿Quieres volver a seleccionar dependencias?"
        then
            return
        fi

    done
}

dependency_status() {

    local text=""
    local p

    for p in "${DEP_LIST[@]}"; do

        if pkg_installed "$p"; then

            text+="[ INSTALADO ] ${DEP_LABEL[$p]}\n"

        else

            text+="[ FALTANTE  ] ${DEP_LABEL[$p]}\n"

        fi

    done

    tui_msgbox "$text"
}

clone_or_update_repo() {

    local repo="$INSTALL_ROOT/repository"
    local commit

    if [[ -d "$repo/.git" ]]; then

        msg "Actualizando Themes-Retro..."

        git \
            -C "$repo" \
            fetch \
            --quiet \
            origin \
            main \
            >> "$LOG_FILE" 2>&1 || true

        git \
            -C "$repo" \
            reset \
            --hard \
            origin/main \
            >> "$LOG_FILE" 2>&1 ||
        {
            err "No se pudo actualizar el repositorio."
            return 1
        }

    else

        msg "Descargando Themes-Retro..."

        rm -rf "$repo"

        git clone \
            --depth=1 \
            "$REPO_URL" \
            "$repo" \
            >> "$LOG_FILE" 2>&1 ||
        {
            err "No se pudo clonar el repositorio."
            return 1
        }

    fi

    commit="$(
        git \
            -C "$repo" \
            rev-parse \
            --short \
            HEAD \
            2>/dev/null ||
            echo unknown
    )"

    echo "$commit" > "$STATE_ROOT/repo_commit"

    ok "Repositorio listo. Commit: $commit"
}

theme_paths() {

    case "$1" in

        vt330)

            BSP_DIR="$INSTALL_ROOT/repository/bspwm/theme_DEV_VT330_basic"

            POLY_DIR="$INSTALL_ROOT/repository/polybar/theme_DEV_VT330_basic_polybar"

            THEME_NAME="DEC VT330 Basic"

            ;;

        gridcase)

            BSP_DIR="$INSTALL_ROOT/repository/bspwm/theme_GRIDcase_1520_basic"

            POLY_DIR="$INSTALL_ROOT/repository/polybar/theme_GRIDcase_1520_basic_polybar"

            THEME_NAME="GRIDcase 1520 Basic"

            ;;

        *)

            return 1

            ;;

    esac
}

missing_theme_dependencies() {

    local missing=()
    local p

    for p in "${DEP_LIST[@]}"; do

        if ! pkg_installed "$p"; then

            missing+=( "$p" )

        fi

    done

    printf '%s\n' "${missing[@]}"
}

all_theme_dependencies_present() {

    local p

    for p in "${DEP_LIST[@]}"; do

        if ! pkg_installed "$p"; then

            return 1

        fi

    done

    return 0
}

install_xinitrc() {

    local dest="$TARGET_HOME/.xinitrc"

    if [[ -e "$dest" ]]; then

        backup_path "$dest"

        record_modified "$dest"

    else

        record_created "$dest"

    fi

    cat > "$dest" <<'EOF'
#!/usr/bin/env sh

if command -v xrdb >/dev/null 2>&1 && [ -f "$HOME/.Xresources" ]; then
    xrdb -merge "$HOME/.Xresources"
fi

pgrep -x sxhkd >/dev/null 2>&1 || sxhkd &

exec bspwm
EOF

    chmod 700 "$dest"
}

install_xresources() {

    local source="$1"
    local dest="$TARGET_HOME/.Xresources"

    if [[ -f "$source" ]]; then

        safe_install_file \
            "$source" \
            "$dest"

    elif [[ ! -e "$dest" ]]; then

        record_created "$dest"

        printf '%s\n' \
            '! Themes Retro Xresources' \
            > "$dest"

    fi
}

install_bspwm_theme() {

    local source="$BSP_DIR/bspwm"
    local dest="$TARGET_HOME/.config/bspwm/bspwmrc"

    mkdir -p \
        "$TARGET_HOME/.config/bspwm"

    safe_install_file \
        "$source" \
        "$dest" \
        0755 ||
        return 1

    sed -i \
        's#/home/dec/.config/polybar/config.ini#$HOME/.config/polybar/config.ini#g' \
        "$dest"

    chmod 755 "$dest"
}

install_sxhkd_theme() {

    local source=""
    local dest="$TARGET_HOME/.config/sxhkd/sxhkdrc"

    mkdir -p \
        "$TARGET_HOME/.config/sxhkd"

    source="$(
        find \
            "$BSP_DIR" \
            -type f \
            -name 'sxhkdrc' \
            -print \
            -quit \
            2>/dev/null ||
            true
    )"

    if [[ -n "$source" ]]; then

        safe_install_file \
            "$source" \
            "$dest"

    elif [[ ! -f "$dest" ]]; then

        record_created "$dest"

        cat > "$dest" <<'EOF'
super + Return
    xterm

super + d
    rofi -show drun

super + shift + q
    bspc node -c

super + alt + q
    bspc quit
EOF

        warn \
            "El repositorio no contiene sxhkdrc; se creó una configuración base."

    fi

    chmod 644 "$dest"
}

install_polybar_theme() {

    local source="$POLY_DIR/config.ini"
    local dest="$TARGET_HOME/.config/polybar/config.ini"

    mkdir -p \
        "$TARGET_HOME/.config/polybar"

    safe_install_file \
        "$source" \
        "$dest" ||
        return 1

    sed -i \
        's/^interface = eth0$/interface = ${env:NETWORK_INTERFACE:eth0}/' \
        "$dest"

    local launch="$TARGET_HOME/.config/polybar/launch.sh"

    if [[ -e "$launch" ]]; then

        backup_path "$launch"

        record_modified "$launch"

    else

        record_created "$launch"

    fi

    cat > "$launch" <<'EOF'
#!/usr/bin/env sh

CONFIG="$HOME/.config/polybar/config.ini"

NETWORK_INTERFACE="$(
    ip route 2>/dev/null |
    awk '$1 == "default" {print $5; exit}'
)"

export NETWORK_INTERFACE="${NETWORK_INTERFACE:-eth0}"

pkill -x polybar 2>/dev/null || true

sleep 0.2

command -v polybar >/dev/null 2>&1 || exit 0

[ -f "$CONFIG" ] || exit 0

polybar \
    --config="$CONFIG" \
    main &
EOF

    chmod 755 "$launch"
}

install_theme_files() {

    local id="$1"

    theme_paths "$id" ||
        return 1

    clone_or_update_repo ||
        return 1

    if [[ ! -f "$BSP_DIR/bspwm" ]]; then

        err \
            "No se encontró la configuración bspwm del tema."

        return 1

    fi

    if [[ ! -f "$POLY_DIR/config.ini" ]]; then

        err \
            "No se encontró config.ini del tema."

        return 1

    fi

    msg "Instalando $THEME_NAME..."

    install_bspwm_theme

    install_sxhkd_theme

    install_polybar_theme

    install_xresources \
        "$BSP_DIR/.Xresources"

    install_xinitrc

    chown \
        -R \
        "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.config" \
        2>/dev/null ||
        true

    chown \
        "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.xinitrc" \
        "$TARGET_HOME/.Xresources" \
        2>/dev/null ||
        true

    echo "$id" \
        > "$STATE_ROOT/current_theme"

    grep -Fxq \
        "$id" \
        "$STATE_ROOT/installed_themes" ||
        echo "$id" \
            >> "$STATE_ROOT/installed_themes"

    ok "$THEME_NAME instalado."

    tui_msgbox \
        "$THEME_NAME instalado.\n\nSe crearon/configuraron:\n\n~/.config/bspwm/\n~/.config/sxhkd/\n~/.config/polybar/\n~/.xinitrc\n~/.Xresources"

    if tui_yesno \
        "¿Quieres reiniciar ahora?"
    then

        clear

        reboot

    fi
}

theme_install_flow() {

    local id="$1"

    local missing=()
    local p
    local text=""

    while IFS= read -r p; do

        [[ -n "$p" ]] &&
            missing+=( "$p" )

    done < <(missing_theme_dependencies)

    if ((${#missing[@]} > 0)); then

        text="Faltan dependencias:\n\n"

        for p in "${missing[@]}"; do

            text+="• ${DEP_LABEL[$p]}\n"

        done

        text+="\nEl tema puede no funcionar correctamente.\n¿Quieres instalar las faltantes ahora?"

        if tui_yesno "$text"; then

            install_selected_dependencies \
                "${missing[@]}"

        else

            tui_yesno \
                "No se instalarán dependencias.\n\n¿Quieres instalar el tema de todas formas?" ||
                return

        fi

        if ! all_theme_dependencies_present; then

            tui_yesno \
                "Aún faltan dependencias.\n\n¿Quieres instalar el tema de todas formas?" ||
                return

        fi
    fi

    theme_paths "$id" ||
        return

    if ! tui_yesno \
        "Tema seleccionado:\n\n$THEME_NAME\n\n¿Continuar?"
    then

        return

    fi

    install_theme_files "$id"

    pause_screen
}

theme_menu() {

    while true; do

        draw_header

        local choice

        choice="$(
            whiptail \
                --title "Instalar temas" \
                --menu \
                "Selecciona un tema" \
                16 \
                76 \
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
                theme_install_flow vt330
                ;;

            2)
                theme_install_flow gridcase
                ;;

            3)
                return
                ;;

        esac

    done
}

version_menu() {

    while true; do

        draw_header

        local choice

        choice="$(
            whiptail \
                --title "Versiones" \
                --menu \
                "Selecciona una opción" \
                18 \
                76 \
                4 \
                "1" "Temas disponibles" \
                "2" "Versión del instalador" \
                "3" "Revisar versión desde Git" \
                "4" "Volver" \
                3>&1 \
                1>&2 \
                2>&3
        )" || return

        case "$choice" in

            1)

                tui_msgbox \
                    "Temas disponibles:\n\nDEC VT330 Basic\nGRIDcase 1520 Basic\n\nTema instalado:\n$(current_theme)"

                ;;

            2)

                tui_msgbox \
                    "Themes Retro\n\nInstaller: $APP_VERSION\n\nRepositorio:\n$REPO_URL"

                ;;

            3)

                clone_or_update_repo ||
                    true

                local repo="$INSTALL_ROOT/repository"

                local commit

                commit="$(
                    git \
                        -C "$repo" \
                        rev-parse \
                        --short \
                        HEAD \
                        2>/dev/null ||
                        echo desconocido
                )"

                tui_msgbox \
                    "Rama: main\nCommit: $commit"

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

    clear

    echo "Reiniciando en 3 segundos..."

    sleep 3

    reboot
}

restore_backups() {

    [[ -f "$STATE_ROOT/backups" ]] ||
        return

    while IFS='|' read -r original backup; do

        [[ -n "$original" && -e "$backup" ]] ||
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

remove_theme_config() {

    local path

    if [[ -f "$STATE_ROOT/created_files" ]]; then

        while IFS= read -r path; do

            [[ -n "$path" ]] &&
                rm -rf "$path"

        done < "$STATE_ROOT/created_files"

    fi

    restore_backups

    rm -rf \
        "$TARGET_HOME/.config/bspwm" \
        "$TARGET_HOME/.config/sxhkd" \
        "$TARGET_HOME/.config/polybar"

    rm -f \
        "$STATE_ROOT/current_theme"

    : > "$STATE_ROOT/backups"

    : > "$STATE_ROOT/created_files"

    : > "$STATE_ROOT/modified_files"

    : > "$STATE_ROOT/installed_themes"
}

uninstall_theme_config() {

    if ! tui_yesno \
        "Esto elimina la configuración de Themes Retro y restaura backups cuando existan.\n\n¿Continuar?"
    then

        return

    fi

    remove_theme_config

    tui_msgbox \
        "Configuración del tema eliminada/restaurada."
}

uninstall_dependencies() {

    local removable=()
    local p
    local text=""

    if [[ ! -f "$STATE_ROOT/installed_packages" ]]; then

        tui_msgbox \
            "No hay dependencias registradas para desinstalar."

        return

    fi

    while IFS= read -r p; do

        if [[ -n "$p" ]] &&
           pkg_installed "$p"
        then

            removable+=( "$p" )

        fi

    done < "$STATE_ROOT/installed_packages"

    if ((${#removable[@]} == 0)); then

        tui_msgbox \
            "No hay dependencias instaladas por Themes Retro para eliminar."

        return
    fi

    text="Se eliminarán únicamente los paquetes instalados por este instalador:\n\n"

    for p in "${removable[@]}"; do

        text+="• ${DEP_LABEL[$p]:-$p}\n"

    done

    if ! tui_yesno \
        "$text\n¿Continuar?"
    then

        return

    fi

    for p in "${removable[@]}"; do

        msg "Eliminando $p..."

        apt-get remove \
            -y \
            "$p" \
            >> "$LOG_FILE" 2>&1 ||
            warn "No se pudo eliminar $p."

    done

    apt-get autoremove \
        -y \
        >> "$LOG_FILE" 2>&1 ||
        true

    : > "$STATE_ROOT/installed_packages"

    tui_msgbox \
        "Dependencias eliminadas.\n\nLos paquetes que ya existían antes del instalador no se eliminan."
}

uninstall_all() {

    if ! tui_yesno \
        "ATENCIÓN\n\nSe eliminarán:\n\n• Configuración de los temas\n• Dependencias instaladas por Themes Retro\n• Datos del instalador\n\n¿Continuar?"
    then

        return

    fi

    remove_theme_config

    uninstall_dependencies

    rm -rf \
        "$INSTALL_ROOT" \
        "$STATE_ROOT" \
        "$BACKUP_ROOT"

    tui_msgbox \
        "Themes Retro fue eliminado completamente."
}

uninstall_menu() {

    while true; do

        draw_header

        local choice

        choice="$(
            whiptail \
                --title "Desinstalar" \
                --menu \
                "Selecciona qué eliminar" \
                18 \
                78 \
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
                uninstall_theme_config
                ;;

            2)
                uninstall_dependencies
                ;;

            3)
                uninstall_all
                return
                ;;

            4)
                return
                ;;

        esac

    done
}

main_menu() {

    while true; do

        draw_header

        local choice

        choice="$(
            whiptail \
                --title "Menú principal" \
                --menu \
                "Selecciona una opción" \
                18 \
                78 \
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
                version_menu
                ;;

            4)
                restart_menu
                ;;

            5)
                uninstall_menu
                ;;

            6)
                clear
                exit 0
                ;;

        esac

    done
}

main() {

    require_root "$@"

    if [[ ! -f /etc/os-release ]]; then

        err "No se pudo detectar el sistema."

        exit 1

    fi

    . /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ||
          "${VERSION_ID:-}" != "22.04" ]]
    then

        err \
            "Este instalador está diseñado para Ubuntu Server 22.04."

        echo

        echo "Detectado:"
        echo "${PRETTY_NAME:-desconocido}"

        exit 1
    fi

    detect_user

    prepare_state

    ensure_apt_updated ||
        true

    ensure_whiptail ||
    {
        err "No se pudo instalar whiptail."
        exit 1
    }

    main_menu
}

main "$@"