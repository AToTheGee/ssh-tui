#!/usr/bin/env bash
# ============================================================
#
#  _______ _______ ___ ___         _______ ___ ___ ___ 
# |   _   |   _   |   Y   | ______ |       |   Y   |   |
# |   1___|   1___|.  1   | ______ |.|   | |.  |   |.  |
# |____   |____   |.  _   |        `-|.  |-|.  |   |.  |
# |:  1   |:  1   |:  |   |          |:  | |:  1   |:  |
# |::.. . |::.. . |::.|:. |          |::.| |::.. . |::.|
# `-------`-------`--- ---'          `---' `-------`---'
#              
#  SSH Key & Host Manager — Terminal UI für macOS & Linux
#  Version : 1.2.0  |  bash ≥ 3.2
#  Autor   : github.com/AToTheGee/ssh-tui
#  Aldo Giese 2026 .... ❤️ you EmJay
# ============================================================

set -uo pipefail   # kein -e: dialog/whiptail Cancel → exit 1, gezielt behandelt

# ── Locale sicherstellen (Pflicht fuer Emoji / UTF-8 Output) ─────────────────
# Wird vor allem in minimalen Server-Installationen (Ubuntu Server, Kali WSL)
# benoetigt, wo LANG nicht gesetzt oder nicht UTF-8 ist.
if [[ "${LANG:-}" != *UTF-8* && "${LC_ALL:-}" != *UTF-8* ]]; then
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
fi

# ── ANSI Farben & Stile ───────────────────────────────────────
R=$'\033[0m'
B=$'\033[1m'
DIM=$'\033[2m'
C_RED=$'\033[38;5;196m'
C_GRN=$'\033[38;5;82m'
C_YLW=$'\033[38;5;226m'
C_BLU=$'\033[38;5;39m'
C_CYN=$'\033[38;5;51m'
C_MAG=$'\033[38;5;213m'
C_ORG=$'\033[38;5;208m'
C_GRY=$'\033[38;5;240m'

# ── Konstanten ────────────────────────────────────────────────
readonly APP="ssh-tui"
readonly VERSION="1.2.0"
readonly OS="$(uname -s)"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
readonly CONFIG_DIR="${HOME}/.config/${APP}"
readonly CONFIG_FILE="${CONFIG_DIR}/config"
readonly SERVERS_FILE="${CONFIG_DIR}/servers.conf"
readonly AGENT_ENV_FILE="${CONFIG_DIR}/ssh-agent.env"

# ── Konfigurierbare Variablen ─────────────────────────────────
SSH_DIR="${HOME}/.ssh"
DEFAULT_USER="${USER:-$(id -un 2>/dev/null || echo 'user')}"
DEFAULT_HOST=""
KEY_PREFIX=""
KEY_SUFFIX=""
DEFAULT_KEY=""
AGENT_AUTOLOAD=""   # kommagetrennte Key-Namen für Auto-Load

TUI_TOOL=""

# ═══════════════════════════════════════════════════════════════
# HILFSFUNKTIONEN
# ═══════════════════════════════════════════════════════════════

