Today 1:43 AM
chatgpt tengo este problema, estoy intentando instalar un tema para el arranque y no se vean todos los servicios que se estan activando pero pasa que se quedo con un tema anterior y no importa que ponga, no se quita
Pasted code(1).sh
File
quiero que me quite ese tiempo para ver si el inittrd no deja de cargar despues de los 10 segundo siga al siguiente

no cambies nada más

Sí. Revisé tu script y ya tenía un límite de 10 segundos, pero además tenía --kill-after=2s, por lo que podía tardar hasta unos 12 segundos antes de continuar. El bloque está en la función update_initramfs_safe.

Hice solo ese cambio:

Ahora espera máximo 10 segundos.
Al llegar a los 10 segundos, mata update-initramfs.
El instalador continúa con el siguiente paso.
No cambié ninguna otra parte del script.

Aquí tienes el archivo modificado:

Descargar script modificado

⚠️ Importante: esto significa que si update-initramfs todavía está trabajando al llegar a los 10 segundos, será terminado a la fuerza. El resto del instalador continuará igualmente. 

amber-bar-installer-10s.sh
Code
en esa fase, crea una pequeña animacion de carga, nada complejo

Listo. Añadí una animación de carga pequeña y sencilla únicamente durante la fase de update-initramfs.

Ahora mostrará algo como:

[ | ] Actualizando initramfs... 3s
[ / ] Actualizando initramfs... 4s
[ - ] Actualizando initramfs... 5s
[ \ ] Actualizando initramfs... 6s

Y mantiene el límite de 10 segundos. No cambié ninguna otra parte del instalador.

Descargar el script con la animación 

amber-bar-installer-10s-spinner.sh
Code
Today 1:00 PM
Pasted code(2).sh
File
Quiero que me ayudes con el instalador, ese cronometro quiero que se lo quites, el de los 10 segundos, tambie el archivo amber-bar quiero que se coloque en el lugar de instalacion

tambien agregame una pequeña animacion de instalación donde muestre los segundos que falta para que se termine de instalar los paquetes 

Sí. Revisé el instalador que me pasaste y lo adapté manteniendo la estructura original. El script actualmente tiene el límite de 10 segundos en update-initramfs, y también esperaba que amber-bar ya estuviera colocado en /usr/share/plymouth/themes/amber-bar.

Hice estos cambios:

Quité completamente el límite de 10 segundos de update-initramfs.

Ahora espera a que termine realmente.
Mientras trabaja muestra una animación:
[ | ] Actualizando initramfs... 05s
[ / ] Actualizando initramfs... 06s
[ - ] Actualizando initramfs... 07s
Añadí una animación durante la instalación de paquetes.
Instala plymouth y plymouth-themes si hacen falta.
Muestra los segundos transcurridos mientras apt trabaja.
No puse un "tiempo restante" falso, porque apt no proporciona un tiempo restante fiable; mostraría segundos transcurridos para que no te engañe el instalador.

Amber Bar ahora puede colocarse automáticamente.

El instalador busca una carpeta:
amber-bar/

junto al propio instalador.

Si la encuentra, copia su contenido automáticamente a:
/usr/share/plymouth/themes/amber-bar/

Por ejemplo:

📁 carpeta
├── amber-bar-installer-final.sh
└── amber-bar/
    ├── amber-bar.plymouth
    ├── amber-bar.script
    └── ...

Así ya no tienes que copiar manualmente el tema.

No cambié el funcionamiento del menú, instalación del servicio, selección del tema, GRUB ni desinstalación.

Además, comprobé la sintaxis del Bash y no presenta errores de sintaxis.

Descargar el instalador modificado

Importante: necesitas poner la carpeta amber-bar junto al instalador para que pueda copiar el tema automáticamente. El script que me enviaste no contiene dentro de sí los archivos gráficos/script del tema; solo contiene el instalador.

amber-bar-installer-final.sh
Code
1 attachment left until tomorrow at 1:44 AM
Start a free Plus trial for more.
Try Plus free

Library
/
amber-bar-installer-final.sh
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
# INSTALAR DEPENDENCIAS
# ------------------------------------------------------------

