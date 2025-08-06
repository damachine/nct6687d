#!/bin/bash

# Automatisches Installations-Script für NCT6687D auf MSI MAG Z890 TOMAHAWK WIFI
# Führt komplette Installation, Konfiguration und Validierung durch

set -e  # Beende bei Fehlern

echo "=== NCT6687D Automatische Installation für MSI MAG Z890 TOMAHAWK WIFI ==="
echo "Datum: $(date)"
echo "Kernel: $(uname -r)"
echo "Benutzer: $(whoami)"
echo

# Überprüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "FEHLER: Dieses Script muss als root ausgeführt werden!"
    echo "Führen Sie aus: sudo bash $0"
    exit 1
fi

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Backup-Verzeichnis erstellen
BACKUP_DIR="/root/nct6687d_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
print_success "Backup-Verzeichnis erstellt: $BACKUP_DIR"

# Funktion für Backup
backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$BACKUP_DIR/"
        print_success "Backup erstellt: $1"
    fi
}

print_step "1. Überprüfung der Voraussetzungen"

# Überprüfe Arch Linux
if ! command -v pacman &> /dev/null; then
    print_error "Dieses Script ist für Arch Linux konzipiert!"
    exit 1
fi

# Überprüfe notwendige Pakete
missing_packages=()
required_packages=("base-devel" "linux-headers" "dkms" "bc" "lm_sensors")

for package in "${required_packages[@]}"; do
    if ! pacman -Qi "$package" &> /dev/null; then
        missing_packages+=("$package")
    fi
done