# macOS-portables sed -i
sed_inplace() {
    if [[ "$OS" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << CONF
SSH_DIR="${SSH_DIR}"
DEFAULT_USER="${DEFAULT_USER}"
DEFAULT_HOST="${DEFAULT_HOST}"
KEY_PREFIX="${KEY_PREFIX}"
KEY_SUFFIX="${KEY_SUFFIX}"
DEFAULT_KEY="${DEFAULT_KEY}"
AGENT_AUTOLOAD="${AGENT_AUTOLOAD}"
CONF
    chmod 600 "$CONFIG_FILE"
}

expand_tilde() { echo "${1/#\~/$HOME}"; }

count_keys() {
    find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | wc -l | tr -d ' \t'
}

count_servers() {
    [[ -f "$SERVERS_FILE" ]] || { echo 0; return; }
    local c
    c=$(grep -v '^#\|^[[:space:]]*$' "$SERVERS_FILE" 2>/dev/null | wc -l | tr -d ' \t')
    echo "${c:-0}"
}

last_modified() {
    local f; f="$(ls -t "$SSH_DIR" 2>/dev/null | head -1)"
    [[ -z "$f" ]] && { echo "–"; return; }
    if [[ "$OS" == "Darwin" ]]; then
        stat -f "%Sm" -t "%d.%m.%Y %H:%M" "${SSH_DIR}/${f}" 2>/dev/null || echo "–"
    else
        stat -c "%y" "${SSH_DIR}/${f}" 2>/dev/null | \
            sed 's/\([0-9]\{4\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\) \([0-9]\{2\}:[0-9]\{2\}\).*/\3.\2.\1 \4/' \
            || echo "–"
    fi
}

# TUI-Wrapper – einheitlich für dialog & whiptail
tui() {
    local type="$1"; shift
    if [[ "$TUI_TOOL" == "dialog" ]]; then
        # --keep-tite: verhindert Wechsel in Alternate Screen Buffer (smcup/rmcup)
        # dadurch bleibt der Banner im Hintergrund sichtbar (wie in WSL/xterm)
        dialog --keep-tite --colors --backtitle "${APP} v${VERSION}" \
            --"$type" "$@" 3>&1 1>&2 2>&3
    else
        whiptail --"$type" "$@" 3>&1 1>&2 2>&3
    fi
}

# ═══════════════════════════════════════════════════════════════
# UNICODE / EMOJI DIAGNOSE
# ═══════════════════════════════════════════════════════════════

check_unicode_support() {
    local issues=() hints=()
    local cur_lang="${LANG:-}" cur_lc="${LC_ALL:-}"

    # 1. Locale UTF-8?
    if [[ "$cur_lang" != *UTF-8* && "$cur_lc" != *UTF-8* ]]; then
        issues+=("Keine UTF-8 Locale aktiv  (LANG=${cur_lang:-nicht gesetzt})")
        hints+=("sudo locale-gen en_US.UTF-8 && sudo update-locale LANG=en_US.UTF-8")
        hints+=("Oder temporaer fuer diese Session: export LANG=C.UTF-8 LC_ALL=C.UTF-8")
    fi

    # 2. locales-Paket vorhanden?
    if command -v locale &>/dev/null; then
        if ! locale -a 2>/dev/null | grep -qi 'utf'; then
            issues+=("Keine UTF-8-Locales generiert")
            hints+=("sudo apt-get install -y locales && sudo locale-gen en_US.UTF-8")
        fi
    fi

    # 3. Noto Emoji Font (relevant fuer Sixel/grafische Terminals)
    if command -v fc-list &>/dev/null; then
        if ! fc-list 2>/dev/null | grep -qi 'noto.*emoji\|emoji'; then
            issues+=("Keine Emoji-Schrift installiert (optional, relevant nur fuer GUI-Terminals)")
            hints+=("sudo apt-get install -y fonts-noto-color-emoji")
        fi
    fi

    [[ ${#issues[@]} -eq 0 ]] && return 0

    echo ""
    echo -e "${C_YLW}${B}  ╔══════════════════════════════════════════════════════════╗${R}"
    echo -e "${C_YLW}${B}  ║  ⚠   Unicode/Emoji-Unterstuetzung eingeschraenkt        ║${R}"
    echo -e "${C_YLW}${B}  ╚══════════════════════════════════════════════════════════╝${R}"
    echo ""
    for issue in "${issues[@]}"; do
        echo -e "  ${C_YLW}•${R} $issue"
    done
    echo ""
    echo -e "  ${C_CYN}${B}Empfohlene Befehle fuer Ubuntu/Debian/Kali:${R}"
    echo ""
    echo -e "  ${C_GRY}# 1. Locale-Paket + UTF-8 einrichten${R}"
    echo -e "  ${C_GRN}sudo apt-get update && sudo apt-get install -y locales${R}"
    echo -e "  ${C_GRN}sudo locale-gen en_US.UTF-8${R}"
    echo -e "  ${C_GRN}sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8${R}"
    echo ""
    echo -e "  ${C_GRY}# 2. Emoji-Font (optional, fuer Sixel/GUI-Terminals)${R}"
    echo -e "  ${C_GRN}sudo apt-get install -y fonts-noto-color-emoji fontconfig${R}"
    echo -e "  ${C_GRN}sudo fc-cache -fv${R}"
    echo ""
    echo -e "  ${C_GRY}# 3. Locale sofort fuer aktuelle Session aktivieren${R}"
    echo -e "  ${C_GRN}export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8${R}"
    echo ""
    echo -e "  ${C_GRY}# 4. Fuer WSL: In /etc/wsl.conf sicherstellen:${R}"
    echo -e "  ${C_GRN}[interop]${R}"
    echo -e "  ${C_GRN}appendWindowsPath = true${R}"
    echo ""
    echo -ne "  ${C_CYN}Weiter trotzdem starten? [j/N]: ${R}"
    local ans; read -r ans
    [[ "$ans" =~ ^[jJyY]$ ]] || exit 0
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# ABHÄNGIGKEITEN
# ═══════════════════════════════════════════════════════════════

check_dependencies() {
    local missing=()
    for tool in ssh ssh-keygen; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done

    if command -v dialog &>/dev/null; then
        TUI_TOOL="dialog"
    elif command -v whiptail &>/dev/null; then
        TUI_TOOL="whiptail"
    else
        missing+=("dialog")
    fi

    # Emoji-/Unicode-Unterstützung prüfen und Hinweis ausgeben
    check_unicode_support

    [[ ${#missing[@]} -eq 0 ]] && return 0

    echo ""
    echo -e "${C_ORG}${B}  ╔══════════════════════════════════════════╗${R}"
    echo -e "${C_ORG}${B}  ║  ⚠   Fehlende Abhängigkeiten             ║${R}"
    echo -e "${C_ORG}${B}  ╚══════════════════════════════════════════╝${R}"
    echo ""
    for m in "${missing[@]}"; do echo -e "    ${C_YLW}📦  ${m}${R}"; done
    echo ""

    local pkg_mgr
    pkg_mgr="$(detect_pkg_manager)" || {
        echo -e "${C_RED}  Kein unterstützter Paketmanager gefunden.${R}"
        echo -e "${C_GRY}  Bitte manuell installieren: ${missing[*]}${R}"
        exit 1
    }

    echo -ne "  ${C_CYN}❓ Jetzt automatisch installieren? [j/N]: ${R}"
    local ans; read -r ans
    if [[ "$ans" =~ ^[jJyY]$ ]]; then
        install_packages "$pkg_mgr" "${missing[@]}"
    else
        echo -e "\n  ${C_RED}Abbruch. Bitte Abhängigkeiten manuell installieren.${R}\n"
        exit 1
    fi
}

detect_pkg_manager() {
    if [[ "$OS" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then echo "brew"; return; fi
        echo -e "\n  ${C_CYN}💡 Homebrew nicht gefunden.${R}" >&2
        echo -e "  ${C_GRY}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${R}\n" >&2
        return 1
    fi
    command -v apt-get &>/dev/null && echo "apt"    && return
    command -v dnf     &>/dev/null && echo "dnf"    && return
    command -v pacman  &>/dev/null && echo "pacman" && return
    command -v zypper  &>/dev/null && echo "zypper" && return
    return 1
}

install_packages() {
    local mgr="$1"; shift
    echo ""
    for pkg in "$@"; do
        echo -e "  ${C_BLU}📦 Installiere ${B}${pkg}${R}${C_BLU}...${R}"
        case "$mgr" in
            brew)   brew install "$pkg"               ;;
            apt)    sudo apt-get install -y "$pkg"    ;;
            dnf)    sudo dnf install -y "$pkg"        ;;
            pacman) sudo pacman -S --noconfirm "$pkg" ;;
            zypper) sudo zypper install -y "$pkg"     ;;
        esac
        echo -e "  ${C_GRN}✅ ${pkg} installiert.${R}"
    done
    echo ""
    command -v dialog   &>/dev/null && TUI_TOOL="dialog"   && return
    command -v whiptail &>/dev/null && TUI_TOOL="whiptail" && return
    echo -e "  ${C_RED}TUI-Tool konnte nicht installiert werden.${R}"; exit 1
}

# ═══════════════════════════════════════════════════════════════
# SSH-AGENT
# ═══════════════════════════════════════════════════════════════

agent_load_env() {
    [[ -f "$AGENT_ENV_FILE" ]] || return 0
    # shellcheck source=/dev/null
    source "$AGENT_ENV_FILE" &>/dev/null || true
}

agent_is_running() {
    [[ -n "${SSH_AUTH_SOCK:-}" ]] || return 1
    ssh-add -l &>/dev/null
    local rc=$?
    [[ $rc -eq 0 || $rc -eq 1 ]]  # 0=Keys geladen, 1=Agent läuft aber leer
}

menu_agent() {
    while true; do
        local choice
        choice=$(tui menu "SSH-Agent" 18 86 6 \
            "1" "📊  $(printf '%-64s%s' 'Status anzeigen'           '[i]')" \
            "2" "🟢  $(printf '%-64s%s' 'Agent starten'             '[s]')" \
            "3" "➕  $(printf '%-64s%s' 'Key zum Agent hinzufuegen' '[a]')" \
            "4" "📋  $(printf '%-64s%s' 'Geladene Keys anzeigen'    '[l]')" \
            "5" "🔧  $(printf '%-64s%s' 'Auto-Load konfigurieren'   '[c]')" \
            "6" "🔴  $(printf '%-64s%s' 'Agent stoppen'             '[x]')" \
            "0" "    Zurueck") || return
        case "$choice" in
            1) agent_status          ;;
            2) agent_start           ;;
            3) agent_add_keys        ;;
            4) agent_list_keys       ;;
            5) agent_config_autoload ;;
            6) agent_stop            ;;
            0) return                ;;
        esac
    done
}

agent_status() {
    local tmpfile; tmpfile="$(mktemp)"
    {
        echo "  SSH-Agent Status"
        echo "  ════════════════════════════════════════════════════"
        echo ""
        if agent_is_running; then
            echo "  ✅  Agent aktiv"
            echo "  🔌  Socket : ${SSH_AUTH_SOCK:-–}"
            echo "  🆔  PID    : ${SSH_AGENT_PID:-–}"
            echo ""
            local key_list key_rc
            key_list=$(ssh-add -l 2>/dev/null); key_rc=$?
            echo "  Geladene Keys:"
            echo "  ──────────────────────────────────────────────────"
            if [[ $key_rc -eq 0 ]]; then
                echo "$key_list" | while read -r bits fp comment type; do
                    printf "  🔑  %-10s  %-48s  %s\n" \
                        "$(echo "$type" | tr -d '()')" "$fp" "$comment"
                done
            else
                echo "  (keine Keys geladen)"
            fi
        else
            echo "  ⛔  Agent nicht aktiv"
            echo ""
            echo "  Zum Starten: Option [2] wählen"
        fi
    } > "$tmpfile"
    tui textbox "$tmpfile" 22 70 || true
    rm -f "$tmpfile"
}

