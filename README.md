# ssh-tui

Eine einfache Terminal-Benutzeroberfläche (TUI) für SSH-Verbindungen, geschrieben als Bash-Skript.

## Voraussetzungen

- `bash` ≥ 4.0
- `whiptail` **oder** `dialog` (für die TUI-Menüs)
- `ssh`

**whiptail installieren** (falls nicht vorhanden):
```bash
# Debian/Ubuntu
sudo apt install whiptail

# Fedora/RHEL
sudo dnf install newt

# Arch
sudo pacman -S libnewt
```

## Verwendung

```bash
chmod +x ssh-tui.sh
./ssh-tui.sh
```

## Funktionen

| Menüpunkt           | Beschreibung                              |
|---------------------|-------------------------------------------|
| Verbindung herstellen | Aus gespeicherten Hosts auswählen und verbinden |
| Host hinzufügen     | Neuen SSH-Host speichern                  |
| Host entfernen      | Gespeicherten Host löschen                |
| Alle Hosts anzeigen | Übersicht aller konfigurierten Hosts      |

## Konfiguration

Hosts werden in `config/hosts.conf` gespeichert (Format: `name=user@host`).

```ini
webserver=admin@192.168.1.10
pi=pi@raspberrypi.local
vps=root@203.0.113.42
```

Die Datei kann auch manuell bearbeitet werden.

## Projektstruktur

```
ssh-tui/
├── ssh-tui.sh          # Hauptskript
├── config/
│   └── hosts.conf      # SSH-Host-Konfiguration
└── README.md
```
# ssh-tui