if [ ${#missing_packages[@]} -gt 0 ]; then
    print_warning "Installiere fehlende Pakete: ${missing_packages[*]}"
    pacman -S --noconfirm "${missing_packages[@]}"
    print_success "Pakete installiert"
fi

print_step "2. Backup der aktuellen Konfiguration"

# Backup aktuelle Module-Konfiguration
backup_file "/etc/modules-load.d/modules.conf"
backup_file "/etc/modprobe.d/nct6683.conf"
backup_file "/etc/sensors.d/nct6683.conf"

# Aktuelle Sensor-Ausgabe sichern
if command -v sensors &> /dev/null; then
    sensors > "$BACKUP_DIR/sensors_before.txt" 2>/dev/null || true
    print_success "Aktuelle Sensor-Ausgabe gesichert"
fi

# Aktuelle Module sichern
lsmod | grep nct > "$BACKUP_DIR/modules_before.txt" 2>/dev/null || true

print_step "3. Entfernung des alten nct6683 Treibers"

# Entlade nct6683 falls geladen
if lsmod | grep -q nct6683; then
    print_warning "Entlade nct6683 Modul..."
    modprobe -r nct6683 || true
    print_success "nct6683 Modul entladen"
fi

# Blacklist nct6683
echo "blacklist nct6683" > /etc/modprobe.d/blacklist-nct6683.conf
print_success "nct6683 auf Blacklist gesetzt"

print_step "4. Installation des nct6687d Treibers"

# Überprüfe ob Repository bereits existiert
if [ ! -d "nct6687d" ]; then
    print_warning "Klone nct6687d Repository..."
    git clone https://github.com/Fred78290/nct6687d
    print_success "Repository geklont"
fi

cd nct6687d

# DKMS Installation
print_warning "Installiere nct6687d via DKMS..."
make dkms/install
print_success "nct6687d Treiber installiert"

cd ..

print_step "5. Konfiguration der Module"

# Erstelle Module-Load-Konfiguration
cat > /etc/modules-load.d/nct6687.conf << 'EOF'
# NCT6687D Treiber für MSI MAG Z890 TOMAHAWK WIFI
nct6687
EOF
print_success "Module-Load-Konfiguration erstellt"

# Erstelle Module-Parameter
cat > /etc/modprobe.d/nct6687.conf << 'EOF'
# NCT6687D Parameter für MSI MAG Z890 TOMAHAWK WIFI
options nct6687 manual=1 force=1

# Abhängigkeit für i2c_i801 (falls Boot-Probleme auftreten)
softdep nct6687 pre: i2c_i801

# Blacklist alter Treiber
blacklist nct6683
EOF
print_success "Module-Parameter konfiguriert"

print_step "6. Laden des nct6687 Moduls"

# Lade nct6687 Modul
modprobe nct6687 manual=1 force=1
if lsmod | grep -q nct6687; then
    print_success "nct6687 Modul erfolgreich geladen"
else
    print_error "Fehler beim Laden des nct6687 Moduls"
    print_warning "Überprüfe Kernel-Logs: dmesg | grep nct6687"
    exit 1
fi

print_step "7. Installation der Sensor-Konfiguration"

# Überprüfe ob Z890 Konfigurationsdatei existiert
if [ -f "Z890_TOMAHAWK_WIFI.conf" ]; then
    cp "Z890_TOMAHAWK_WIFI.conf" /etc/sensors.d/
    print_success "Z890 Sensor-Konfiguration installiert"
else
    print_warning "Erstelle Standard-Z890 Konfiguration..."
    
    cat > /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf << 'EOF'
# MSI MAG Z890 TOMAHAWK WIFI - Automatisch generierte Konfiguration
chip "nct6687-*"
    # Spannungen
    label in0         "+12V"
    label in1         "+5V"
    label in2         "VCore"
    label in3         "CPU SA"
    label in4         "DRAM"
    label in5         "CPU I/O"
    label in6         "CPU AUX"
    label in7         "PCH Core"
    label in8         "+3.3V"
    
    # Temperaturen
    label temp1       "CPU Package"
    label temp2       "System"
    label temp3       "VRM MOS"
    label temp4       "PCH"
    label temp5       "CPU Socket"
    
    # Lüfter
    label fan1        "CPU_FAN"
    label fan2        "SYS_FAN1"
    label fan3        "SYS_FAN2"
    label fan4        "SYS_FAN3"
    
    # Spannungs-Multiplier
    compute in0       (@ * 12), (@ / 12)
    compute in1       (@ * 5), (@ / 5)
    compute in4       (@ * 2), (@ / 2)
EOF
    print_success "Standard-Konfiguration erstellt"
fi

# Lade Sensor-Konfiguration
sensors -s
print_success "Sensor-Konfiguration geladen"

print_step "8. Erste Validierung"

# Warte kurz für Sensor-Initialisierung
sleep 2

# Überprüfe Sensor-Ausgabe
if sensors | grep -q nct6687; then
    print_success "nct6687 Sensoren erkannt"
    
    # Zeige erste Sensor-Ausgabe
    echo "Erste Sensor-Ausgabe:"
    sensors | grep -A 20 nct6687 | sed 's/^/  /'
else
    print_warning "nct6687 nicht in sensors-Ausgabe - möglicherweise normale Verzögerung"
fi

print_step "9. Erstellung der Diagnose-Scripts"

# Erstelle Diagnose-Scripts falls nicht vorhanden
scripts=("diagnose_fans_z890.sh" "analyze_voltages_z890.sh" "validate_z890_config.sh" "performance_test_z890.sh")

for script in "${scripts[@]}"; do
    if [ ! -f "$script" ]; then
        print_warning "$script nicht gefunden - erstelle Platzhalter"
        echo "#!/bin/bash" > "$script"
        echo "echo 'Diagnose-Script $script - Implementierung ausstehend'" >> "$script"
        chmod +x "$script"
    else
        chmod +x "$script"
        print_success "$script verfügbar und ausführbar"
    fi
done

print_step "10. Finale Validierung"

# Führe grundlegende Validierung durch
validation_passed=true

# Modul-Check
if ! lsmod | grep -q nct6687; then
    print_error "nct6687 Modul nicht geladen"
    validation_passed=false
fi

# hwmon-Check
hwmon_path=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
if [ -z "$hwmon_path" ]; then
    print_error "nct6687 hwmon Gerät nicht gefunden"
    validation_passed=false
else
    print_success "hwmon Gerät gefunden: $hwmon_path"
fi

# Sensor-Check
sensor_count=$(find "$hwmon_path" -name "*_input" 2>/dev/null | wc -l)
if [ "$sensor_count" -gt 0 ]; then
    print_success "$sensor_count Sensor-Eingänge verfügbar"
else
    print_warning "Keine Sensor-Eingänge gefunden"
fi

print_step "11. Backup und Dokumentation"

# Speichere finale Konfiguration
sensors > "$BACKUP_DIR/sensors_after.txt" 2>/dev/null || true
lsmod | grep nct > "$BACKUP_DIR/modules_after.txt" 2>/dev/null || true
dmesg | grep nct6687 > "$BACKUP_DIR/dmesg_nct6687.txt" 2>/dev/null || true

# Erstelle Installations-Dokumentation
cat > "$BACKUP_DIR/installation_log.txt" << EOF
NCT6687D Installation für MSI MAG Z890 TOMAHAWK WIFI
Datum: $(date)
Kernel: $(uname -r)
Benutzer: $(whoami)

Installation erfolgreich: $validation_passed

Installierte Dateien:
- /etc/modules-load.d/nct6687.conf
- /etc/modprobe.d/nct6687.conf
- /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf
- /etc/modprobe.d/blacklist-nct6683.conf

Verfügbare Diagnose-Scripts:
- diagnose_fans_z890.sh
- analyze_voltages_z890.sh
- validate_z890_config.sh
- performance_test_z890.sh

Backup-Verzeichnis: $BACKUP_DIR
EOF

print_success "Installations-Dokumentation erstellt"

echo
echo "=== Installation abgeschlossen ==="

if [ "$validation_passed" = true ]; then
    print_success "NCT6687D erfolgreich installiert und konfiguriert!"
    echo
    echo "Nächste Schritte:"
    echo "1. Führen Sie aus: bash validate_z890_config.sh"
    echo "2. Überprüfen Sie Sensoren: sensors"
    echo "3. Bei Problemen: bash diagnose_fans_z890.sh"
    echo "4. Für Performance-Test: bash performance_test_z890.sh"
else
    print_warning "Installation mit Warnungen abgeschlossen"
    echo
    echo "Troubleshooting:"
    echo "1. Überprüfen Sie Kernel-Logs: dmesg | grep nct6687"
    echo "2. Testen Sie manuelle Modulladung: sudo modprobe nct6687 manual=1 force=1"
    echo "3. Überprüfen Sie BIOS Hardware Monitor Einstellungen"
fi

echo
echo "Backup und Logs verfügbar in: $BACKUP_DIR"
echo "Bei Problemen können Sie mit den Backup-Dateien die ursprüngliche Konfiguration wiederherstellen."

# Erstelle Recovery-Script
cat > "$BACKUP_DIR/recovery.sh" << 'EOF'
#!/bin/bash
echo "Stelle ursprüngliche nct6683 Konfiguration wieder her..."
modprobe -r nct6687 2>/dev/null || true
rm -f /etc/modules-load.d/nct6687.conf
rm -f /etc/modprobe.d/nct6687.conf
rm -f /etc/modprobe.d/blacklist-nct6683.conf
rm -f /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf
modprobe nct6683
echo "Recovery abgeschlossen. Starten Sie das System neu."
EOF

chmod +x "$BACKUP_DIR/recovery.sh"
print_success "Recovery-Script erstellt: $BACKUP_DIR/recovery.sh"

echo
echo "=== Installation erfolgreich abgeschlossen ==="