agent_start() {
    if agent_is_running; then
        tui msgbox "ℹ  SSH-Agent läuft bereits.\n\nPID: ${SSH_AGENT_PID:-unbekannt}" 8 50
        return
    fi
    mkdir -p "$CONFIG_DIR"
    ssh-agent -s > "$AGENT_ENV_FILE" 2>/dev/null
    chmod 600 "$AGENT_ENV_FILE"
    # shellcheck source=/dev/null
    source "$AGENT_ENV_FILE" &>/dev/null || true
    tui msgbox "✅ SSH-Agent gestartet!\n\nPID:    ${SSH_AGENT_PID:-–}\nSocket: ${SSH_AUTH_SOCK:-–}\n\n💡 Hinweis: Läuft nur in dieser Shell-Session.\nFür Persistenz → Option [5] Auto-Load." 14 64
}

agent_stop() {
    if ! agent_is_running; then
        tui msgbox "ℹ  Kein aktiver SSH-Agent gefunden." 6 46; return
    fi
    tui yesno "⏹  SSH-Agent stoppen?\n\nPID: ${SSH_AGENT_PID:-–}\n\nAlle geladenen Keys werden entladen." 10 54 || return
    ssh-agent -k &>/dev/null || true
    rm -f "$AGENT_ENV_FILE"
    unset SSH_AUTH_SOCK SSH_AGENT_PID 2>/dev/null || true
    tui msgbox "✅ SSH-Agent gestoppt." 6 40
}

agent_add_keys() {
    if ! agent_is_running; then
        tui yesno "⚠  SSH-Agent läuft nicht.\n\nJetzt starten?" 8 48 || return
        agent_start
        agent_is_running || return
    fi
    local items=()
    while IFS= read -r pub; do
        local name; name="$(basename "$pub" .pub)"
        [[ -f "${SSH_DIR}/${name}" ]] || continue
        local info fp type
        info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
        fp="$(echo "$info" | awk '{print $2}')"
        type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
        items+=("$name" "[${type}]  ${fp}")
    done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

    if [[ ${#items[@]} -eq 0 ]]; then
        tui msgbox "⚠  Keine privaten Keys in ${SSH_DIR} gefunden." 6 56; return
    fi
    local selected
    selected=$(tui menu "➕  Key zum Agent hinzufügen" 20 72 8 "${items[@]}") || return
    clear
    echo -e "\n  ${C_BLU}${B}➕ Lade Key '${selected}' in SSH-Agent...${R}\n"
    ssh-add "${SSH_DIR}/${selected}"
    echo -e "\n  ${C_GRY}Drücke Enter...${R}"; read -r
}

agent_list_keys() {
    if ! agent_is_running; then
        tui msgbox "⚠  SSH-Agent läuft nicht." 6 40; return
    fi
    local tmpfile; tmpfile="$(mktemp)"
    {
        echo "  Geladene Keys im SSH-Agent"
        echo "  ════════════════════════════════════════════════════════════"
        echo ""
        local key_list key_rc
        key_list=$(ssh-add -l 2>/dev/null); key_rc=$?
        if [[ $key_rc -eq 0 ]]; then
            printf "  %-12s  %-50s  %s\n" "Typ" "Fingerprint" "Kommentar"
            echo "  ────────────────────────────────────────────────────────────"
            echo "$key_list" | while read -r bits fp comment type; do
                printf "  %-12s  %-50s  %s\n" \
                    "$(echo "$type" | tr -d '()')" "$fp" "$comment"
            done
        else
            echo "  (keine Keys geladen)"
        fi
    } > "$tmpfile"
    tui textbox "$tmpfile" 22 74 || true
    rm -f "$tmpfile"
}

agent_config_autoload() {
    local current="${AGENT_AUTOLOAD:-}"
    local val
    val=$(tui inputbox \
        "⚙  Auto-Load Keys konfigurieren\n\nKommagetrennte Key-Namen die beim Start\nautomatisch geladen werden sollen.\n\nBeispiel: id_ed25519,work_rsa\n\nAktuell: ${current:-–}" \
        16 64 "$current") || return
    AGENT_AUTOLOAD="$val"
    save_config

    local shell_name; shell_name="$(basename "${SHELL:-bash}")"
    local profile_file
    case "$shell_name" in
        zsh)  profile_file="${HOME}/.zshrc" ;;
        fish) profile_file="${HOME}/.config/fish/config.fish" ;;
        *)    [[ "$OS" == "Darwin" ]] && profile_file="${HOME}/.bash_profile" \
                                      || profile_file="${HOME}/.bashrc" ;;
    esac

    tui msgbox \
        "✅ Auto-Load gespeichert.\n\nKonfigurierte Keys:\n  ${AGENT_AUTOLOAD:-–}\n\nFür automatisches Laden beim Shell-Start,\nfüge folgendes in ${profile_file} ein:\n\n  eval \"\$(ssh-agent -s)\"\n  ssh-add ${SSH_DIR}/<keyname>" \
        18 66
}

# ═══════════════════════════════════════════════════════════════
# ERSTER START / SETUP
# ═══════════════════════════════════════════════════════════════

first_run_setup() {
    clear
    echo ""
    echo -e "  ${C_MAG}${B}🔐 Willkommen bei ssh-tui v${VERSION}!${R}"
    echo -e "  ${C_GRY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"
    echo -e "  ${C_GRY}Erster Start — kurze Einrichtung erforderlich.${R}"
    echo ""

    local chosen_dir="${HOME}/.ssh"
    if [[ -d "${HOME}/.ssh" ]] && [[ -n "$(ls -A "${HOME}/.ssh" 2>/dev/null)" ]]; then
        local key_count host_count
        key_count=$(find "${HOME}/.ssh" -maxdepth 1 -name "*.pub" 2>/dev/null | wc -l | tr -d ' \t')
        host_count=0
        [[ -f "${HOME}/.ssh/known_hosts" ]] && \
            host_count=$(wc -l < "${HOME}/.ssh/known_hosts" | tr -d ' \t')
        echo -e "  ${C_GRN}✅ Vorhandener SSH-Ordner gefunden:${R} ${B}${HOME}/.ssh${R}"
        echo ""
        echo -e "  ${C_YLW}🔑${R}  SSH-Keys:       ${B}${key_count}${R}"
        echo -e "  ${C_CYN}🌐${R}  Bekannte Hosts: ${B}${host_count}${R}"
        echo ""
        echo -ne "  ${C_YLW}❓ Diesen Ordner verwenden? [J/n]: ${R}"
        local use_existing; read -r use_existing
        if [[ "$use_existing" =~ ^[nN]$ ]]; then
            echo -ne "  ${C_CYN}📁 Neuer Speicherort (Enter = ~/.ssh): ${R}"
            local custom_dir; read -r custom_dir
            chosen_dir="${custom_dir:-${HOME}/.ssh}"
        fi
    else
        echo -e "  ${C_CYN}📁 Kein SSH-Ordner unter ~/.ssh gefunden.${R}"
        echo -ne "\n  Speicherort eingeben (Enter = ~/.ssh): "
        local custom_dir; read -r custom_dir
        chosen_dir="${custom_dir:-${HOME}/.ssh}"
    fi

    SSH_DIR="$(expand_tilde "$chosen_dir")"
    mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
    mkdir -p "$CONFIG_DIR"
    touch "$SERVERS_FILE"
    DEFAULT_USER="${USER:-$(id -un 2>/dev/null || echo 'user')}"
    save_config

    echo ""
    echo -e "  ${C_GRN}✅ Konfiguration gespeichert:${R} ${C_GRY}${CONFIG_FILE}${R}"
    sleep 1
    list_keys_plain
}