install_packages()
{
    echo
    echo "=============================================="
    echo "          INSTALANDO DEPENDENCIAS"
    echo "=============================================="
    echo

    if command -v plymouth >/dev/null 2>&1 &&        dpkg -s plymouth-themes >/dev/null 2>&1; then
        ok "Plymouth y sus temas ya están instalados."
        return 0
    fi

    info "Instalando Plymouth y Plymouth Themes..."

    local LOG_FILE="/tmp/amber-bar-apt.log"
    local PID
    local ELAPSED=0
    local SPINNER='|/-\\'
    local SPIN_INDEX=0
    local RESULT

    apt-get update >"$LOG_FILE" 2>&1 &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        printf "\r[ %s ] Actualizando paquetes... %02ds transcurridos"             "${SPINNER:$SPIN_INDEX:1}" "$ELAPSED"
        sleep 1
        ELAPSED=$((ELAPSED + 1))
        SPIN_INDEX=$(( (SPIN_INDEX + 1) % 4 ))
    done
    wait "$PID"
    RESULT=$?
    printf "\r\033[K"

    if [ "$RESULT" -ne 0 ]; then
        error "No se pudo actualizar la información de paquetes."
        tail -n 10 "$LOG_FILE" 2>/dev/null || true
        rm -f "$LOG_FILE"
        return 1
    fi

    ELAPSED=0
    SPIN_INDEX=0

    apt-get install -y plymouth plymouth-themes >>"$LOG_FILE" 2>&1 &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        printf "\r[ %s ] Instalando paquetes... %02ds transcurridos"             "${SPINNER:$SPIN_INDEX:1}" "$ELAPSED"
        sleep 1
        ELAPSED=$((ELAPSED + 1))
        SPIN_INDEX=$(( (SPIN_INDEX + 1) % 4 ))
    done
    wait "$PID"
    RESULT=$?
    printf "\r\033[K"

    if [ "$RESULT" -eq 0 ]; then
        ok "Paquetes instalados correctamente."
    else
        error "La instalación de paquetes terminó con código ${RESULT}."
        tail -n 10 "$LOG_FILE" 2>/dev/null || true
        rm -f "$LOG_FILE"
        return 1
    fi

    rm -f "$LOG_FILE"
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

    info "Ejecutando update-initramfs -u -k all..."

    local PID
    local ELAPSED=0
    local SPINNER='|/-\\'
    local SPIN_INDEX=0
    local RESULT

    update-initramfs -u -k all >/tmp/amber-bar-initramfs.log 2>&1 &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        printf "\r[ %s ] Actualizando initramfs... %02ds" \
            "${SPINNER:$SPIN_INDEX:1}" "$ELAPSED"

        sleep 1
        ELAPSED=$((ELAPSED + 1))
        SPIN_INDEX=$(( (SPIN_INDEX + 1) % 4 ))
    done

    wait "$PID"
    RESULT=$?

    printf "\r\\033[K"

    if [ "$RESULT" -eq 0 ]; then
        ok "initramfs actualizado correctamente."
    else
        warn "update-initramfs terminó con código ${RESULT}."
        warn "El instalador continuará."
        warn "Últimas líneas del proceso:"
        tail -n 5 /tmp/amber-bar-initramfs.log 2>/dev/null || true
    fi

    rm -f /tmp/amber-bar-initramfs.log
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
    # Instalar dependencias
    # --------------------------------------------------------

    if ! install_packages; then
        pause
        return
    fi

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

    # --------------------------------------------------------
    # Colocar el tema Amber Bar en su ubicación de instalación
    # --------------------------------------------------------

    INSTALLER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    SOURCE_THEME_DIR="${INSTALLER_DIR}/${THEME_NAME}"

    if [ -d "$SOURCE_THEME_DIR" ]; then
        info "Copiando Amber Bar a ${THEME_DIR}..."
        mkdir -p "$THEME_DIR"
        cp -a "$SOURCE_THEME_DIR"/. "$THEME_DIR"/
        ok "Amber Bar colocado en su ubicación de instalación."
    fi

    if [ ! -d "$THEME_DIR" ]; then
        error "No existe:"
        echo
        echo "    $THEME_DIR"
        echo
        echo "Coloca una carpeta 'amber-bar' junto a este instalador."
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