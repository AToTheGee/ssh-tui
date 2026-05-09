#!/usr/bin/env bash
# ============================================================
#  🔐  ssh-tui – SSH Key & Host Manager
#  macOS & Linux | bash ≥ 3.2
# ============================================================

set -uo pipefail   # no -e: dialog Cancel returns 1 → handled via || return

# ── ANSI Colors & Styles ──────────────────────────────────────
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

# ── App-Konstanten ────────────────────────────────────────────
readonly APP="ssh-tui"
readonly VERSION="1.0.0"
readonly OS="$(uname -s)"
readonly CONFIG_DIR="${HOME}/.config/${APP}"
readonly CONFIG_FILE="${CONFIG_DIR}/config"

# ── Konfigurierbare Variablen ─────────────────────────────────
SSH_DIR="${HOME}/.ssh"
DEFAULT_USER="${USER:-$(id -un 2>/dev/null || echo 'user')}"
DEFAULT_HOST=""
KEY_PREFIX=""
KEY_SUFFIX=""
DEFAULT_KEY=""

TUI_TOOL=""

# ──────────────────────────────────────────────────────────────
# HILFSFUNKTIONEN
# ──────────────────────────────────────────────────────────────

# Portable sed -i (macOS braucht leeres '' als Backup-Suffix)
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
CONF
    chmod 600 "$CONFIG_FILE"
}

count_keys() {
    find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | wc -l | tr -d ' \t'
}

last_modified() {
    local f
    f="$(ls -t "$SSH_DIR" 2>/dev/null | head -1)"
    [[ -z "$f" ]] && { echo "–"; return; }
    if [[ "$OS" == "Darwin" ]]; then
        stat -f "%Sm" -t "%d.%m.%Y %H:%M" "${SSH_DIR}/${f}" 2>/dev/null || echo "–"
    else
        stat -c "%y" "${SSH_DIR}/${f}" 2>/dev/null | \
            sed 's/\([0-9]\{4\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\) \([0-9]\{2\}:[0-9]\{2\}\).*/\3.\2.\1 \4/' \
            || echo "–"
    fi
}

# Tilde-Expansion ohne eval
expand_tilde() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

# TUI-Wrapper: einheitlich für dialog & whiptail
tui() {
    local type="$1"; shift
    if [[ "$TUI_TOOL" == "dialog" ]]; then
        dialog --colors --backtitle "🔐  ${APP} v${VERSION}" \
            --"$type" "$@" 3>&1 1>&2 2>&3
    else
        whiptail --"$type" "$@" 3>&1 1>&2 2>&3
    fi
}

# ──────────────────────────────────────────────────────────────
# ABHÄNGIGKEITEN
# ──────────────────────────────────────────────────────────────

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

    [[ ${#missing[@]} -eq 0 ]] && return 0

    echo ""
    echo -e "${C_ORG}${B}  ╔══════════════════════════════════════════╗${R}"
    echo -e "${C_ORG}${B}  ║  ⚠   Fehlende Abhängigkeiten             ║${R}"
    echo -e "${C_ORG}${B}  ╚══════════════════════════════════════════╝${R}"
    echo ""
    for m in "${missing[@]}"; do
        echo -e "    ${C_YLW}📦  ${m}${R}"
    done
    echo ""

    local pkg_mgr
    pkg_mgr="$(detect_pkg_manager)" || {
        echo -e "${C_RED}  Kein unterstützter Paketmanager gefunden.${R}"
        echo -e "${C_GRY}  Bitte manuell installieren: ${missing[*]}${R}"
        exit 1
    }

    echo -ne "  ${C_CYN}❓ Jetzt automatisch installieren? [j/N]: ${R}"
    local ans
    read -r ans
    if [[ "$ans" =~ ^[jJyY]$ ]]; then
        install_packages "$pkg_mgr" "${missing[@]}"
    else
        echo -e "\n  ${C_RED}Abbruch. Bitte Abhängigkeiten manuell installieren.${R}\n"
        exit 1
    fi
}

detect_pkg_manager() {
    if [[ "$OS" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            echo "brew"
        else
            echo -e "\n  ${C_CYN}💡 Homebrew nicht gefunden.${R}" >&2
            echo -e "  Installieren mit:" >&2
            echo -e "  ${C_GRY}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${R}\n" >&2
            return 1
        fi
    elif command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf      &>/dev/null; then echo "dnf"
    elif command -v pacman   &>/dev/null; then echo "pacman"
    elif command -v zypper   &>/dev/null; then echo "zypper"
    else return 1
    fi
}

install_packages() {
    local mgr="$1"; shift
    echo ""
    for pkg in "$@"; do
        echo -e "  ${C_BLU}📦 Installiere ${B}${pkg}${R}${C_BLU}...${R}"
        case "$mgr" in
            brew)   brew install "$pkg" ;;
            apt)    sudo apt-get install -y "$pkg" ;;
            dnf)    sudo dnf install -y "$pkg" ;;
            pacman) sudo pacman -S --noconfirm "$pkg" ;;
            zypper) sudo zypper install -y "$pkg" ;;
        esac
        echo -e "  ${C_GRN}✅ ${pkg} installiert.${R}"
    done
    echo ""

    # TUI-Tool neu ermitteln nach Installation
    if command -v dialog &>/dev/null; then
        TUI_TOOL="dialog"
    elif command -v whiptail &>/dev/null; then
        TUI_TOOL="whiptail"
    else
        echo -e "  ${C_RED}TUI-Tool konnte nicht installiert werden.${R}"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────────────