list_keys_plain() {
    local found=0
    while IFS= read -r pub; do
        if [[ $found -eq 0 ]]; then
            clear; echo ""
            echo -e "  ${C_MAG}${B}🔑 Vorhandene SSH-Keys in ${SSH_DIR}${R}"
            echo ""
            echo -e "  ${C_GRY}┌──────────────────────────────────────────────────────────┐${R}"
        fi
        found=1
        local name info fp type
        name="$(basename "$pub" .pub)"
        info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
        fp="$(echo "$info" | awk '{print $2}')"
        type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
        echo -e "  ${C_GRY}│${R}  ${C_YLW}🔑${R}  ${B}${name}${R}  ${C_GRY}[${type}]${R}"
        echo -e "  ${C_GRY}│${R}     ${DIM}${fp}${R}"
        echo -e "  ${C_GRY}│${R}"
    done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)
    [[ $found -eq 0 ]] && return
    echo -e "  ${C_GRY}└──────────────────────────────────────────────────────────┘${R}"
    echo ""
    echo -e "  ${C_GRY}Drücke Enter zum Fortfahren...${R}"; read -r
}

# ═══════════════════════════════════════════════════════════════
# BANNER & DASHBOARD
# ═══════════════════════════════════════════════════════════════

show_banner() {
    clear
    local key_count srv_count last_mod hn un
    local sys_time sys_up sys_ip sys_os
    key_count="$(count_keys)"
    srv_count="$(count_servers)"
    last_mod="$(last_modified)"
    hn="$(hostname -s 2>/dev/null || hostname)"
    un="${DEFAULT_USER:-${USER:-'?'}}"

    # Systeminfos (OS-portabel)
    sys_time="$(date '+%d.%m.%Y %H:%M:%S' 2>/dev/null || echo '–')"
    if [[ "$OS" == "Darwin" ]]; then
        sys_os="macOS $(sw_vers -productVersion 2>/dev/null)"
        sys_up="$(uptime 2>/dev/null | sed 's/.*up \([^,]*\).*/\1/' | xargs || echo '–')"
        sys_ip="$(ipconfig getifaddr en0 2>/dev/null \
                  || ipconfig getifaddr en1 2>/dev/null || echo '–')"
    else
        sys_os="$(grep '^PRETTY_NAME' /etc/os-release 2>/dev/null \
                  | cut -d= -f2 | tr -d '"' || uname -sr)"
        sys_up="$(uptime -p 2>/dev/null | sed 's/^up //' \
                  || uptime 2>/dev/null | sed 's/.*up \([^,]*\).*/\1/' | xargs)"
        sys_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '–')"
    fi
    [[ -z "${sys_up:-}" ]] && sys_up="–"
    [[ -z "${sys_ip:-}" ]] && sys_ip="–"
    [[ -z "${sys_os:-}" ]] && sys_os="$(uname -sr)"

    echo -e "${C_BLU}${B}"
    cat << 'BANNER'                                                                                      
  _____ _____ __ __         ______  __ __  ____ 
 / ___// ___/|  T  T       |      T|  T  Tl    j
(   \_(   \_ |  l  | _____ |      ||  |  | |  T 
 \__  T\__  T|  _  ||     |l_j  l_j|  |  | |  | 
 /  \ |/  \ ||  |  |l_____j  |  |  |  :  | |  | 
 \    |\    ||  |  |         |  |  l     | j  l 
  \___j \___jl__j__j         l__j   \__,_j|____j
BANNER
    echo -e "${R}"
    echo -e "  ${C_GRY}SSH Key & Host Manager  —  Terminal UI fuer macOS & Linux  —  v${VERSION}${R}"
    echo ""
    echo -e "  ${C_GRY}══════════════════════════════════════════════════════════════════════${R}"
    printf "  ${C_CYN}Benutzer   ${R}${B}%-24s${R}  ${C_CYN}Host         ${R}${B}%s${R}\n" "$un" "$hn"
    printf "  ${C_YLW}Keys       ${R}${B}%-24s${R}  ${C_YLW}Geaendert    ${R}%s\n" "$key_count" "$last_mod"
    printf "  ${C_MAG}Server     ${R}${B}%-24s${R}  ${C_GRN}SSH-Dir      ${R}${C_GRY}%s${R}\n" "$srv_count" "$SSH_DIR"
    echo -e "  ${C_GRY}──────────────────────────────────────────────────────────────────────${R}"
    printf "  ${C_ORG}OS         ${R}%-30s  ${C_ORG}Kernel       ${R}%s\n" "${sys_os:0:28}" "$(uname -r 2>/dev/null | cut -d- -f1)"
    printf "  ${C_ORG}Uptime     ${R}%-30s  ${C_ORG}IP           ${R}%s\n" "${sys_up:0:28}" "$sys_ip"
    printf "  ${C_GRY}uname      ${R}%-30s  ${C_GRY}Zeit         ${R}%s\n" "$(uname -srm 2>/dev/null | cut -c1-28)" "$sys_time"
    echo -e "  ${C_GRY}══════════════════════════════════════════════════════════════════════${R}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# HAUPTMENÜ
# ═══════════════════════════════════════════════════════════════

menu_main() {
    while true; do
        show_banner
        local choice
        choice=$(tui menu "Hauptmenue" 20 86 8 \
            "1" "🔑  $(printf '%-64s%s' 'SSH-Keys verwalten'    '[k]')" \
            "2" "🖥  $(printf '%-64s%s' 'Server-Liste'          '[s]')" \
            "3" "🚀  $(printf '%-64s%s' 'Verbinden'             '[v]')" \
            "4" "✨  $(printf '%-64s%s' 'Neuen Key generieren'  '[g]')" \
            "5" "🌐  $(printf '%-64s%s' 'known_hosts verwalten' '[h]')" \
            "6" "🤖  $(printf '%-64s%s' 'SSH-Agent'             '[a]')" \
            "7" "🔧  $(printf '%-64s%s' 'Einstellungen'         '[e]')" \
            "0" "🚪  $(printf '%-64s%s' 'Beenden'               '[q]')") || break
        case "$choice" in
            1) menu_keys     ;;
            2) menu_servers  ;;
            3) menu_connect  ;;
            4) menu_generate ;;
            5) menu_hosts    ;;
            6) menu_agent    ;;
            7) menu_settings ;;
            0) break         ;;
        esac
    done
    clear
    echo -e "\n  ${C_GRN}${B}👋 Auf Wiedersehen!${R}\n"
}

# ═══════════════════════════════════════════════════════════════
# SSH-KEYS VERWALTEN
# ═══════════════════════════════════════════════════════════════

menu_keys() {
    while true; do
        local choice
        choice=$(tui menu "SSH-Keys verwalten" 16 86 6 \
            "1" "📋  $(printf '%-64s%s' 'Alle Keys auflisten'     '[l]')" \
            "2" "🔍  $(printf '%-64s%s' 'Key pruefen / testen'    '[p]')" \
            "3" "📤  $(printf '%-64s%s' 'Key auf Server deployen' '[d]')" \
            "4" "📎  $(printf '%-64s%s' 'Public Key kopieren'     '[c]')" \
            "5" "🗑️  $(printf '%-64s%s' 'Key loeschen'            '[x]')" \
            "0" "    Zurueck") || return
        case "$choice" in
            1) show_key_list_dialog ;;
            2) verify_key           ;;
            3) deploy_key           ;;
            4) copy_public_key      ;;
            5) delete_key           ;;
            0) return               ;;
        esac
    done
}

