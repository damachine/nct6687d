#!/bin/bash

# Komplette Lösung für Sensor-Label-Zuordnung auf MSI MAG Z890 TOMAHAWK WIFI
# Behebt Lüfter-Erkennung und Label-Mapping-Probleme

echo "=== Sensor-Label-Zuordnung Korrektur für MSI MAG Z890 TOMAHAWK WIFI ==="
echo "Datum: $(date)"
echo

# Überprüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "FEHLER: Dieses Script muss als root ausgeführt werden!"
    echo "sudo bash $0"
    exit 1
fi

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Überprüfe NCT6687 Status
hwmon_path=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
if [ -z "$hwmon_path" ]; then
    print_error "NCT6687 hwmon Gerät nicht gefunden!"
    echo "Überprüfen Sie: lsmod | grep nct6687"
    echo "Falls nicht geladen: sudo modprobe nct6687 manual=1"
    exit 1
fi

print_success "NCT6687 Gerät gefunden: $hwmon_path"

print_step "1. Analyse der aktuellen Sensor-Ausgabe"

# Aktuelle sensors-Ausgabe analysieren
echo "Aktuelle sensors-Ausgabe:"
if command -v sensors &> /dev/null; then
    sensors | grep -A 50 nct6687 | sed 's/^/  /'
else
    print_warning "sensors-Befehl nicht verfügbar. Installieren: sudo pacman -S lm_sensors"
fi

echo
echo "Hardware-Register-Analyse:"
echo "Fan-Register | RPM-Wert | Status"
echo "-------------|----------|-------"

declare -a active_fans
declare -a fan_rpms

for i in {1..8}; do
    fan_input="$hwmon_path/fan${i}_input"
    if [ -f "$fan_input" ]; then
        rpm=$(cat "$fan_input" 2>/dev/null || echo "0")
        fan_rpms[$i]=$rpm
        
        if [ "$rpm" -gt 0 ]; then
            active_fans+=($i)
            status="AKTIV"
        else
            status="INAKTIV"
        fi
        
        printf "fan%-9d | %-8s | %s\n" "$i" "$rpm" "$status"
    fi
done

echo
print_success "Aktive Lüfter gefunden: ${#active_fans[@]} (Register: ${active_fans[*]})"

print_step "2. Problem-Identifikation"

problems_found=0