# ERSTER START / SETUP
# ──────────────────────────────────────────────────────────────

first_run_setup() {
    clear
    echo ""
    echo -e "  ${C_MAG}${B}🔐 Willkommen bei ssh-tui v${VERSION}!${R}"
    echo -e "  ${C_GRY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"
    echo -e "  ${C_GRY}Erster Start — kurze Einrichtung erforderlich.${R}"
    echo ""

    local chosen_dir="${HOME}/.ssh"

    # Prüfen ob ~/.ssh vorhanden und nicht leer ist
    if [[ -d "${HOME}/.ssh" ]] && [[ -n "$(ls -A "${HOME}/.ssh" 2>/dev/null)" ]]; then
        local key_count host_count
        key_count=$(find "${HOME}/.ssh" -maxdepth 1 -name "*.pub" 2>/dev/null | wc -l | tr -d ' \t')
        host_count=0
        [[ -f "${HOME}/.ssh/known_hosts" ]] && \
            host_count=$(wc -l < "${HOME}/.ssh/known_hosts" | tr -d ' \t')

        echo -e "  ${C_GRN}✅ Vorhandener SSH-Ordner gefunden:${R} ${B}${HOME}/.ssh${R}"
        echo ""
        echo -e "  ${C_YLW}🔑${R} SSH-Keys:        ${B}${key_count}${R}"
        echo -e "  ${C_CYN}🌐${R} Bekannte Hosts:  ${B}${host_count}${R}"
        echo ""
        echo -ne "  ${C_YLW}❓ Diesen Ordner verwenden? [J/n]: ${R}"
        local use_existing
        read -r use_existing

        if [[ "$use_existing" =~ ^[nN]$ ]]; then
            echo ""
            echo -ne "  ${C_CYN}📁 Neuer Speicherort (Enter = ~/.ssh): ${R}"
            local custom_dir
            read -r custom_dir
            chosen_dir="${custom_dir:-${HOME}/.ssh}"
        fi
    else
        echo -e "  ${C_CYN}📁 Kein vorhandener SSH-Ordner unter ~/.ssh gefunden.${R}"
        echo ""
        echo -ne "  Speicherort eingeben (Enter = ~/.ssh): "
        local custom_dir
        read -r custom_dir
        chosen_dir="${custom_dir:-${HOME}/.ssh}"
    fi

    SSH_DIR="$(expand_tilde "$chosen_dir")"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    DEFAULT_USER="${USER:-$(id -un 2>/dev/null || echo 'user')}"
    save_config

    echo ""
    echo -e "  ${C_GRN}✅ Konfiguration gespeichert:${R} ${C_GRY}${CONFIG_FILE}${R}"
    sleep 1

    # Vorhandene Keys auflisten
    list_keys_plain
}