show_key_list_dialog() {
    local tmpfile; tmpfile="$(mktemp)"
    {
        printf "  %-28s %-12s %s\n" "Name" "Typ" "Fingerprint"
        echo "  ──────────────────────────────────────────────────────────────────────"
        local found=0
        while IFS= read -r pub; do
            found=1
            local name info fp type
            name="$(basename "$pub" .pub)"
            info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
            fp="$(echo "$info" | awk '{print $2}')"
            type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
            printf "  🔑  %-24s %-12s %s\n" "$name" "$type" "$fp"
        done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)
        [[ $found -eq 0 ]] && echo "  (Keine Keys in ${SSH_DIR})"
    } > "$tmpfile"
    tui textbox "$tmpfile" 22 78 || true
    rm -f "$tmpfile"
}

# Interne Hilfsfunktion: Key aus Liste wählen
_pick_key() {
    local title="${1:-🔑  Key wählen}"
    local items=()
    while IFS= read -r pub; do
        local name info fp type
        name="$(basename "$pub" .pub)"
        info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
        fp="$(echo "$info" | awk '{print $2}')"
        type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
        items+=("$name" "[${type}]  ${fp}")
    done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)
    if [[ ${#items[@]} -eq 0 ]]; then
        tui msgbox "⚠  Keine SSH-Keys in ${SSH_DIR} gefunden." 6 54; return 1
    fi
    tui menu "$title" 20 74 8 "${items[@]}"
}

verify_key() {
    local selected; selected=$(_pick_key "✅  Key prüfen / testen") || return
    local pub="${SSH_DIR}/${selected}.pub"
    local priv="${SSH_DIR}/${selected}"
    local tmpfile; tmpfile="$(mktemp)"
    {
        echo "  Key-Prüfung: ${selected}"
        echo "  ══════════════════════════════════════════════════════"
        echo ""
        local info; info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
        if [[ -n "$info" ]]; then
            echo "  ✅  Public Key lesbar"
            printf "  %-14s %s\n" "Bits:"         "$(echo "$info" | awk '{print $1}')"
            printf "  %-14s %s\n" "Fingerprint:"  "$(echo "$info" | awk '{print $2}')"
            printf "  %-14s %s\n" "Kommentar:"    "$(echo "$info" | awk '{print $3}')"
            printf "  %-14s %s\n" "Typ:"          "$(echo "$info" | awk '{print $NF}' | tr -d '()')"
        else
            echo "  ❌  Public Key nicht lesbar"
        fi
        echo ""
        if [[ -f "$priv" ]]; then
            local perms
            if [[ "$OS" == "Darwin" ]]; then
                perms=$(stat -f "%Lp" "$priv" 2>/dev/null)
            else
                perms=$(stat -c "%a" "$priv" 2>/dev/null)
            fi
            echo "  ✅  Privater Key vorhanden"
            printf "  %-14s %s\n" "Rechte:" "${perms}"
            [[ "$perms" != "600" ]] && echo "  ⚠   Empfehlung: chmod 600 ${priv}"
        else
            echo "  ⚠   Kein privater Key gefunden"
        fi
    } > "$tmpfile"
    tui textbox "$tmpfile" 20 64 || true
    rm -f "$tmpfile"

    # Berechtigungen reparieren
    if [[ -f "$priv" ]]; then
        local perms
        if [[ "$OS" == "Darwin" ]]; then
            perms=$(stat -f "%Lp" "$priv" 2>/dev/null)
        else
            perms=$(stat -c "%a" "$priv" 2>/dev/null)
        fi
        if [[ "$perms" != "600" ]]; then
            tui yesno "⚠  Berechtigungen jetzt korrigieren?\n\nchmod 600 ${priv}" 9 60 && \
                chmod 600 "$priv" && \
                tui msgbox "✅ Berechtigungen auf 600 gesetzt." 6 44
        fi
    fi

    # Optionaler Verbindungstest
    tui yesno "🧪  Verbindungstest mit diesem Key durchführen?" 8 54 || return
    local test_host
    test_host=$(tui inputbox \
        "🧪  Verbindungstest\n\nZiel (user@host):" 9 56 \
        "${DEFAULT_USER:-}${DEFAULT_HOST:+@${DEFAULT_HOST}}") || return
    [[ -z "$test_host" ]] && return
    clear
    echo -e "\n  ${C_BLU}${B}🧪 Teste Verbindung zu ${test_host} mit '${selected}'...${R}\n"
    if ssh -i "$priv" \
           -o BatchMode=yes \
           -o ConnectTimeout=8 \
           -o StrictHostKeyChecking=accept-new \
           "$test_host" "echo '✅ Verbindung erfolgreich!'" 2>&1; then
        echo -e "\n  ${C_GRN}${B}✅ Test bestanden.${R}"
    else
        echo -e "\n  ${C_RED}${B}❌ Verbindung fehlgeschlagen.${R}"
    fi
    echo -e "\n  ${C_GRY}Drücke Enter...${R}"; read -r
}

deploy_key() {
    local selected; selected=$(_pick_key "🚀  Key deployen — Key wählen") || return
    local pub_content; pub_content="$(cat "${SSH_DIR}/${selected}.pub" 2>/dev/null)"
    [[ -z "$pub_content" ]] && { tui msgbox "❌ Public Key nicht lesbar." 6 42; return; }

    local target=""
    # Server aus Liste anbieten, falls vorhanden
    if [[ -f "$SERVERS_FILE" ]] && \
       grep -q -v '^#\|^[[:space:]]*$' "$SERVERS_FILE" 2>/dev/null; then
        local srv_items=("0" "✏   Manuell eingeben")
        while IFS='|' read -r name user host port desc; do
            [[ "$name" =~ ^#|^[[:space:]]*$ ]] && continue
            srv_items+=("$name" "🖥  ${user}@${host}:${port}  ${desc}")
        done < <(grep -v '^#\|^[[:space:]]*$' "$SERVERS_FILE" 2>/dev/null)
        local srv_choice
        srv_choice=$(tui menu "🚀  Deploy-Ziel wählen" 20 70 8 "${srv_items[@]}") || return
        if [[ "$srv_choice" != "0" ]]; then
            while IFS='|' read -r name user host port desc; do
                [[ "$name" == "$srv_choice" ]] && target="${user}@${host}" && break
            done < <(grep -v '^#\|^[[:space:]]*$' "$SERVERS_FILE" 2>/dev/null)
        fi
    fi

    if [[ -z "$target" ]]; then
        target=$(tui inputbox \
            "🚀  Key deployen\n\nZiel-Host (user@host):" 9 58 \
            "${DEFAULT_USER:-}${DEFAULT_HOST:+@${DEFAULT_HOST}}") || return
    fi
    [[ -z "$target" ]] && return

    tui yesno \
        "🚀  Key deployen?\n\n  Key:    ${selected}.pub\n  Ziel:   ${target}\n\n  Methode: ssh-copy-id (Fallback: manuell)" \
        12 62 || return

    clear
    echo -e "\n  ${C_BLU}${B}🚀 Deploye '${selected}.pub' auf ${target}...${R}\n"
    if command -v ssh-copy-id &>/dev/null; then
        ssh-copy-id -i "${SSH_DIR}/${selected}.pub" "$target"
    else
        # Manueller Fallback ohne eval
        echo "$pub_content" | ssh "$target" \
            'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
    fi
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        echo -e "\n  ${C_GRN}${B}✅ Key erfolgreich deployt!${R}"
    else
        echo -e "\n  ${C_RED}${B}❌ Deploy fehlgeschlagen (Exit: ${rc}).${R}"
    fi
    echo -e "\n  ${C_GRY}Drücke Enter...${R}"; read -r
}

copy_public_key() {
    local selected; selected=$(_pick_key "📤  Public Key kopieren") || return
    local pub_content; pub_content="$(cat "${SSH_DIR}/${selected}.pub")"

    if [[ "$OS" == "Darwin" ]]; then
        echo "$pub_content" | pbcopy
        tui msgbox "✅ Public Key '${selected}' in Zwischenablage kopiert!" 7 62
    elif command -v xclip &>/dev/null; then
        echo "$pub_content" | xclip -selection clipboard
        tui msgbox "✅ Public Key '${selected}' in Zwischenablage kopiert!" 7 62
    elif command -v xsel &>/dev/null; then
        echo "$pub_content" | xsel --clipboard --input
        tui msgbox "✅ Public Key '${selected}' in Zwischenablage kopiert!" 7 62
    else
        local tmpfile; tmpfile="$(mktemp)"
        echo "$pub_content" > "$tmpfile"
        tui msgbox "ℹ  Kein Clipboard-Tool (xclip/xsel) gefunden.\nKey wird angezeigt:" 8 56 || true
        tui textbox "$tmpfile" 10 80 || true
        rm -f "$tmpfile"
    fi
}

delete_key() {
    local selected; selected=$(_pick_key "🗑  Key löschen") || return
    tui yesno \
        "🗑  Key '${selected}' wirklich löschen?\n\nEntfernt werden:\n  • ${selected}\n  • ${selected}.pub" \
        11 56 || return
    rm -f "${SSH_DIR}/${selected}" "${SSH_DIR}/${selected}.pub"
    tui msgbox "✅ Key '${selected}' gelöscht." 6 46
}

# ═══════════════════════════════════════════════════════════════
# SERVER-LISTE
# Format: name|user|host|port|beschreibung
# ═══════════════════════════════════════════════════════════════

servers_get_all() {
    [[ -f "$SERVERS_FILE" ]] || return
    grep -v '^#\|^[[:space:]]*$' "$SERVERS_FILE" 2>/dev/null || true
}

menu_servers() {
    while true; do
        local count; count="$(count_servers)"
        local choice
        choice=$(tui menu "Server-Liste  (${count} Eintraege)" 16 86 5 \
            "1" "📋  $(printf '%-64s%s' 'Alle Server anzeigen' '[l]')" \
            "2" "➕  $(printf '%-64s%s' 'Server hinzufuegen'   '[n]')" \
            "3" "📝  $(printf '%-64s%s' 'Server bearbeiten'    '[e]')" \
            "4" "🗑️  $(printf '%-64s%s' 'Server loeschen'      '[x]')" \
            "0" "    Zurueck") || return
        case "$choice" in
            1) show_server_list ;;
            2) add_server       ;;
            3) edit_server      ;;
            4) delete_server    ;;
            0) return           ;;
        esac
    done
}

