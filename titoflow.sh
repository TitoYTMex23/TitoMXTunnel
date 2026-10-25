#!/bin/bash
# ==============================================================================
#  ⚡ TITOFLOW DATA CENTER v2.1 — Motor propio + Gestor HWID + Selector de protocolo  (TitoMX)
#  Instalador y panel en un solo archivo. Debian 10+/Ubuntu 20.04+ (apt).
#  Uso:  bash titoflow.sh      → instala (1ra vez) y abre el panel
#        titoflow              → abre el panel
#        titoflow --cleanup    → corta sesiones vencidas (lo corre cron solo)
# ==============================================================================

VERSION="2.1"

# ───────── TU GITHUB (ya configurado) ─────────
# Binarios compilados por ti, subidos a un Release. Nombres esperados:
#   dnstt-server-linux-amd64  vaydns-server-linux-amd64  slipstream-server-linux-amd64
#   (y las variantes -linux-arm64 si usas VPS ARM)
REPO_BIN="https://github.com/TitoYTMex23/TitoMXTunnel/releases/latest/download"
REPO_SCRIPT="https://raw.githubusercontent.com/TitoYTMex23/TitoMXTunnel/main/titoflow.sh"
# ──────────────────────────────────────────────────────

CONF_DIR="/etc/titoflow"
CONF="$CONF_DIR/titoflow.conf"
DB="$CONF_DIR/hwid_db.txt"
KEY_DIR="$CONF_DIR/keys"
ROUTES="$CONF_DIR/routes.json"
OPT_DIR="/opt/titoflow"
BIN_DIR="$OPT_DIR/bin"
SELF="/usr/local/bin/titoflow"
LIMITS="/etc/security/limits.d/titoflow.conf"

R=$'\e[1;31m'; G=$'\e[1;32m'; Y=$'\e[1;33m'; C=$'\e[1;36m'
M=$'\e[1;35m'; W=$'\e[1;37m'; B=$'\e[1;34m'; N=$'\e[0m'
BGC=$'\e[46;30;1m'

[[ $EUID -ne 0 ]] && { echo "${R}Ejecuta como root (sudo -i)${N}"; exit 1; }

case "$(uname -m)" in
    x86_64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) ARCH=amd64 ;;
esac

declare -A ON