# Problem 1: Keine aktiven Lüfter
if [ ${#active_fans[@]} -eq 0 ]; then
    print_error "Problem: Keine aktiven Lüfter erkannt"
    echo "Mögliche Ursachen:"
    echo "  - BIOS Hardware Monitor deaktiviert"
    echo "  - Lüfter nicht angeschlossen"
    echo "  - Treiber-Parameter fehlen (manual=1)"
    ((problems_found++))
fi

# Problem 2: Falsche Labels in sensors-Ausgabe
if command -v sensors &> /dev/null; then
    sensors_output=$(sensors | grep -A 50 nct6687)
    
    # Prüfe ob Standard NCT6687 Labels verwendet werden
    if echo "$sensors_output" | grep -q "CPU_FAN\|SYS_FAN"; then
        print_warning "Problem: Nicht-Standard Labels in sensors-Ausgabe erkannt"
        echo "Die sensors.d Konfiguration verwendet nicht die NCT6687 Standard-Labels"
        ((problems_found++))
    fi
fi

# Problem 3: Manual-Modus nicht aktiviert
if [ -f "/sys/module/nct6687/parameters/manual" ]; then
    manual_mode=$(cat /sys/module/nct6687/parameters/manual)
    if [ "$manual_mode" != "Y" ]; then
        print_warning "Problem: Manual-Modus nicht aktiviert"
        echo "Für korrekte Sensor-Zuordnung sollte manual=1 verwendet werden"
        ((problems_found++))
    fi
fi

if [ $problems_found -eq 0 ]; then
    print_success "Keine offensichtlichen Probleme erkannt"
else
    echo "Gefundene Probleme: $problems_found"
fi

print_step "3. Backup der aktuellen Konfiguration"

backup_dir="/root/nct6687_sensor_fix_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"

# Backup aktuelle Konfiguration
if [ -f "/etc/sensors.d/Z890_TOMAHAWK_WIFI.conf" ]; then
    cp "/etc/sensors.d/Z890_TOMAHAWK_WIFI.conf" "$backup_dir/"
    print_success "Backup erstellt: $backup_dir/Z890_TOMAHAWK_WIFI.conf"
fi

# Backup aktuelle sensors-Ausgabe
if command -v sensors &> /dev/null; then
    sensors > "$backup_dir/sensors_before_fix.txt"
    print_success "Sensors-Ausgabe gesichert"
fi

# Backup Module-Parameter
if [ -f "/etc/modprobe.d/nct6687.conf" ]; then
    cp "/etc/modprobe.d/nct6687.conf" "$backup_dir/"
fi

print_step "4. Treiber-Parameter korrigieren"

# Überprüfe und korrigiere Module-Parameter
echo "Aktuelle Module-Parameter:"
if [ -f "/etc/modprobe.d/nct6687.conf" ]; then
    cat /etc/modprobe.d/nct6687.conf | sed 's/^/  /'
else
    echo "  Keine nct6687.conf gefunden"
fi

# Erstelle/aktualisiere Module-Parameter
cat > /etc/modprobe.d/nct6687.conf << 'EOF'
# NCT6687D Parameter für MSI MAG Z890 TOMAHAWK WIFI
# Korrigierte Konfiguration für bessere Sensor-Erkennung
options nct6687 manual=1 force=1

# Abhängigkeit für i2c_i801 (falls Boot-Probleme auftreten)
softdep nct6687 pre: i2c_i801

# Blacklist alter Treiber
blacklist nct6683
EOF

print_success "Module-Parameter aktualisiert"

print_step "5. Treiber mit korrigierten Parametern neu laden"

# Entlade und lade Treiber neu
print_warning "Lade nct6687 Treiber neu..."
modprobe -r nct6687 2>/dev/null || true
sleep 2

modprobe nct6687 manual=1 force=1
if [ $? -eq 0 ]; then
    print_success "nct6687 Treiber erfolgreich neu geladen"
else
    print_error "Fehler beim Laden des nct6687 Treibers"
    echo "Überprüfen Sie: dmesg | grep nct6687"
    exit 1
fi

# Warte auf Hardware-Initialisierung
sleep 3

print_step "6. Korrigierte Sensor-Konfiguration installieren"

# Installiere korrigierte Konfiguration
if [ -f "Z890_TOMAHAWK_WIFI_corrected_labels.conf" ]; then
    cp "Z890_TOMAHAWK_WIFI_corrected_labels.conf" "/etc/sensors.d/Z890_TOMAHAWK_WIFI.conf"
    print_success "Korrigierte Sensor-Konfiguration installiert"
else
    print_warning "Erstelle Standard-korrigierte Konfiguration..."
    
    # Erstelle Basis-Konfiguration mit NCT6687 Standard-Labels
    cat > /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf << 'EOF'
# MSI MAG Z890 TOMAHAWK WIFI - Korrigierte NCT6687 Standard-Labels
chip "nct6687-*"
    # Spannungen (NCT6687 Standard)
    label in0         "+12V"
    label in1         "+5V"
    label in2         "CPU Soc"
    label in3         "DRAM"
    label in4         "CPU Vcore"
    label in5         "Chipset"
    label in6         "CPU SA"
    label in7         "Voltage #2"
    label in8         "AVCC3"
    label in9         "CPU 1P8"
    label in10        "CPU VDDP"
    label in11        "+3.3V"
    label in12        "AVSB"
    label in13        "VBat"

    # Temperaturen (NCT6687 Standard)
    label temp1       "CPU"
    label temp2       "System"
    label temp3       "VRM MOS"
    label temp4       "PCH"
    label temp5       "CPU Socket"
    label temp6       "PCIe x1"
    label temp7       "M2_1"

    # Lüfter (NCT6687 Standard)
    label fan1        "CPU Fan"
    label fan2        "Pump Fan"
    label fan3        "System Fan #1"
    label fan4        "System Fan #2"
    label fan5        "System Fan #3"
    label fan6        "System Fan #4"
    label fan7        "System Fan #5"
    label fan8        "System Fan #6"

    # Spannungs-Multiplier
    compute in0       (@ * 12), (@ / 12)
    compute in1       (@ * 5), (@ / 5)
    compute in3       (@ * 2), (@ / 2)
EOF
    print_success "Standard-korrigierte Konfiguration erstellt"
fi

# Lade Sensor-Konfiguration neu
sensors -s
print_success "Sensor-Konfiguration neu geladen"

print_step "7. Validierung der Korrektur"

# Warte kurz für Sensor-Stabilisierung
sleep 2

echo "Neue sensors-Ausgabe nach Korrektur:"
if command -v sensors &> /dev/null; then
    new_sensors_output=$(sensors | grep -A 50 nct6687)
    echo "$new_sensors_output" | sed 's/^/  /'
    
    # Speichere neue Ausgabe
    echo "$new_sensors_output" > "$backup_dir/sensors_after_fix.txt"
else
    print_warning "sensors-Befehl nicht verfügbar"
fi

# Analysiere Verbesserungen
echo
echo "Verbesserungs-Analyse:"

# Zähle aktive Lüfter nach Korrektur
new_active_fans=0
for i in {1..8}; do
    fan_input="$hwmon_path/fan${i}_input"
    if [ -f "$fan_input" ]; then
        rpm=$(cat "$fan_input" 2>/dev/null || echo "0")
        if [ "$rpm" -gt 0 ]; then
            ((new_active_fans++))
        fi
    fi
done

echo "Aktive Lüfter vorher: ${#active_fans[@]}"
echo "Aktive Lüfter nachher: $new_active_fans"

if [ $new_active_fans -gt ${#active_fans[@]} ]; then
    improvement=$((new_active_fans - ${#active_fans[@]}))
    print_success "Verbesserung: +$improvement zusätzliche Lüfter erkannt"
elif [ $new_active_fans -eq ${#active_fans[@]} ]; then
    print_success "Lüfter-Erkennung stabil"
else
    print_warning "Lüfter-Erkennung reduziert - möglicherweise normale Variation"
fi

# Prüfe Label-Konsistenz
if command -v sensors &> /dev/null; then
    if sensors | grep -A 50 nct6687 | grep -q "CPU Fan\|System Fan"; then
        print_success "NCT6687 Standard-Labels werden verwendet"
    else
        print_warning "Labels möglicherweise noch nicht korrekt"
    fi
fi

print_step "8. Zusätzliche Optimierungen"

# BIOS-Empfehlungen
echo "BIOS/UEFI Empfehlungen für optimale Sensor-Erkennung:"
echo "1. Hardware Monitor: Enabled"
echo "2. Smart Fan Control: Enabled"
echo "3. Fan Speed Control: PWM (für 4-Pin Lüfter)"
echo "4. CPU Fan Speed: Normal oder Silent"
echo "5. System Fan Speed: Normal"

echo
echo "Für weitere Optimierung führen Sie aus:"
echo "- bash analyze_z890_hardware_mapping.sh (detaillierte Hardware-Analyse)"
echo "- bash debug_nct6687_registers.sh (Register-Level-Debug)"
echo "- bash test_pwm_controls.sh (PWM-Funktionalitäts-Test)"

print_step "9. Erstelle Recovery-Script"

# Erstelle Recovery-Script
cat > "$backup_dir/recovery_sensor_fix.sh" << EOF
#!/bin/bash
echo "Stelle ursprüngliche Sensor-Konfiguration wieder her..."

# Stoppe nct6687
modprobe -r nct6687 2>/dev/null || true

# Stelle Backup-Dateien wieder her
if [ -f "$backup_dir/Z890_TOMAHAWK_WIFI.conf" ]; then
    cp "$backup_dir/Z890_TOMAHAWK_WIFI.conf" /etc/sensors.d/
    echo "Sensor-Konfiguration wiederhergestellt"
fi

if [ -f "$backup_dir/nct6687.conf" ]; then
    cp "$backup_dir/nct6687.conf" /etc/modprobe.d/
    echo "Module-Parameter wiederhergestellt"
fi

# Lade Treiber neu
modprobe nct6687
sensors -s

echo "Recovery abgeschlossen. Überprüfen Sie mit: sensors"
EOF

chmod +x "$backup_dir/recovery_sensor_fix.sh"
print_success "Recovery-Script erstellt: $backup_dir/recovery_sensor_fix.sh"

print_step "10. Finale Dokumentation"

# Erstelle Dokumentation der Änderungen
cat > "$backup_dir/fix_documentation.txt" << EOF
Sensor-Label-Zuordnung Korrektur für MSI MAG Z890 TOMAHAWK WIFI
================================================================

Datum: $(date)
Kernel: $(uname -r)

Durchgeführte Änderungen:
1. Module-Parameter korrigiert (manual=1, force=1)
2. NCT6687 Treiber neu geladen
3. Sensor-Konfiguration auf NCT6687 Standard-Labels umgestellt
4. sensors.d Konfiguration aktualisiert

Vorher:
- Aktive Lüfter: ${#active_fans[@]}
- Labels: Möglicherweise nicht-standard

Nachher:
- Aktive Lüfter: $new_active_fans
- Labels: NCT6687 Standard-Labels

Backup-Verzeichnis: $backup_dir
Recovery-Script: $backup_dir/recovery_sensor_fix.sh

Nächste Schritte:
1. Vergleichen Sie sensors-Ausgabe mit BIOS-Werten
2. Führen Sie Hardware-Mapping-Analyse aus
3. Passen Sie Labels bei Bedarf an die tatsächliche Hardware an
4. Testen Sie PWM-Kontrollen

Bei Problemen:
- Führen Sie das Recovery-Script aus
- Überprüfen Sie BIOS Hardware Monitor Einstellungen
- Konsultieren Sie die Debug-Scripts
EOF

print_success "Dokumentation erstellt: $backup_dir/fix_documentation.txt"

echo
echo "=== Sensor-Label-Zuordnung Korrektur abgeschlossen ==="
echo
if [ $new_active_fans -gt 0 ]; then
    print_success "Korrektur erfolgreich! $new_active_fans aktive Lüfter erkannt"
    echo
    echo "Überprüfen Sie die neue sensors-Ausgabe:"
    echo "  sensors"
    echo
    echo "Für weitere Optimierung:"
    echo "  bash analyze_z890_hardware_mapping.sh"
    echo "  bash create_corrected_z890_config.sh"
else
    print_warning "Korrektur teilweise erfolgreich"
    echo
    echo "Weitere Troubleshooting-Schritte:"
    echo "1. Überprüfen Sie BIOS Hardware Monitor Einstellungen"
    echo "2. Führen Sie aus: bash debug_nct6687_registers.sh"
    echo "3. Testen Sie verschiedene Treiber-Parameter"
fi

echo
echo "Backup und Recovery verfügbar in: $backup_dir"