show_server_list() {
    local tmpfile; tmpfile="$(mktemp)"
    {
        printf "  %-18s %-26s %-6s %s\n" "Name" "Benutzer@Host" "Port" "Beschreibung"
        echo "  ──────────────────────────────────────────────────────────────────────────"
        local found=0
        while IFS='|' read -r name user host port desc; do
            [[ "$name" =~ ^#|^[[:space:]]*$ ]] && continue
            found=1
            printf "  🖥  %-14s %-26s %-6s %s\n" "$name" "${user}@${host}" "$port" "$desc"
        done < <(servers_get_all)
        [[ $found -eq 0 ]] && echo "  (Keine Server gespeichert)"
    } > "$tmpfile"
    tui textbox "$tmpfile" 22 78 || true
    rm -f "$tmpfile"
}

_pick_server() {
    local title="${1:-🖥  Server wählen}"
    local items=()
    while IFS='|' read -r name user host port desc; do
        [[ "$name" =~ ^#|^[[:space:]]*$ ]] && continue
        items+=("$name" "🖥  ${user}@${host}:${port}  ${desc}")
    done < <(servers_get_all)
    if [[ ${#items[@]} -eq 0 ]]; then
        tui msgbox "⚠  Keine Server gespeichert.\nBitte zuerst einen Server hinzufügen." 8 54
        return 1
    fi
    tui menu "$title" 20 72 8 "${items[@]}"
}

add_server() {
    local name user host port desc
    name=$(tui inputbox "➕  Server hinzufügen\n\nName (z.B. 'webserver', 'pi-home'):" 9 58 "") || return
    [[ -z "$name" ]] && return
    name="${name//|/}"
    user=$(tui inputbox "➕  Server hinzufügen\n\nBenutzer:" 9 52 "$DEFAULT_USER") || return
    user="${user//|/}"
    host=$(tui inputbox "➕  Server hinzufügen\n\nHostname oder IP-Adresse:" 9 58 "${DEFAULT_HOST:-}") || return
    [[ -z "$host" ]] && return
    host="${host//|/}"
    port=$(tui inputbox "➕  Server hinzufügen\n\nPort:" 9 48 "22") || return
    [[ -z "$port" ]] && port="22"
    port="${port//|/}"
    desc=$(tui inputbox "➕  Server hinzufügen\n\nBeschreibung (optional):" 9 60 "") || return
    desc="${desc//|/}"

    mkdir -p "$CONFIG_DIR"
    echo "${name}|${user}|${host}|${port}|${desc}" >> "$SERVERS_FILE"
    tui msgbox "✅ Server '${name}' gespeichert." 6 46
}

edit_server() {
    local selected; selected=$(_pick_server "✏   Server bearbeiten") || return
    local line; line=$(grep "^${selected}|" "$SERVERS_FILE" 2>/dev/null | head -1)
    local cur_name cur_user cur_host cur_port cur_desc
    IFS='|' read -r cur_name cur_user cur_host cur_port cur_desc <<< "$line"

    local user host port desc
    user=$(tui inputbox "✏  Bearbeiten: ${selected}\n\nBenutzer:" 9 54 "$cur_user") || return
    host=$(tui inputbox "✏  Bearbeiten: ${selected}\n\nHostname oder IP:" 9 58 "$cur_host") || return
    port=$(tui inputbox "✏  Bearbeiten: ${selected}\n\nPort:" 9 48 "$cur_port") || return
    desc=$(tui inputbox "✏  Bearbeiten: ${selected}\n\nBeschreibung:" 9 60 "$cur_desc") || return
    user="${user//|/}"; host="${host//|/}"; port="${port//|/}"; desc="${desc//|/}"

    sed_inplace "/^${selected}|/d" "$SERVERS_FILE"
    echo "${selected}|${user}|${host}|${port}|${desc}" >> "$SERVERS_FILE"
    tui msgbox "✅ Server '${selected}' aktualisiert." 6 50
}

delete_server() {
    local selected; selected=$(_pick_server "🗑  Server löschen") || return
    tui yesno "🗑  Server '${selected}' wirklich löschen?" 8 52 || return
    sed_inplace "/^${selected}|/d" "$SERVERS_FILE"
    tui msgbox "✅ Server '${selected}' gelöscht." 6 46
}

# ═══════════════════════════════════════════════════════════════
# VERBINDEN
# ═══════════════════════════════════════════════════════════════

menu_connect() {
    local conn_user="" conn_host="" conn_port="22"

    # Server-Liste anbieten wenn vorhanden
    if [[ -f "$SERVERS_FILE" ]] && \
       grep -q -v '^#\|^[[:space:]]*$' "$SERVERS_FILE" 2>/dev/null; then
        local src
        src=$(tui menu "Verbinden" 12 86 3 \
            "1" "🖥  $(printf '%-64s%s' 'Aus Server-Liste waehlen' '[l]')" \
            "2" "📝  $(printf '%-64s%s' 'Manuell eingeben'         '[m]')" \
            "0" "    Zurueck") || return
        case "$src" in
            1)
                local srv; srv=$(_pick_server "🚀  Server zum Verbinden wählen") || return
                while IFS='|' read -r name user host port desc; do
                    [[ "$name" == "$srv" ]] && \
                        conn_user="$user" conn_host="$host" conn_port="$port" && break
                done < <(servers_get_all)
                ;;
            2) ;; # → manuelle Eingabe unten
            0) return ;;
        esac
    fi

    if [[ -z "$conn_host" ]]; then
        local default_target="${DEFAULT_USER:-}${DEFAULT_HOST:+@${DEFAULT_HOST}}"
        local manual
        manual=$(tui inputbox "🚀  Verbinden\n\nZiel (user@host):" 9 58 "$default_target") || return
        [[ -z "$manual" ]] && return
        if [[ "$manual" == *@* ]]; then
            conn_user="${manual%%@*}"; conn_host="${manual##*@}"
        else
            conn_host="$manual"; conn_user="${DEFAULT_USER:-}"
        fi
    fi

    # Key-Auswahl
    local key_items=("0" "(Systemstandard / ~/.ssh/config)")
    while IFS= read -r pub; do
        local name info type
        name="$(basename "$pub" .pub)"
        info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
        type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
        key_items+=("$name" "[${type}]")
    done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)
    local key_choice
    key_choice=$(tui menu "🔑  Key für Verbindung wählen" 18 64 8 "${key_items[@]}") || return

    clear
    local target="${conn_user:+${conn_user}@}${conn_host}"
    echo -e "\n  ${C_GRN}${B}🚀 Verbinde mit ${target}:${conn_port}...${R}\n"
    local ssh_opts=("-p" "$conn_port")
    [[ "$key_choice" != "0" ]] && ssh_opts+=("-i" "${SSH_DIR}/${key_choice}")
    ssh "${ssh_opts[@]}" "$target"
    echo -e "\n  ${C_GRY}Verbindung beendet. Drücke Enter...${R}"; read -r
}

# ═══════════════════════════════════════════════════════════════
# KEY GENERIEREN
# ═══════════════════════════════════════════════════════════════

menu_generate() {
    local key_type
    key_type=$(tui menu "Key-Typ waehlen" 14 86 4 \
        "ed25519" "🔐  $(printf '%-64s' 'Ed25519   -- modern, kompakt, empfohlen')" \
        "rsa"     "🔑  $(printf '%-64s' 'RSA 4096  -- klassisch, weit verbreitet')" \
        "ecdsa"   "🔷  $(printf '%-64s' 'ECDSA     -- Elliptische Kurve (NIST)')" \
        "dsa"     "⛔  $(printf '%-64s' 'DSA       -- veraltet, nicht empfohlen')") || return

    local default_name="${KEY_PREFIX}${key_type}${KEY_SUFFIX}"
    local key_name
    key_name=$(tui inputbox "📝  Key-Name:" 8 56 "$default_name") || return
    [[ -z "$key_name" ]] && return

    if [[ -f "${SSH_DIR}/${key_name}" ]]; then
        tui yesno "⚠  Key '${key_name}' existiert bereits!\n\nÜberschreiben?" 9 52 || return
    fi

    local cur_user="${DEFAULT_USER:-${USER:-user}}"
    local cur_host; cur_host="$(hostname -s 2>/dev/null || hostname)"
    local key_comment
    key_comment=$(tui inputbox \
        "💬  Kommentar (z.B. E-Mail oder Beschreibung):" 8 62 \
        "${cur_user}@${cur_host}") || return

    local bits_flag=""
    [[ "$key_type" == "rsa"   ]] && bits_flag="-b 4096"
    [[ "$key_type" == "ecdsa" ]] && bits_flag="-b 521"

    tui yesno \
        "✨  Key generieren?\n\n  Typ:       ${key_type}\n  Name:      ${key_name}\n  Speichern: ${SSH_DIR}/${key_name}\n  Kommentar: ${key_comment}" \
        14 64 || return

    clear
    echo -e "\n  ${C_BLU}${B}✨ Generiere SSH-Key '${key_name}'...${R}\n"
    # shellcheck disable=SC2086
    ssh-keygen -t "$key_type" $bits_flag -C "$key_comment" -f "${SSH_DIR}/${key_name}"
    echo -e "\n  ${C_GRN}${B}✅ Key erfolgreich erstellt!${R}"
    echo -e "  ${C_GRY}Drücke Enter...${R}"; read -r
}

# ═══════════════════════════════════════════════════════════════
# KNOWN_HOSTS VERWALTEN
# ═══════════════════════════════════════════════════════════════

menu_hosts() {
    local hosts_file="${SSH_DIR}/known_hosts"
    while true; do
        local count=0
        [[ -f "$hosts_file" ]] && \
            count=$(grep -v '^#\|^[[:space:]]*$' "$hosts_file" 2>/dev/null | wc -l | tr -d ' \t')
        local choice
        choice=$(tui menu "known_hosts  (${count} Eintraege)" 14 86 3 \
            "1" "📋  $(printf '%-64s%s' 'Tabellarisch anzeigen' '[l]')" \
            "2" "🗑️  $(printf '%-64s%s' 'Eintrag entfernen'     '[x]')" \
            "0" "    Zurueck") || return
        case "$choice" in
            1) show_known_hosts_table "$hosts_file" ;;
            2) remove_known_host      "$hosts_file" ;;
            0) return ;;
        esac
    done
}