list_keys_plain() {
    local found=0

    while IFS= read -r pub; do
        if [[ $found -eq 0 ]]; then
            clear
            echo ""
            echo -e "  ${C_MAG}${B}🔑 Vorhandene SSH-Keys in ${SSH_DIR}${R}"
            echo ""
            echo -e "  ${C_GRY}┌──────────────────────────────────────────────────────────┐${R}"
        fi
        found=1

        local name info fp type
        name="$(basename "$pub" .pub)"
        info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
        fp="$(echo "$info"   | awk '{print $2}')"
        type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"

        echo -e "  ${C_GRY}│${R}  ${C_YLW}🔑${R}  ${B}${name}${R}  ${C_GRY}[${type}]${R}"
        echo -e "  ${C_GRY}│${R}     ${DIM}${fp}${R}"
        echo -e "  ${C_GRY}│${R}"
    done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

    if [[ $found -eq 0 ]]; then return; fi

    echo -e "  ${C_GRY}└──────────────────────────────────────────────────────────┘${R}"
    echo ""
    echo -e "  ${C_GRY}Drücke Enter zum Fortfahren...${R}"
    read -r
}

# ──────────────────────────────────────────────────────────────
# ASCII BANNER & DASHBOARD
# ──────────────────────────────────────────────────────────────

show_banner() {
    clear
    local key_count last_mod hn un
    key_count="$(count_keys)"
    last_mod="$(last_modified)"
    hn="$(hostname -s 2>/dev/null || hostname)"
    un="${DEFAULT_USER:-${USER:-'?'}}"

    echo -e "${C_BLU}${B}"
    cat << 'BANNER'
  ███████╗███████╗██╗  ██╗    ████████╗██╗   ██╗██╗
  ██╔════╝██╔════╝██║  ██║    ╚══██╔══╝██║   ██║██║
  ███████╗███████╗███████║       ██║   ██║   ██║██║
  ╚════██║╚════██║██╔══██║       ██║   ██║   ██║██║
  ███████║███████║██║  ██║       ██║   ╚██████╔╝██║
  ╚══════╝╚══════╝╚═╝  ╚═╝       ╚═╝    ╚═════╝ ╚═╝
BANNER
    echo -e "${R}"
    echo -e "  ${C_GRY}══════════════════════════════════════════════════════${R}"
    printf "  ${C_CYN}👤 User     ${R}${B}%-24s${R}${C_CYN}🖥  Host   ${R}${B}%s${R}\n" \
        "$un" "$hn"
    printf "  ${C_YLW}🔑 Keys     ${R}${B}%-24s${R}${C_YLW}🕒 Geändert ${R}%s\n" \
        "$key_count" "$last_mod"
    printf "  ${C_GRN}📁 SSH-Dir  ${R}${C_GRY}%s${R}\n" "$SSH_DIR"
    echo -e "  ${C_GRY}══════════════════════════════════════════════════════${R}"
    echo ""
}

# ──────────────────────────────────────────────────────────────
# HAUPTMENÜ
# ──────────────────────────────────────────────────────────────

menu_main() {
    while true; do
        show_banner
        local choice
        choice=$(tui menu "  🔐  Hauptmenü" 18 62 6 \
            "keys"     "🔑  SSH-Keys verwalten" \
            "connect"  "🚀  Verbinden" \
            "generate" "✨  Neuen Key generieren" \
            "hosts"    "🌐  known_hosts verwalten" \
            "settings" "⚙   Einstellungen" \
            "quit"     "🚪  Beenden") || break

        case "$choice" in
            keys)     menu_keys     ;;
            connect)  menu_connect  ;;
            generate) menu_generate ;;
            hosts)    menu_hosts    ;;
            settings) menu_settings ;;
            quit)     break         ;;
        esac
    done

    clear
    echo -e "\n  ${C_GRN}${B}👋 Auf Wiedersehen!${R}\n"
}

# ──────────────────────────────────────────────────────────────
# KEYS VERWALTEN
# ──────────────────────────────────────────────────────────────

menu_keys() {
    while true; do
        local choice
        choice=$(tui menu "🔑 SSH-Keys" 14 60 4 \
            "list"   "📋  Alle Keys anzeigen" \
            "copy"   "📤  Public Key kopieren" \
            "delete" "🗑   Key löschen" \
            "back"   "◀   Zurück") || return

        case "$choice" in
            list)   show_key_list_dialog ;;
            copy)   copy_public_key      ;;
            delete) delete_key           ;;
            back)   return               ;;
        esac
    done
}

