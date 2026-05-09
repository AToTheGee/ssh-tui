# 🔐 ssh-tui

```text
 _______ _______ ___ ___        _______ ___ ___ ___ 
|   _   |   _   |   Y   |______|       |   Y   |   |
|   1___|   1___|.  1   |______|.|   | |.  |   |.  |
|____   |____   |.  _   |      `-|.  |-|.  |   |.  |
|:  1   |:  1   |:  |   |        |:  | |:  1   |:  |
|::.. . |::.. . |::.|:. |        |::.| |::.. . |::.|
`-------`-------`--- ---'        `---' `-------`---'        
```

**🔐 SSH Key & Host Manager — Terminal UI für macOS & Linux**

![bash](https://img.shields.io/badge/bash-%E2%89%A5%203.2-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey?style=flat-square&logo=apple)
![license](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

---

## ✨ Features

| Feature | Beschreibung |
| --- | --- |
| 🔑 **Key-Verwaltung** | SSH-Keys auflisten, Fingerprints anzeigen, Keys löschen |
| 📤 **Clipboard** | Public Key per `pbcopy` / `xclip` / `xsel` kopieren |
| ✨ **Key-Generator** | Ed25519, RSA-4096, ECDSA, DSA — mit Präfix/Suffix-Support |
| 🚀 **Verbinden** | SSH-Verbindung mit Key-Auswahl direkt aus der App |
| 🌐 **known\_hosts** | Einträge einsehen und per `ssh-keygen -R` entfernen |
| ⚙️ **Einstellungen** | Standard-User, -Host, -Key, SSH-Dir, Key-Präfix/Suffix |
| 📦 **Auto-Install** | Fehlende Abhängigkeiten werden erkannt & automatisch installiert |
| 🎨 **Fancy UI** | ANSI 256-Farben, Emojis, ASCII-Banner, `dialog` / `whiptail` |

---

## 🖥️ Voraussetzungen

> Die App erkennt fehlende Tools beim Start und bietet an, diese **automatisch zu installieren**.

| Tool | Zweck | Pflicht |
| --- | --- | --- |
| `bash` ≥ 3.2 | Shell | ✅ |
| `ssh` + `ssh-keygen` | SSH-Operationen | ✅ |
| `dialog` **oder** `whiptail` | TUI-Menüs | ✅ (wird ggf. installiert) |
| `pbcopy` / `xclip` / `xsel` | Clipboard | ➖ optional |

### Manuelle Installation (falls benötigt)

```bash
# macOS (Homebrew)
brew install dialog

# Debian / Ubuntu
sudo apt install dialog

# Fedora / RHEL
sudo dnf install dialog

# Arch Linux
sudo pacman -S dialog

# openSUSE
sudo zypper install dialog
```

---

## 🚀 Quickstart

```bash
# 1. Repository klonen
git clone https://github.com/AToTheGee/ssh-tui.git
cd ssh-tui

# 2. Ausführbar machen
chmod +x ssh-tui.sh

# 3. Starten
./ssh-tui.sh
```

Beim **ersten Start** wird ein kurzes Setup durchgeführt:

1. 📁 Vorhandener `~/.ssh`-Ordner wird erkannt — Keys & Hosts werden gezählt
2. ❓ Du wirst gefragt, ob du diesen Ordner verwenden möchtest (oder einen anderen angibst)
3. 🔑 Alle vorhandenen SSH-Keys werden mit Fingerprint aufgelistet
4. ✅ Konfiguration wird in `~/.config/ssh-tui/config` gespeichert

---

## 🗂️ Menü-Übersicht

```text
🔐 Hauptmenü
├── 🔑  SSH-Keys verwalten
│   ├── 📋  Alle Keys anzeigen
│   ├── 📤  Public Key kopieren
│   └── 🗑   Key löschen
├── 🚀  Verbinden          (user@host + Key-Auswahl)
├── ✨  Neuen Key generieren
│   └── ed25519 / RSA-4096 / ECDSA / DSA
├── 🌐  known_hosts verwalten
│   ├── 📋  Alle Einträge anzeigen
│   └── 🗑   Eintrag entfernen
├── ⚙️  Einstellungen
│   ├── 👤  Standard-Benutzer
│   ├── 🖥   Standard-Host
│   ├── 🏷   Key-Präfix / -Suffix
│   ├── 📁  SSH-Verzeichnis
│   └── 🔑  Standard-Key
└── 🚪  Beenden
```

---

## ⚙️ Einstellungen & Konfiguration

Die Konfiguration wird automatisch in `~/.config/ssh-tui/config` gespeichert (Rechte: `600`):

```bash
SSH_DIR="/Users/alice/.ssh"
DEFAULT_USER="alice"
DEFAULT_HOST="myserver.example.com"
KEY_PREFIX="work_"
KEY_SUFFIX="_2024"
DEFAULT_KEY="work_ed25519_2024"
```

**Key-Präfix/Suffix** — Beispiel:

```text
Präfix: "work_"   Suffix: "_prod"
→ Neuer Key-Name-Vorschlag: work_ed25519_prod
```

---

## 🗂️ Projektstruktur

```text
ssh-tui/
├── ssh-tui.sh            🔐 Hauptskript
├── config/
│   └── hosts.conf        📋 Beispielkonfiguration (SSH-Hosts)
└── README.md
```

---

## 🤝 Mitmachen

Pull Requests und Issues sind herzlich willkommen!

```bash
git checkout -b feature/mein-feature
# … Änderungen …
git commit -m "feat: mein neues Feature"
git push origin feature/mein-feature
```

---
Made with (❤️=emjay) and too many SSH keys, too many servers, and a desire for a better terminal experience.
Happy SSHing! 🚀 