show_known_hosts_table() {
    local hosts_file="$1"
    if [[ ! -f "$hosts_file" ]]; then
        tui msgbox "ℹ  Keine known_hosts-Datei gefunden." 6 46; return
    fi
    local tmpfile; tmpfile="$(mktemp)"
    {
        printf "  %-38s %-20s %s\n" "Hostname" "Schlüssel-Typ" "Hinweis"
        echo "  ──────────────────────────────────────────────────────────────────────────"
        while IFS=' ' read -r host keytype key rest; do
            [[ "$host" =~ ^#|^[[:space:]]*$ ]] && continue
            local display_host="$host"
            local hinweis=""
            # Gehashte Hosts (SHA1-HMAC)
            if [[ "$host" == "|1|"* ]]; then
                display_host="[gehashed]"
                hinweis="sha1-hashed"
            # Mehrere Aliase (kommagetrennt)
            elif [[ "$host" == *,* ]]; then
                local alias_count
                alias_count=$(echo "$host" | tr ',' '\n' | wc -l | tr -d ' \t')
                display_host="${host%%,*}"
                hinweis="${alias_count} Aliase"
            fi
            # IP-Range / Wildcard
            [[ "$host" == *"*"* || "$host" == *"?"* ]] && hinweis="Wildcard"
            printf "  %-38s %-20s %s\n" "$display_host" "$keytype" "$hinweis"
        done < "$hosts_file"
    } > "$tmpfile"
    tui textbox "$tmpfile" 24 80 || true
    rm -f "$tmpfile"
}

remove_known_host() {
    local hosts_file="$1"
    local target
    target=$(tui inputbox \
        "🗑  Eintrag aus known_hosts entfernen\n\nHostname oder IP-Adresse:" \
        9 58 "") || return
    [[ -z "$target" ]] && return
    ssh-keygen -R "$target" 2>/dev/null || true
    tui msgbox "✅ Eintrag '${target}' entfernt." 6 50
}

# ═══════════════════════════════════════════════════════════════
# EINSTELLUNGEN
# ═══════════════════════════════════════════════════════════════

menu_settings() {
    while true; do
        local choice
        choice=$(tui menu "Einstellungen" 24 86 8 \
            "1" "👤  $(printf '%-40s%22s' 'Standard-Benutzer'   "[${DEFAULT_USER:--}]")" \
            "2" "🖥  $(printf '%-40s%22s' 'Standard-Host'       "[${DEFAULT_HOST:--}]")" \
            "3" "🏷  $(printf '%-40s%22s' 'Key-Praefix'         "[${KEY_PREFIX:--}]")" \
            "4" "🏷  $(printf '%-40s%22s' 'Key-Suffix'          "[${KEY_SUFFIX:--}]")" \
            "5" "📁  $(printf '%-40s%22s' 'SSH-Verzeichnis'     "[${SSH_DIR}]")" \
            "6" "🔑  $(printf '%-40s%22s' 'Standard-Key'        "[${DEFAULT_KEY:--}]")" \
            "7" "🔗  $(printf '%-40s%22s' 'Alias einrichten'    '[a]')" \
            "0" "    Zurueck") || return

        local val
        case "$choice" in
            1)
                val=$(tui inputbox \
                    "👤  Standard-Benutzername:\n\nWird als Vorauswahl beim Verbinden verwendet." \
                    10 60 "$DEFAULT_USER") || continue
                DEFAULT_USER="$val"; save_config
                tui msgbox "✅ Benutzername: '${DEFAULT_USER}'" 6 48 ;;
            2)
                val=$(tui inputbox \
                    "🖥   Standard-Hostname:\n\nWird als Vorauswahl beim Verbinden verwendet." \
                    10 60 "$DEFAULT_HOST") || continue
                DEFAULT_HOST="$val"; save_config
                tui msgbox "✅ Standard-Host: '${DEFAULT_HOST}'" 6 48 ;;
            3)
                val=$(tui inputbox \
                    "🏷  Key-Präfix:\n\nBeispiel: 'work_'  →  work_ed25519" \
                    10 56 "$KEY_PREFIX") || continue
                KEY_PREFIX="$val"; save_config
                tui msgbox "✅ Präfix: '${KEY_PREFIX:-leer}'" 6 44 ;;
            4)
                val=$(tui inputbox \
                    "🏷  Key-Suffix:\n\nBeispiel: '_2024'  →  ed25519_2024" \
                    10 56 "$KEY_SUFFIX") || continue
                KEY_SUFFIX="$val"; save_config
                tui msgbox "✅ Suffix: '${KEY_SUFFIX:-leer}'" 6 44 ;;
            5)
                val=$(tui inputbox \
                    "📁  SSH-Verzeichnis:\n\nAbsoluter Pfad oder ~ für Home.\nAktuell: ${SSH_DIR}" \
                    12 64 "$SSH_DIR") || continue
                local new_dir; new_dir="$(expand_tilde "$val")"
                if mkdir -p "$new_dir" 2>/dev/null; then
                    chmod 700 "$new_dir"; SSH_DIR="$new_dir"; save_config
                    tui msgbox "✅ SSH-Verzeichnis:\n${SSH_DIR}" 8 60
                else
                    tui msgbox "⚠  Verzeichnis konnte nicht erstellt werden:\n${new_dir}" 8 60
                fi ;;
            6)
                local items=("keine" "— kein Standard-Key —")
                while IFS= read -r pub; do
                    local info type
                    info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
                    type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
                    items+=("$(basename "$pub" .pub)" "[$type]")
                done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)
                val=$(tui menu "🔑  Standard-Key wählen" 20 64 8 "${items[@]}") || continue
                [[ "$val" == "keine" ]] && val=""
                DEFAULT_KEY="$val"; save_config
                tui msgbox "✅ Standard-Key: '${DEFAULT_KEY:-nicht gesetzt}'" 6 54 ;;
            7) setup_alias ;;
            0) return ;;
        esac
    done
}