show_key_list_dialog() {
    local tmpfile
    tmpfile="$(mktemp)"

    {
        printf "%-26s %-11s %s\n" "Name" "Typ" "Fingerprint"
        printf "%s\n" "──────────────────────────────────────────────────────────"
        local found=0
        while IFS= read -r pub; do
            found=1
            local name info fp type
            name="$(basename "$pub" .pub)"
            info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
            fp="$(echo "$info"   | awk '{print $2}')"
            type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
            printf "%-26s %-11s %s\n" "$name" "$type" "$fp"
        done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)
        [[ $found -eq 0 ]] && echo "(Keine Keys in ${SSH_DIR})"
    } > "$tmpfile"

    tui textbox "$tmpfile" 22 74 || true
    rm -f "$tmpfile"
}

copy_public_key() {
    local items=()
    while IFS= read -r pub; do
        local name info fp
        name="$(basename "$pub" .pub)"
        info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
        fp="$(echo "$info" | awk '{print $2}')"
        items+=("$name" "$fp")
    done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

    if [[ ${#items[@]} -eq 0 ]]; then
        tui msgbox "⚠  Keine SSH-Keys vorhanden." 6 42
        return
    fi

    local selected
    selected=$(tui menu "📤 Public Key kopieren" 20 68 8 "${items[@]}") || return

    local pub_content
    pub_content="$(cat "${SSH_DIR}/${selected}.pub")"

    if [[ "$OS" == "Darwin" ]]; then
        echo "$pub_content" | pbcopy
        tui msgbox "✅ Public Key '${selected}' in die Zwischenablage kopiert!" 7 60
    elif command -v xclip &>/dev/null; then
        echo "$pub_content" | xclip -selection clipboard
        tui msgbox "✅ Public Key '${selected}' in die Zwischenablage kopiert!" 7 60
    elif command -v xsel &>/dev/null; then
        echo "$pub_content" | xsel --clipboard --input
        tui msgbox "✅ Public Key '${selected}' in die Zwischenablage kopiert!" 7 60
    else
        # Fallback: Key im Textbox anzeigen
        local tmpfile
        tmpfile="$(mktemp)"
        echo "$pub_content" > "$tmpfile"
        tui msgbox "ℹ  Kein Clipboard-Tool gefunden.\nKey wird angezeigt:" 8 55 || true
        tui textbox "$tmpfile" 10 76 || true
        rm -f "$tmpfile"
    fi
}

delete_key() {
    local items=()
    while IFS= read -r pub; do
        local info type
        info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
        type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
        items+=("$(basename "$pub" .pub)" "[$type]")
    done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

    if [[ ${#items[@]} -eq 0 ]]; then
        tui msgbox "⚠  Keine SSH-Keys vorhanden." 6 42
        return
    fi

    local selected
    selected=$(tui menu "🗑  Key löschen" 20 60 8 "${items[@]}") || return

    tui yesno "🗑  Key '${selected}' wirklich löschen?\n\nFolgende Dateien werden entfernt:\n  • ${selected}\n  • ${selected}.pub" 12 58 || return

    rm -f "${SSH_DIR}/${selected}" "${SSH_DIR}/${selected}.pub"
    tui msgbox "✅ Key '${selected}' wurde gelöscht." 6 50
}

# ──────────────────────────────────────────────────────────────
# VERBINDEN
# ──────────────────────────────────────────────────────────────

menu_connect() {
    local default_target=""
    [[ -n "$DEFAULT_USER" ]] && default_target="${DEFAULT_USER}"
    [[ -n "$DEFAULT_HOST" ]] && default_target="${default_target}@${DEFAULT_HOST}"

    local host
    host=$(tui inputbox "🚀 SSH-Verbindung\n\nZiel eingeben (user@host oder hostname):" 10 60 \
        "$default_target") || return
    [[ -z "$host" ]] && return

    # Key auswählen
    local items=("Standard" "(Systemstandard / ~/.ssh/config)")
    while IFS= read -r pub; do
        local name info type
        name="$(basename "$pub" .pub)"
        info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
        type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
        items+=("$name" "[$type]")
    done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

    local key_choice
    key_choice=$(tui menu "🔑 Key für Verbindung wählen" 18 60 8 "${items[@]}") || return

    clear
    echo -e "\n  ${C_GRN}${B}🚀 Verbinde mit ${host}...${R}\n"

    if [[ "$key_choice" == "Standard" ]]; then
        ssh "$host"
    else
        ssh -i "${SSH_DIR}/${key_choice}" "$host"
    fi

    echo -e "\n  ${C_GRY}Verbindung beendet. Drücke Enter...${R}"
    read -r
}

# ──────────────────────────────────────────────────────────────
# KEY GENERIEREN
# ──────────────────────────────────────────────────────────────

menu_generate() {
    local key_type
    key_type=$(tui menu "✨ Key-Typ wählen" 14 62 4 \
        "ed25519" "🔐 Ed25519  — modern, kompakt, empfohlen" \
        "rsa"     "🔑 RSA 4096 — klassisch, weit verbreitet" \
        "ecdsa"   "🔷 ECDSA    — Elliptische Kurve (NIST)" \
        "dsa"     "⚠  DSA      — veraltet, nicht empfohlen") || return

    local default_name="${KEY_PREFIX}${key_type}${KEY_SUFFIX}"
    local key_name
    key_name=$(tui inputbox "📝 Key-Name:" 8 54 "$default_name") || return
    [[ -z "$key_name" ]] && return

    if [[ -f "${SSH_DIR}/${key_name}" ]]; then
        tui yesno "⚠  Key '${key_name}' existiert bereits!\n\nÜberschreiben?" 9 52 || return
    fi

    local cur_user cur_host
    cur_user="${DEFAULT_USER:-${USER:-$(id -un 2>/dev/null || echo 'user')}}"
    cur_host="$(hostname -s 2>/dev/null || hostname)"
    local key_comment
    key_comment=$(tui inputbox "💬 Kommentar (z.B. E-Mail oder Beschreibung):" 8 60 \
        "${cur_user}@${cur_host}") || return

    local bits_flag=""
    [[ "$key_type" == "rsa"   ]] && bits_flag="-b 4096"
    [[ "$key_type" == "ecdsa" ]] && bits_flag="-b 521"

    tui yesno "✨ Key generieren?\n\n  Typ:       ${key_type}\n  Name:      ${key_name}\n  Speichern: ${SSH_DIR}/${key_name}\n  Kommentar: ${key_comment}" 14 62 || return

    clear
    echo -e "\n  ${C_BLU}${B}✨ Generiere SSH-Key '${key_name}'...${R}\n"

    # shellcheck disable=SC2086
    ssh-keygen -t "$key_type" $bits_flag \
        -C "$key_comment" \
        -f "${SSH_DIR}/${key_name}"

    echo -e "\n  ${C_GRN}${B}✅ Key erfolgreich erstellt!${R}"
    echo -e "  ${C_GRY}Drücke Enter...${R}"
    read -r
}

# ──────────────────────────────────────────────────────────────
# KNOWN_HOSTS VERWALTEN
# ──────────────────────────────────────────────────────────────

menu_hosts() {
    while true; do
        local hosts_file="${SSH_DIR}/known_hosts"
        local count=0
        [[ -f "$hosts_file" ]] && count=$(wc -l < "$hosts_file" | tr -d ' \t')

        local choice
        choice=$(tui menu "🌐 known_hosts verwalten" 14 62 3 \
            "view"  "📋  Alle Einträge anzeigen  (${count} Zeilen)" \
            "clear" "🗑   Eintrag entfernen  (ssh-keygen -R)" \
            "back"  "◀   Zurück") || return

        case "$choice" in
            view)
                if [[ -f "$hosts_file" ]]; then
                    tui textbox "$hosts_file" 22 80 || true
                else
                    tui msgbox "ℹ  Keine known_hosts-Datei gefunden." 6 46
                fi ;;
            clear)
                local target
                target=$(tui inputbox "🗑  Eintrag entfernen\n\nHostname oder IP-Adresse:" 9 56 "") || continue
                [[ -z "$target" ]] && continue
                ssh-keygen -R "$target" 2>/dev/null || true
                tui msgbox "✅ Eintrag '${target}' entfernt." 6 48 ;;
            back) return ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────
# EINSTELLUNGEN
# ──────────────────────────────────────────────────────────────

menu_settings() {
    while true; do
        local choice
        choice=$(tui menu "⚙  Einstellungen" 22 68 7 \
            "user"   "👤  Standard-Benutzer    [${DEFAULT_USER:-–}]" \
            "host"   "🖥   Standard-Host        [${DEFAULT_HOST:-–}]" \
            "prefix" "🏷   Key-Präfix           [${KEY_PREFIX:-–}]" \
            "suffix" "🏷   Key-Suffix           [${KEY_SUFFIX:-–}]" \
            "dir"    "📁  SSH-Verzeichnis      [${SSH_DIR}]" \
            "defkey" "🔑  Standard-Key         [${DEFAULT_KEY:-–}]" \
            "back"   "◀   Zurück") || return

        local val
        case "$choice" in
            user)
                val=$(tui inputbox "👤 Standard-Benutzername:\n\nWird als Vorauswahl beim Verbinden verwendet." 10 56 \
                    "$DEFAULT_USER") || continue
                DEFAULT_USER="$val"
                save_config
                tui msgbox "✅ Benutzername gesetzt: '${DEFAULT_USER}'" 6 48 ;;

            host)
                val=$(tui inputbox "🖥  Standard-Hostname:\n\nWird als Vorauswahl beim Verbinden verwendet." 10 56 \
                    "$DEFAULT_HOST") || continue
                DEFAULT_HOST="$val"
                save_config
                tui msgbox "✅ Standard-Host gesetzt: '${DEFAULT_HOST}'" 6 48 ;;

            prefix)
                val=$(tui inputbox "🏷  Key-Präfix:\n\nWird vor neue Key-Namen gesetzt.\nBeispiel: 'work_'  →  work_ed25519" 12 56 \
                    "$KEY_PREFIX") || continue
                KEY_PREFIX="$val"
                save_config
                tui msgbox "✅ Präfix gesetzt: '${KEY_PREFIX:-leer}'" 6 48 ;;

            suffix)
                val=$(tui inputbox "🏷  Key-Suffix:\n\nWird nach neue Key-Namen gesetzt.\nBeispiel: '_2024'  →  ed25519_2024" 12 56 \
                    "$KEY_SUFFIX") || continue
                KEY_SUFFIX="$val"
                save_config
                tui msgbox "✅ Suffix gesetzt: '${KEY_SUFFIX:-leer}'" 6 48 ;;

            dir)
                val=$(tui inputbox "📁 SSH-Verzeichnis:\n\nAbsoluter Pfad oder ~ für Home.\nAktuell: ${SSH_DIR}" 12 60 \
                    "$SSH_DIR") || continue
                local new_dir
                new_dir="$(expand_tilde "$val")"
                if mkdir -p "$new_dir" 2>/dev/null; then
                    chmod 700 "$new_dir"
                    SSH_DIR="$new_dir"
                    save_config
                    tui msgbox "✅ SSH-Verzeichnis gesetzt:\n${SSH_DIR}" 8 58
                else
                    tui msgbox "⚠  Verzeichnis konnte nicht erstellt werden:\n${new_dir}" 8 58
                fi ;;

            defkey)
                local items=("keine" "— kein Standard-Key —")
                while IFS= read -r pub; do
                    local info type
                    info="$(ssh-keygen -l -f "$pub" 2>/dev/null)"
                    type="$(echo "$info" | awk '{print $NF}' | tr -d '()')"
                    items+=("$(basename "$pub" .pub)" "[$type]")
                done < <(find "$SSH_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null | sort)

                val=$(tui menu "🔑 Standard-Key wählen" 20 60 8 "${items[@]}") || continue
                [[ "$val" == "keine" ]] && val=""
                DEFAULT_KEY="$val"
                save_config
                tui msgbox "✅ Standard-Key: '${DEFAULT_KEY:-nicht gesetzt}'" 6 50 ;;

            back) return ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────

main() {
    check_dependencies
    load_config

    # Erster Start?
    if [[ ! -f "$CONFIG_FILE" ]]; then
        first_run_setup
    fi

    menu_main
}

main "$@"