# ══════════════════════════ UTILIDADES ══════════════════════════
pause() { read -rp "  ${Y}Enter para continuar...${N}" _; }
ok()    { echo "  ${G}[✔]${N} $*"; }
warn()  { echo "  ${Y}[!]${N} $*"; }
fail()  { echo "  ${R}[✘]${N} $*"; }
line()  { echo "${Y}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }
sline() { echo "${C}──────────────────────────────────────────────────────────────────${N}"; }

get_ip() {
    curl -s4 --max-time 5 ifconfig.me 2>/dev/null \
    || curl -s4 --max-time 5 api.ipify.org 2>/dev/null \
    || hostname -I | awk '{print $1}'
}

load_conf() {
    DOMAIN=""; TARGET_PORT=22; MTU=700
    P_DNSTT=5300; P_VAY=5301; P_SLIP=5302; SERVER_IP=""
    [[ -f $CONF ]] && source "$CONF"
    if [[ -z $SERVER_IP ]]; then SERVER_IP=$(get_ip); fi
}

save_conf() {
    mkdir -p "$CONF_DIR"
    cat > "$CONF" <<EOF
DOMAIN="$DOMAIN"
TARGET_PORT="$TARGET_PORT"
MTU="$MTU"
P_DNSTT="$P_DNSTT"
P_VAY="$P_VAY"
P_SLIP="$P_SLIP"
SERVER_IP="$SERVER_IP"
EOF
    chmod 600 "$CONF"
}

svc() { systemctl is-active --quiet "titoflow-$1" 2>/dev/null && echo "${G}ON${N}" || echo "${R}OFF${N}"; }

compute_online() {
    ON=()
    while read -r u c; do
        [[ -n $u ]] && ON[$u]=$c
    done < <(ps -eo user:32=,args= | awk '$1!="root" && $2=="sshd:" {c[$1]++} END{for(u in c) print u,c[u]}')
}

days_left() {   # $1 = fecha YYYY-MM-DD
    echo $(( ( $(date -d "$1" +%s) - $(date -d "$(date +%F)" +%s) ) / 86400 ))
}

# ══════════════════════════ PANEL PRINCIPAL ══════════════════════════
dashboard() {
    clear
    load_conf
    compute_online
    local today total=0 expd=0 onl=0 h n e m s t p
    today=$(date +%F)
    if [[ -f $DB ]]; then
        while IFS='|' read -r h n e m s t p; do
            [[ -z $h ]] && continue
            total=$((total+1))
            [[ ! "$e" > "$today" ]] && expd=$((expd+1))
            onl=$((onl + ${ON[$h]:-0}))
        done < "$DB"
    fi
    local os cpus ram cpu disk
    os=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")
    cpus=$(nproc)
    ram=$(free -m | awk '/Mem/{printf "%d/%dMB (%.0f%%)",$3,$2,$3*100/$2}')
    cpu=$(top -bn1 | awk '/Cpu\(s\)/{printf "%.1f", $2+$4}')
    disk=$(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')

    echo "${BGC}       ⚡⚡⚡  TITOFLOW DATA CENTER  ✦  TitoMX  ⚡⚡⚡       ${N}"
    echo
    echo " ${C}◈${N} ONLINES: ${G}${onl}${N}  ${C}◈${N} VENCIDOS: ${R}${expd}${N}  ${C}◈${N} TOTAL: ${Y}${total}${N}"
    echo " ${C}◈${N} S.O: ${W}${os}${N}  ${C}◈${N} CPU's: ${W}${cpus}${N}"
    echo " ${C}◈${N} IP: ${M}${SERVER_IP}${N}  ${C}◈${N} FECHA: ${W}$(date '+%d/%m/%Y-%H:%M')${N}"
    line
    echo " ${Y}Key:${N} ${G}Verified${N} ${C}[ TitoFlow v${VERSION} ]${N}  ${C}Dominio:${N} ${W}${DOMAIN:-sin configurar}${N}"
    line
    echo " ${C}◈${N} SSH destino : ${W}127.0.0.1:${TARGET_PORT}${N}   ${C}◈${N} MTU: ${W}${MTU}${N}"
    echo " ${C}◈${N} DNS-Router :53 $(svc dnsrouter)   ${C}◈${N} VayDNS :${P_VAY} $(svc vaydns)"
    echo " ${C}◈${N} DNSTT :${P_DNSTT} $(svc dnstt)       ${C}◈${N} Slipstream :${P_SLIP} $(svc slipstream)"
    line
    echo " ${C}◈${N} RAM: ${W}${ram}${N}  ${C}◈${N} CPU: ${W}${cpu}%${N}  ${C}◈${N} DISCO: ${W}${disk}${N}"
    line
    echo " ${R}[${W}01${R}]${N} ${C}◈${N} CREAR HWID  ${G}(elige protocolo)${N}"
    echo " ${R}[${W}02${R}]${N} ${C}◈${N} CREAR USUARIO MANUAL  ${G}(elige protocolo)${N}"
    echo " ${R}[${W}03${R}]${N} ${C}◈${N} CREAR USUARIOS EN LOTE  ${G}(elige protocolo)${N}"
    echo " ${R}[${W}04${R}]${N} ${C}◈${N} LISTA DE CLIENTES  ${G}(online / vencimientos)${N}"
    echo " ${R}[${W}05${R}]${N} ${C}◈${N} EDITAR  ${G}(clave / límite / vencimiento)${N}"
    echo " ${R}[${W}06${R}]${N} ${C}◈${N} RENOVAR"
    echo " ${R}[${W}07${R}]${N} ${C}◈${N} SUSPENDER / REACTIVAR"
    echo " ${R}[${W}08${R}]${N} ${C}◈${N} ELIMINAR"
    echo " ${R}[${W}09${R}]${N} ${C}◈${N} ELIMINAR VENCIDOS"
    echo " ${R}[${W}10${R}]${N} ${C}◈${N} GENERAR LINK slipnet://  ${G}(elige protocolo)${N}"
    echo " ${R}[${W}11${R}]${N} ${C}◈${N} REINICIAR TÚNELES"
    echo " ${R}[${W}12${R}]${N} ${C}◈${N} AJUSTES  ${G}(dominio / MTU / puerto destino)${N}"
    echo " ${R}[${W}13${R}]${N} ${C}◈${N} INSTALAR / REPARAR / ACTUALIZAR MOTORES"
    echo " ${R}[${W}14${R}]${N} ${C}◈${N} ACTUALIZAR SCRIPT"
    echo " ${R}[${W}00${R}]${N} ${C}◈${N} ${R}[ SALIR ]${N}"
    line
}

# ══════════════════════════ USUARIOS (HWID + MANUAL) ══════════════════════════
# DB: id|nombre|vence|limite|estado|tipo|clave      (tipo = HWID o MANUAL)
valid_hwid()  { [[ "$1" =~ ^[A-Za-z0-9]{6,32}$ ]]; }
valid_uname() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]; }
valid_id()    { [[ "$1" =~ ^[A-Za-z0-9_-]{3,32}$ ]]; }
valid_limit() { [[ "$1" =~ ^[0-9]{1,3}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 999 )); }
valid_days()  { [[ "$1" =~ ^[0-9]{1,4}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 3650 )); }
valid_pass()  { [[ "$1" =~ ^[A-Za-z0-9@#%+=._-]{4,32}$ ]]; }
rand_pass()   { tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' </dev/urandom | head -c 8; }

db_get() { grep "^$1|" "$DB" 2>/dev/null | head -1; }

# Evita tocar usuarios del sistema (root, backup, etc.)
is_foreign() { id "$1" &>/dev/null && [[ -z $(db_get "$1") ]]; }

create_user() {   # $1=id $2=nombre $3=fecha_exp [$4=clave]
    local nologin; nologin=$(command -v nologin || echo /usr/sbin/nologin)
    if id "$1" &>/dev/null; then
        usermod -U -e "$3" "$1" || return 1
        [[ -n $4 ]] && echo "$1:$4" | chpasswd
    else
        { useradd -M -s "$nologin" -e "$3" -c "$2" "$1" 2>/dev/null \
          || useradd --badname -M -s "$nologin" -e "$3" -c "$2" "$1"; } || return 1
        echo "$1:${4:-$1}" | chpasswd
    fi
}

set_limit() {     # $1=id $2=max
    touch "$LIMITS"
    sed -i "/^$1[[:space:]]/d" "$LIMITS"
    echo "$1 hard maxlogins $((10#$2))" >> "$LIMITS"
}

db_set() {        # id nombre exp max estado [tipo] [clave]
    touch "$DB"; chmod 600 "$DB"
    local old tipo pass
    old=$(db_get "$1")
    IFS='|' read -r _ _ _ _ _ tipo pass <<< "$old"
    tipo=${6:-${tipo:-HWID}}
    [[ $# -ge 7 ]] && pass=$7
    sed -i "/^$1|/d" "$DB"
    echo "$1|$2|$3|$4|$5|$tipo|$pass" >> "$DB"
}

user_card() {     # id nombre exp lim tipo clave
    echo "    ${C}Usuario:${N}      $1"
    if [[ "$5" == "MANUAL" ]]; then echo "    ${C}Contraseña:${N}   $6"
    else echo "    ${C}Contraseña:${N}   (igual al HWID)"; fi
    echo "    ${C}Cliente:${N}      $2"
    echo "    ${C}Vence:${N}        $3  ($(days_left "$3") días)"
    echo "    ${C}Límite:${N}       $4 conexión(es) simultánea(s)"
}

add_client() {
    clear; echo "${BGC}        🔑  AUTORIZAR NUEVO DISPOSITIVO (HWID)        ${N}"; echo
    choose_proto || return
    read -rp "  HWID del dispositivo: " h
    valid_hwid "$h" || { fail "HWID inválido (solo letras/números, 6-32)"; pause; return; }
    is_foreign "$h" && { fail "Ese nombre ya existe en el sistema (no es de TitoFlow)"; pause; return; }
    read -rp "  Nombre / referencia del cliente: " name
    name=${name//|/ }; name=${name:-cliente}
    read -rp "  Días de vigencia [30]: " d; d=${d:-30}
    valid_days "$d" || { fail "Días inválidos (1-3650)"; pause; return; }
    read -rp "  Límite de dispositivos simultáneos (1-999) [1]: " m; m=${m:-1}
    valid_limit "$m" || { fail "Límite inválido (1-999)"; pause; return; }
    d=$((10#$d)); m=$((10#$m))

    local exp; exp=$(date -d "+$d days" +%F)
    create_user "$h" "$name" "$exp" "$h" || { fail "No se pudo crear el usuario"; pause; return; }
    set_limit "$h" "$m"
    db_set "$h" "$name" "$exp" "$m" ACTIVO HWID ""
    echo; ok "Dispositivo autorizado"
    user_card "$h" "$name" "$exp" "$m" HWID ""
    echo "    ${C}Protocolo:${N}    $(proto_title)"
    echo; generate_uri "$h" "" "$PROTO"
    pause
}

add_manual() {
    clear; echo "${BGC}        👤  CREAR USUARIO MANUAL (usuario + contraseña)        ${N}"; echo
    choose_proto || return
    read -rp "  Usuario (minúsculas/números, 3-32): " u
    valid_uname "$u" || { fail "Usuario inválido (minúsculas, números, _ -; empieza con letra)"; pause; return; }
    is_foreign "$u" && { fail "Ese usuario ya existe en el sistema (no es de TitoFlow)"; pause; return; }
    read -rp "  Contraseña [Enter = generar]: " p; p=${p:-$(rand_pass)}
    valid_pass "$p" || { fail "Contraseña inválida (4-32 caracteres: letras, números y @#%+=._-)"; pause; return; }
    read -rp "  Nombre / referencia [Enter = usuario]: " name
    name=${name//|/ }; name=${name:-$u}
    read -rp "  Días de vigencia [30]: " d; d=${d:-30}
    valid_days "$d" || { fail "Días inválidos (1-3650)"; pause; return; }
    read -rp "  Límite de conexiones simultáneas (1-999) [1]: " m; m=${m:-1}
    valid_limit "$m" || { fail "Límite inválido (1-999)"; pause; return; }
    d=$((10#$d)); m=$((10#$m))

    local exp; exp=$(date -d "+$d days" +%F)
    create_user "$u" "$name" "$exp" "$p" || { fail "No se pudo crear el usuario"; pause; return; }
    set_limit "$u" "$m"
    db_set "$u" "$name" "$exp" "$m" ACTIVO MANUAL "$p"
    echo; ok "Usuario creado"
    user_card "$u" "$name" "$exp" "$m" MANUAL "$p"
    echo "    ${C}Protocolo:${N}    $(proto_title)"
    echo; generate_uri "$u" "$p" "$PROTO"
    pause
}

add_bulk() {
    clear; echo "${BGC}        📦  CREAR USUARIOS EN LOTE        ${N}"; echo
    choose_proto || return
    read -rp "  Prefijo (ej. tito → tito001, tito002...): " pre
    [[ "$pre" =~ ^[a-z][a-z0-9_-]{1,20}$ ]] || { fail "Prefijo inválido (minúsculas/números, empieza con letra)"; pause; return; }
    read -rp "  Cantidad (1-200): " q
    { [[ "$q" =~ ^[0-9]{1,3}$ ]] && (( 10#$q >= 1 && 10#$q <= 200 )); } || { fail "Cantidad inválida (1-200)"; pause; return; }
    read -rp "  Días de vigencia [30]: " d; d=${d:-30}
    valid_days "$d" || { fail "Días inválidos (1-3650)"; pause; return; }
    read -rp "  Límite por usuario (1-999) [1]: " m; m=${m:-1}
    valid_limit "$m" || { fail "Límite inválido (1-999)"; pause; return; }
    q=$((10#$q)); d=$((10#$d)); m=$((10#$m))

    local exp out i=0 made=0 u p
    exp=$(date -d "+$d days" +%F)
    out="/root/lote_${pre}_$(date +%Y%m%d_%H%M%S).txt"
    : > "$out"; chmod 600 "$out"
    echo
    printf "${C}%-20s %-12s %-11s %s${N}\n" USUARIO CLAVE VENCE LIM
    sline
    while (( made < q && i < 9999 )); do
        i=$((i+1)); u=$(printf "%s%03d" "$pre" "$i")
        id "$u" &>/dev/null && continue
        [[ -n $(db_get "$u") ]] && continue
        p=$(rand_pass)
        create_user "$u" "$u" "$exp" "$p" || continue
        set_limit "$u" "$m"
        db_set "$u" "$u" "$exp" "$m" ACTIVO MANUAL "$p"
        printf "%-20s %-12s %-11s %s\n" "$u" "$p" "$exp" "$m"
        bulk_links "$u" "$p" "$exp" "$m" >> "$out"
        made=$((made+1))
    done
    echo; ok "$made usuario(s) creados"
    ok "Lista con links guardada en: ${W}$out${N}"
    pause
}

list_clients() {
    clear; echo "${BGC}        📊  CLIENTES REGISTRADOS        ${N}"; echo
    load_conf; compute_online
    if [[ ! -s $DB ]]; then warn "No hay usuarios registrados."; pause; return; fi
    read -rp "  Filtro (Enter = todos): " f
    echo
    printf "${C}%-18s %-7s %-10s %-10s %-11s %-5s %-4s %-4s %s${N}\n" USUARIO/HWID TIPO CLAVE CLIENTE VENCE DÍAS LIM ONL ESTADO
    sline
    local today h n e m s t p dl st pv shown=0
    today=$(date +%F)
    while IFS='|' read -r h n e m s t p; do
        [[ -z $h ]] && continue
        [[ -n $f && "$h|$n" != *"$f"* ]] && continue
        t=${t:-HWID}
        if [[ $t == MANUAL ]]; then pv=$p; else pv="-"; fi
        dl=$(days_left "$e")
        if [[ "$s" == "SUSPENDIDO" ]]; then st="${Y}SUSPENDIDO${N}"
        elif [[ ! "$e" > "$today" ]]; then st="${R}VENCIDO${N}"
        else st="${G}ACTIVO${N}"; fi
        printf "%-18s %-7s %-10s %-10s %-11s %-5s %-4s %-4s %s\n" "$h" "$t" "$pv" "${n:0:10}" "$e" "$dl" "$m" "${ON[$h]:-0}" "$st"
        shown=$((shown+1))
    done < "$DB"
    echo; echo "  ${C}Mostrando:${N} $shown"
    pause
}

edit_client() {
    clear; echo "${BGC}        ✏  EDITAR USUARIO / HWID        ${N}"; echo
    read -rp "  Usuario o HWID: " h
    local rec; rec=$(db_get "$h")
    [[ -z $rec ]] && { fail "No registrado en TitoFlow"; pause; return; }
    local n e m s t p
    IFS='|' read -r _ n e m s t p <<< "$rec"; t=${t:-HWID}
    echo
    user_card "$h" "$n" "$e" "$m" "$t" "$p"
    echo
    echo "  1) Cambiar contraseña  (solo usuarios MANUAL)"
    echo "  2) Cambiar límite de conexiones (1-999)"
    echo "  3) Cambiar vencimiento (días desde hoy, o fecha AAAA-MM-DD)"
    echo "  4) Cambiar nombre / referencia"
    echo "  0) Volver"
    read -rp "  Opción: " o
    case $o in
        1)  [[ $t != MANUAL ]] && { warn "Un HWID siempre usa su propio ID como contraseña."; pause; return; }
            read -rp "  Nueva contraseña [Enter = generar]: " np; np=${np:-$(rand_pass)}
            valid_pass "$np" || { fail "Contraseña inválida"; pause; return; }
            echo "$h:$np" | chpasswd && db_set "$h" "$n" "$e" "$m" "$s" MANUAL "$np"
            ok "Contraseña cambiada: ${W}$np${N}" ;;
        2)  read -rp "  Nuevo límite (1-999): " nm
            valid_limit "$nm" || { fail "Límite inválido"; pause; return; }
            nm=$((10#$nm)); set_limit "$h" "$nm"; db_set "$h" "$n" "$e" "$nm" "$s"
            ok "Límite: $nm" ;;
        3)  read -rp "  Días desde hoy o fecha: " v
            local ne
            if [[ "$v" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -d "$v" >/dev/null 2>&1; then ne=$(date -d "$v" +%F)
            elif valid_days "$v"; then ne=$(date -d "+$((10#$v)) days" +%F)
            else fail "Valor inválido"; pause; return; fi
            usermod -e "$ne" "$h" && db_set "$h" "$n" "$ne" "$m" "$s"
            ok "Vence: $ne" ;;
        4)  read -rp "  Nuevo nombre: " nn; nn=${nn//|/ }
            [[ -n $nn ]] && db_set "$h" "$nn" "$e" "$m" "$s" && ok "Nombre actualizado" ;;
        *)  return ;;
    esac
    pause
}

renew_client() {
    clear; echo "${BGC}        🔄  RENOVAR        ${N}"; echo
    read -rp "  Usuario o HWID: " h
    local rec; rec=$(db_get "$h")
    [[ -z $rec ]] && { fail "No registrado en TitoFlow"; pause; return; }
    local n e m s
    IFS='|' read -r _ n e m s _ <<< "$rec"
    read -rp "  Días a sumar [30]: " d; d=${d:-30}
    valid_days "$d" || { fail "Días inválidos (1-3650)"; pause; return; }
    local base today; today=$(date +%F)
    if [[ "$e" > "$today" ]]; then base="$e"; else base="$today"; fi
    local newexp; newexp=$(date -d "$base +$((10#$d)) days" +%F)
    create_user "$h" "$n" "$newexp"
    db_set "$h" "$n" "$newexp" "$m" "ACTIVO"
    ok "Renovado hasta ${W}$newexp${N}"
    pause
}

toggle_client() {
    clear; echo "${BGC}        🚫  SUSPENDER / REACTIVAR        ${N}"; echo
    read -rp "  Usuario o HWID: " h
    local rec; rec=$(db_get "$h")
    [[ -z $rec ]] && { fail "No registrado en TitoFlow"; pause; return; }
    local n e m s
    IFS='|' read -r _ n e m s _ <<< "$rec"
    if [[ "$s" == "SUSPENDIDO" ]]; then
        create_user "$h" "$n" "$e"
        db_set "$h" "$n" "$e" "$m" "ACTIVO"
        ok "$h reactivado"
    else
        usermod -L "$h" 2>/dev/null
        pkill -KILL -u "$h" 2>/dev/null
        db_set "$h" "$n" "$e" "$m" "SUSPENDIDO"
        ok "$h suspendido y desconectado en vivo"
    fi
    pause
}

remove_one() {    # $1 = id (quita usuario del sistema y de la base)
    pkill -KILL -u "$1" 2>/dev/null
    userdel -f "$1" 2>/dev/null
    sed -i "/^$1|/d" "$DB" 2>/dev/null
    sed -i "/^$1[[:space:]]/d" "$LIMITS" 2>/dev/null
}

delete_client() {
    clear; echo "${BGC}        🗑  ELIMINAR USUARIO / HWID        ${N}"; echo
    read -rp "  Usuario o HWID a eliminar: " h
    valid_id "$h" || { fail "Valor inválido"; pause; return; }
    [[ -z $(db_get "$h") ]] && { fail "No registrado en TitoFlow (no lo toco)"; pause; return; }
    remove_one "$h"
    ok "$h eliminado y desconectado"
    pause
}

purge_expired() {
    clear; echo "${BGC}        🧹  ELIMINAR VENCIDOS        ${N}"; echo
    [[ -s $DB ]] || { warn "No hay usuarios registrados."; pause; return; }
    local today h n e m s t p list=()
    today=$(date +%F)
    while IFS='|' read -r h n e m s t p; do
        [[ -z $h ]] && continue
        [[ ! "$e" > "$today" ]] && list+=("$h")
    done < "$DB"
    if [[ ${#list[@]} -eq 0 ]]; then ok "No hay vencidos."; pause; return; fi
    echo "  Vencidos (${#list[@]}): ${list[*]}"
    read -rp "  ¿Eliminar todos? [y/N]: " c
    if [[ $c == y || $c == Y ]]; then
        for h in "${list[@]}"; do remove_one "$h"; done
        ok "${#list[@]} usuario(s) eliminados"
    fi
    pause
}

cleanup() {
    [[ -f $DB ]] || return
    local today h n e m s t p; today=$(date +%F)
    while IFS='|' read -r h n e m s t p; do
        [[ -z $h ]] && continue
        if [[ ! "$e" > "$today" || "$s" == "SUSPENDIDO" ]]; then
            pkill -KILL -u "$h" 2>/dev/null
        fi
    done < "$DB"
}

# ══════════════════════════ PROTOCOLOS + LINK slipnet:// ══════════════════════════
# Todos los protocolos DNS terminan en el mismo SSH local: un usuario sirve en cualquiera.
# Para sumar uno nuevo: agrega su línea aquí y su motor en apply_services.
# clave|etiqueta|tipo slipnet|subdominio|llave pública (vacío = no usa)|motor
PROTOS=(
    "vaydns|VayDNS + SSH|vaydns_ssh|vs|vaydns.pub|vaydns-server"
    "dnstt|DNSTT + SSH|dnstt_ssh|ts|dnstt.pub|dnstt-server"
    "slipstream|Slipstream + SSH|slipstream_ssh|ss||slipstream-server"
)
# Protocolos cuyo link ya se comprobó contra la app. Los demás muestran un aviso.
VERIFIED="vaydns"
PROTO=""

proto_load() {    # $1=clave → PR_KEY PR_LABEL PR_TYPE PR_SUB PR_KEYF PR_ENG
    local p
    for p in "${PROTOS[@]}"; do
        [[ ${p%%|*} == "$1" ]] && { IFS='|' read -r PR_KEY PR_LABEL PR_TYPE PR_SUB PR_KEYF PR_ENG <<< "$p"; return 0; }
    done
    return 1
}

proto_installed() { [[ -f "/etc/systemd/system/titoflow-$1.service" ]]; }

proto_title() {
    if [[ $PROTO == all ]]; then echo "TODOS"
    else proto_load "$PROTO" && echo "$PR_LABEL"; fi
}

choose_proto() {  # deja la elección en $PROTO (vaydns | dnstt | slipstream | all)
    local p i=0 k lbl st n=${#PROTOS[@]} o
    PROTO=""
    echo "  ${Y}¿Qué protocolo quieres crear?${N}"
    echo
    for p in "${PROTOS[@]}"; do
        i=$((i+1)); k=${p%%|*}; lbl=$(echo "$p" | cut -d'|' -f2)
        if proto_installed "$k"; then st="${G}ON${N}"; else st="${R}no instalado${N}"; fi
        echo "   ${R}[${W}${i}${R}]${N} ${C}◈${N} ${lbl}  ${st}"
    done
    echo "   ${R}[${W}$((n+1))${R}]${N} ${C}◈${N} TODOS  ${G}(un link por cada protocolo activo)${N}"
    echo "   ${R}[${W}0${R}]${N} ${C}◈${N} ${R}[ CANCELAR ]${N}"
    echo
    read -rp "  ${W}► Protocolo [1]: ${N}" o; o=${o:-1}
    [[ $o == 0 ]] && return 1
    if [[ $o =~ ^[0-9]+$ ]] && (( 10#$o == n + 1 )); then
        PROTO=all
    elif [[ $o =~ ^[0-9]+$ ]] && (( 10#$o >= 1 && 10#$o <= n )); then
        p=${PROTOS[$((10#$o-1))]}; k=${p%%|*}
        proto_installed "$k" || { fail "Ese protocolo no está instalado (opción 13 para instalarlo)"; pause; return 1; }
        PROTO=$k
    else
        fail "Opción inválida"; pause; return 1
    fi
    echo
}

build_uri() {     # $1=clave de protocolo  $2=usuario  $3=clave (si falta, = usuario)
    local U=$2 P=${3:-$2} pub=""
    proto_load "$1" || return 1
    if [[ -n $PR_KEYF ]]; then
        pub=$(cat "$KEY_DIR/$PR_KEYF" 2>/dev/null)
        [[ -z $pub ]] && return 1
    fi
    # Estructura slipnet v22 (la misma que genera tu app para VayDNS + SSH).
    local RAW="22|${PR_TYPE}|TitoFlow-${PR_LABEL%% *}|${PR_SUB}.${DOMAIN}|8.8.8.8:53:0|0|5000|bbr|1080|127.0.0.1|0|${pub}|${U}|${P}|1|${U}|${P}|22|0|${SERVER_IP}|0||udp|password||||0|443|||0||0|0||0||0|0|1080|0|caa|101|0|0|0|0|0|2|0|||8080||0|/|1||"
    echo "slipnet://$(echo -n "$RAW" | base64 -w 0)"
}

generate_uri() {  # $1=usuario  $2=clave (vacío en HWID)  $3=protocolo (vaydns|dnstt|slipstream|all)
    load_conf
    local which=${3:-vaydns} ks=() p k uri
    if [[ $which == all ]]; then
        for p in "${PROTOS[@]}"; do k=${p%%|*}; proto_installed "$k" && ks+=("$k"); done
    else
        ks=("$which")
    fi
    [[ ${#ks[@]} -eq 0 ]] && { warn "No hay protocolos activos (opción 13)."; return; }
    for k in "${ks[@]}"; do
        proto_load "$k" || continue
        uri=$(build_uri "$k" "$1" "$2")
        if [[ -z $uri ]]; then warn "$PR_LABEL: falta la llave pública (opción 13)."; continue; fi
        echo "  ${Y}📋 Link para el cliente ($PR_LABEL):${N}"
        echo "${G}${uri}${N}"
        [[ " $VERIFIED " == *" $k "* ]] || echo "  ${Y}⚠ El formato de $PR_LABEL aún no está verificado con la app: prueba el link antes de entregarlo.${N}"
        echo
    done
}

bulk_links() {    # $1=usuario $2=clave $3=vence $4=límite  (usa $PROTO; una línea por protocolo)
    local p k
    for p in "${PROTOS[@]}"; do
        k=${p%%|*}
        [[ $PROTO != all && $PROTO != "$k" ]] && continue
        proto_installed "$k" || continue
        proto_load "$k"
        echo "$1 | $2 | $3 | $4 | $PR_LABEL | $(build_uri "$k" "$1" "$2")"
    done
}

link_menu() {
    clear; echo "${BGC}        🔗  GENERAR LINK        ${N}"; echo
    read -rp "  Usuario o HWID: " h
    local rec t p; rec=$(db_get "$h")
    [[ -z $rec ]] && { fail "No registrado en TitoFlow"; pause; return; }
    IFS='|' read -r _ _ _ _ _ t p <<< "$rec"
    [[ $t == MANUAL ]] || p=""
    echo
    choose_proto || return
    generate_uri "$h" "$p" "$PROTO"
    pause
}

# ══════════════════════════ MOTORES / INSTALACIÓN ══════════════════════════
fetch_engine() {  # $1 = nombre (dnstt-server, vaydns-server, slipstream-server)
    local dest="$BIN_DIR/$1"
    mkdir -p "$BIN_DIR"
    if curl -fsSL --max-time 180 -o "$dest.tmp" "$REPO_BIN/$1-linux-$ARCH"; then
        mv -f "$dest.tmp" "$dest"; chmod +x "$dest"; return 0
    fi
    rm -f "$dest.tmp"; return 1
}

fetch_all_engines() {
    local e got=0
    for e in dnstt-server vaydns-server slipstream-server; do
        if fetch_engine "$e"; then ok "Motor $e descargado"; got=$((got+1))
        elif [[ -x $BIN_DIR/$e ]]; then warn "$e: no se pudo bajar, uso la copia local"; got=$((got+1))
        else warn "$e: no está en tu repo (se omite)"; fi
    done
    return $(( got == 0 ))
}

gen_keys() {
    mkdir -p "$KEY_DIR"; chmod 700 "$KEY_DIR"
    local old=/etc/slipgate/tunnels e f
    # Reutiliza las llaves del instalador anterior: los links ya vendidos siguen funcionando
    if [[ -f $old/dnstt-ssh/server.key && ! -f $KEY_DIR/dnstt.key ]]; then
        cp "$old/dnstt-ssh/server.key" "$KEY_DIR/dnstt.key"; ok "Llave DNSTT reutilizada"
    fi
    if [[ -f $old/vaydns-ssh/server.key && ! -f $KEY_DIR/vaydns.key ]]; then
        cp "$old/vaydns-ssh/server.key" "$KEY_DIR/vaydns.key"; ok "Llave VayDNS reutilizada"
        for f in "$old"/vaydns-ssh/*.pub; do [[ -f $f ]] && cp "$f" "$KEY_DIR/vaydns.pub" && break; done
    fi
    if [[ -f $old/slipstream-ssh/cert.pem && ! -f $KEY_DIR/slip.crt ]]; then
        cp "$old/slipstream-ssh/cert.pem" "$KEY_DIR/slip.crt"
        cp "$old/slipstream-ssh/key.pem"  "$KEY_DIR/slip.key"; ok "Certificado Slipstream reutilizado"
    fi
    # Si no había llaves viejas, se generan nuevas
    for e in dnstt vaydns; do
        if [[ -x $BIN_DIR/$e-server && ! -f $KEY_DIR/$e.key ]]; then
            "$BIN_DIR/$e-server" -gen-key -privkey-file "$KEY_DIR/$e.key" -pubkey-file "$KEY_DIR/$e.pub" >/dev/null 2>&1 \
              && ok "Llaves $e generadas" || warn "No se pudo generar llave de $e (revisa: $BIN_DIR/$e-server -h)"
        fi
    done
    if [[ -x $BIN_DIR/slipstream-server && ! -f $KEY_DIR/slip.crt ]]; then
        openssl req -x509 -newkey rsa:2048 -nodes -keyout "$KEY_DIR/slip.key" -out "$KEY_DIR/slip.crt" \
            -days 3650 -subj "/CN=$DOMAIN" >/dev/null 2>&1 && ok "Certificado Slipstream generado"
    fi
    # La llave pública de VayDNS va dentro de los links slipnet://
    if [[ -f $KEY_DIR/vaydns.key && ! -s $KEY_DIR/vaydns.pub ]]; then
        warn "Falta la llave pública de VayDNS (64 caracteres hex)."
        read -rp "  Pégala aquí: " pk
        [[ $pk =~ ^[0-9a-fA-F]{64}$ ]] && echo "$pk" > "$KEY_DIR/vaydns.pub" || warn "Llave inválida; podrás ponerla en $KEY_DIR/vaydns.pub"
    fi
    if [[ -f $KEY_DIR/dnstt.key && ! -s $KEY_DIR/dnstt.pub ]]; then
        warn "Falta la llave pública de DNSTT (64 caracteres hex)."
        read -rp "  Pégala aquí (Enter = omitir): " pk
        [[ $pk =~ ^[0-9a-fA-F]{64}$ ]] && echo "$pk" > "$KEY_DIR/dnstt.pub" || warn "Sin llave pública DNSTT; podrás ponerla en $KEY_DIR/dnstt.pub"
    fi
}

write_unit() {    # $1=nombre $2=desc $3=ExecStart
    cat > "/etc/systemd/system/titoflow-$1.service" <<EOF
[Unit]
Description=TitoFlow $2
After=network.target

[Service]
ExecStart=$3
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
}

write_router() {
    mkdir -p "$OPT_DIR"
    cat > "$OPT_DIR/dnsrouter.py" <<'PY'
#!/usr/bin/env python3
# TitoFlow DNS Router: escucha UDP/53 y reparte por dominio a cada motor.
import asyncio, json, signal

CFG = "/etc/titoflow/routes.json"
routes = {}

def load():
    global routes
    try:
        with open(CFG) as f:
            routes = json.load(f)
    except Exception:
        pass

def qname(data):
    i, labels = 12, []
    try:
        while True:
            l = data[i]
            if l == 0:
                break
            if l & 0xC0:
                return None
            labels.append(data[i + 1:i + 1 + l].decode("ascii", "ignore").lower())
            i += 1 + l
    except IndexError:
        return None
    return ".".join(labels)

class Router(asyncio.DatagramProtocol):
    def connection_made(self, t):
        self.t = t

    def datagram_received(self, data, addr):
        name = qname(data)
        if not name:
            return
        for dom, port in routes.items():
            if name == dom or name.endswith("." + dom):
                asyncio.ensure_future(self.fwd(data, addr, port))
                return

    async def fwd(self, data, addr, port):
        loop = asyncio.get_running_loop()
        fut = loop.create_future()

        class C(asyncio.DatagramProtocol):
            def datagram_received(s, d, a):
                if not fut.done():
                    fut.set_result(d)

            def error_received(s, e):
                if not fut.done():
                    fut.set_exception(e)

        tr, _ = await loop.create_datagram_endpoint(C, remote_addr=("127.0.0.1", port))
        try:
            tr.sendto(data)
            resp = await asyncio.wait_for(fut, 5)
            self.t.sendto(resp, addr)
        except Exception:
            pass
        finally:
            tr.close()

async def main():
    load()
    loop = asyncio.get_running_loop()
    loop.add_signal_handler(signal.SIGHUP, load)
    await loop.create_datagram_endpoint(Router, local_addr=("0.0.0.0", 53))
    await asyncio.Event().wait()

asyncio.run(main())
PY
    chmod +x "$OPT_DIR/dnsrouter.py"
}

apply_services() {
    load_conf
    [[ -z $DOMAIN ]] && { fail "Falta el dominio (opción 12)"; return 1; }
    local svcs=() sep="" routes="{"
    systemctl stop titoflow-dnsrouter titoflow-dnstt titoflow-vaydns titoflow-slipstream 2>/dev/null

    # Banderas copiadas de tus servicios que ya funcionaban (slipgate)
    if [[ -x $BIN_DIR/dnstt-server && -f $KEY_DIR/dnstt.key ]]; then
        write_unit dnstt "DNSTT" "$BIN_DIR/dnstt-server -privkey-file $KEY_DIR/dnstt.key -mtu $MTU ts.$DOMAIN 127.0.0.1:$P_DNSTT 127.0.0.1:$TARGET_PORT"
        routes+="${sep}\"ts.$DOMAIN\":$P_DNSTT"; sep=","; svcs+=(titoflow-dnstt)
    fi
    if [[ -x $BIN_DIR/vaydns-server && -f $KEY_DIR/vaydns.key ]]; then
        write_unit vaydns "VayDNS" "$BIN_DIR/vaydns-server -udp 127.0.0.1:$P_VAY -privkey-file $KEY_DIR/vaydns.key -mtu $MTU -domain vs.$DOMAIN -upstream 127.0.0.1:$TARGET_PORT -idle-timeout 10s -keepalive 2s -clientid-size 2 -record-type caa"
        routes+="${sep}\"vs.$DOMAIN\":$P_VAY"; sep=","; svcs+=(titoflow-vaydns)
    fi
    if [[ -x $BIN_DIR/slipstream-server && -f $KEY_DIR/slip.crt ]]; then
        write_unit slipstream "Slipstream" "$BIN_DIR/slipstream-server --dns-listen-host 127.0.0.1 --dns-listen-port $P_SLIP --cert $KEY_DIR/slip.crt --key $KEY_DIR/slip.key --domain ss.$DOMAIN --target-address 127.0.0.1:$TARGET_PORT"
        routes+="${sep}\"ss.$DOMAIN\":$P_SLIP"; sep=","; svcs+=(titoflow-slipstream)
    fi
    routes+="}"
    if [[ ${#svcs[@]} -eq 0 ]]; then fail "No hay motores instalados (opción 13)"; return 1; fi

    echo "$routes" > "$ROUTES"
    write_router
    write_unit dnsrouter "DNS Router" "/usr/bin/python3 $OPT_DIR/dnsrouter.py"
    svcs+=(titoflow-dnsrouter)

    systemctl daemon-reload
    local s
    for s in "${svcs[@]}"; do
        systemctl enable "$s" >/dev/null 2>&1
        systemctl restart "$s"
        sleep 1
        if systemctl is-active --quiet "$s"; then ok "$s activo"
        else fail "$s no arrancó → journalctl -u $s -n 20"; fi
    done
}

free_port53() {
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        mkdir -p /etc/systemd/resolved.conf.d
        printf "[Resolve]\nDNSStubListener=no\n" > /etc/systemd/resolved.conf.d/titoflow.conf
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        systemctl restart systemd-resolved
    fi
    command -v ufw >/dev/null && ufw status | grep -q active && ufw allow 53/udp >/dev/null 2>&1
    ok "Puerto 53/UDP liberado"
}

setup_ssh() {
    mkdir -p /etc/ssh/sshd_config.d
    grep -qiE '^Include.*sshd_config\.d' /etc/ssh/sshd_config || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
    cat > /etc/ssh/sshd_config.d/00-titoflow.conf <<'EOF'
PasswordAuthentication yes
UsePAM yes
AllowTcpForwarding yes
EOF
    grep -q pam_limits.so /etc/pam.d/sshd || echo "session required pam_limits.so" >> /etc/pam.d/sshd
    if sshd -t 2>/dev/null; then
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
        ok "SSH preparado (password + límite de sesiones PAM)"
    else
        warn "sshd -t reportó errores; revisa /etc/ssh/sshd_config"
    fi
}

install_all() {
    clear; echo "${BGC}        ⚡  INSTALANDO TITOFLOW DATA CENTER  ⚡        ${N}"; echo
    load_conf
    if [[ -z $DOMAIN ]]; then
        read -rp "  Dominio base (ej. tudominio.com): " DOMAIN
        [[ -z $DOMAIN ]] && { fail "Necesito el dominio"; return 1; }
    fi
    echo "  ${Y}[*] Instalando dependencias...${N}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq curl openssl python3 cron procps iproute2 >/dev/null 2>&1
    ok "Dependencias listas"

    mkdir -p "$CONF_DIR" "$KEY_DIR" "$BIN_DIR"; touch "$DB"
    SERVER_IP=$(get_ip); save_conf

    echo "  ${Y}[*] Descargando motores desde TU repo...${N}"
    if ! fetch_all_engines; then
        fail "No pude bajar ningún motor. Revisa REPO_BIN al inicio del script."
        return 1
    fi
    # Si existía el instalador ajeno (slipgate), se apaga: ocupa el puerto 53
    local u
    for u in $(systemctl list-unit-files --no-legend 'slipgate-*' 2>/dev/null | awk '{print $1}'); do
        systemctl disable --now "$u" >/dev/null 2>&1
    done
    free_port53
    gen_keys
    setup_ssh
    apply_services
    echo "*/15 * * * * root $SELF --cleanup >/dev/null 2>&1" > /etc/cron.d/titoflow
    echo
    ok "Instalación terminada. Abre el panel con:  ${W}titoflow${N}"
    echo
    echo "  ${Y}Registros DNS que debes tener en tu dominio:${N}"
    echo "    ns.${DOMAIN}   A    ${SERVER_IP}"
    echo "    vs.${DOMAIN}   NS   ns.${DOMAIN}"
    echo "    ts.${DOMAIN}   NS   ns.${DOMAIN}"
    echo "    ss.${DOMAIN}   NS   ns.${DOMAIN}"
    echo
    pause
}

restart_tunnels() {
    local s
    for s in dnstt vaydns slipstream dnsrouter; do
        [[ -f /etc/systemd/system/titoflow-$s.service ]] && systemctl restart "titoflow-$s" 2>/dev/null
    done
    ok "Túneles reiniciados"; sleep 1
}

settings_menu() {
    clear; echo "${BGC}        ⚙  AJUSTES        ${N}"; echo
    load_conf
    echo "  1) Dominio base : ${W}$DOMAIN${N}"
    echo "  2) MTU          : ${W}$MTU${N}"
    echo "  3) Puerto SSH destino (22 / 2222 de tu panel): ${W}$TARGET_PORT${N}"
    echo "  0) Volver"
    read -rp "  Opción: " o
    case $o in
        1) read -rp "  Nuevo dominio: " v; [[ -n $v ]] && DOMAIN=$v ;;
        2) read -rp "  Nuevo MTU: " v; [[ $v =~ ^[0-9]+$ ]] && MTU=$v ;;
        3) read -rp "  Nuevo puerto: " v; [[ $v =~ ^[0-9]+$ ]] && TARGET_PORT=$v ;;
        *) return ;;
    esac
    save_conf; apply_services; pause
}

engines_menu() {
    clear; echo "${BGC}        🛠  MOTORES        ${N}"; echo
    load_conf
    fetch_all_engines
    gen_keys
    apply_services
    pause
}

update_script() {
    if curl -fsSL --max-time 30 "$REPO_SCRIPT" -o /tmp/titoflow.new && bash -n /tmp/titoflow.new; then
        install -m 755 /tmp/titoflow.new "$SELF"; ok "Script actualizado. Vuelve a abrir: titoflow"; exit 0
    else
        fail "No se pudo actualizar (revisa REPO_SCRIPT)"; pause
    fi
}

# ══════════════════════════ ENTRADA ══════════════════════════
if [[ $1 == "--cleanup" ]]; then load_conf; cleanup; exit 0; fi

# Autoinstalar el comando global
if [[ "$0" != "$SELF" ]]; then
    if [[ -f "$0" && -r "$0" ]]; then install -m 755 "$0" "$SELF"
    else curl -fsSL "$REPO_SCRIPT" -o "$SELF" 2>/dev/null && chmod +x "$SELF"; fi
fi

load_conf
[[ ! -f $CONF || -z $DOMAIN ]] && install_all

while true; do
    dashboard
    read -rp " ${W}► Opción : ${N}" op
    case $op in
        1|01) add_client ;;
        2|02) add_manual ;;
        3|03) add_bulk ;;
        4|04) list_clients ;;
        5|05) edit_client ;;
        6|06) renew_client ;;
        7|07) toggle_client ;;
        8|08) delete_client ;;
        9|09) purge_expired ;;
        10) link_menu ;;
        11) restart_tunnels ;;
        12) settings_menu ;;
        13) engines_menu ;;
        14) update_script ;;
        0|00) clear; exit 0 ;;
    esac
done