setup_alias() {
    local shell_name; shell_name="$(basename "${SHELL:-bash}")"

    # Shell-spezifische Profil-Datei ermitteln (Best Practice je OS/Shell)
    local profile_file
    case "$shell_name" in
        zsh)
            profile_file="${HOME}/.zshrc" ;;
        fish)
            profile_file="${HOME}/.config/fish/config.fish" ;;
        bash)
            if [[ "$OS" == "Darwin" ]]; then
                # macOS: bash liest .bash_profile beim Login
                if [[ -f "${HOME}/.bashrc" && ! -f "${HOME}/.bash_profile" ]]; then
                    profile_file="${HOME}/.bashrc"
                else
                    profile_file="${HOME}/.bash_profile"
                fi
            else
                profile_file="${HOME}/.bashrc"
            fi ;;
        *)
            profile_file="${HOME}/.profile" ;;
    esac

    local alias_name
    alias_name=$(tui inputbox \
        "🔗  Alias einrichten\n\nWie soll der Befehl heißen?\n\nShell erkannt : ${shell_name}\nProfil-Datei  : ${profile_file}" \
        14 62 "ssht") || return
    [[ -z "$alias_name" ]] && alias_name="ssht"

    # Alias-Zeile je Shell
    local alias_line
    if [[ "$shell_name" == "fish" ]]; then
        alias_line="alias ${alias_name} '${SCRIPT_PATH}'"
    else
        alias_line="alias ${alias_name}='${SCRIPT_PATH}'"
    fi

    # Vorhandenen Alias ersetzen?
    if grep -q "alias ${alias_name}" "$profile_file" 2>/dev/null; then
        tui yesno \
            "⚠  Alias '${alias_name}' existiert bereits\nin ${profile_file}.\n\nErsetzen?" \
            10 60 || return
        local tmpfile; tmpfile="$(mktemp)"
        grep -v "alias ${alias_name}" "$profile_file" > "$tmpfile" 2>/dev/null && \
            mv "$tmpfile" "$profile_file" || rm -f "$tmpfile"
    fi

    # Alias anhängen
    mkdir -p "$(dirname "$profile_file")"
    {
        echo ""
        echo "# ssh-tui alias (hinzugefügt von ${APP} v${VERSION})"
        echo "$alias_line"
    } >> "$profile_file"

    local reload_hint="source ${profile_file}"

    tui msgbox \
        "✅ Alias '${alias_name}' eingerichtet!\n\nHinzugefügt in:\n  ${profile_file}\n\n⚠  Bitte Terminal neu starten\n   oder Profil neu laden:\n\n  ${reload_hint}" \
        16 66
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

main() {
    check_dependencies
    load_config
    agent_load_env

    if [[ ! -f "$CONFIG_FILE" ]]; then
        first_run_setup
    fi

    menu_main
}

main "$@"

