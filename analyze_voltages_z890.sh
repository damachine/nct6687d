#!/bin/bash

# Spannungsanalyse Script für MSI MAG Z890 TOMAHAWK WIFI
# Analysiert Spannungssensoren und empfiehlt Multiplier-Einstellungen

echo "=== Spannungsanalyse für MSI MAG Z890 TOMAHAWK WIFI ==="
echo "Datum: $(date)"
echo

# Überprüfen ob bc verfügbar ist
if ! command -v bc &> /dev/null; then
    echo "WARNUNG: 'bc' nicht gefunden. Installieren Sie es für Berechnungen:"
    echo "  sudo pacman -S bc"
    echo
fi

# Finde nct6687 hwmon Gerät
echo "=== NCT6687 Gerät-Erkennung ==="
hwmon_path=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
if [ -z "$hwmon_path" ]; then
    echo "FEHLER: nct6687 hwmon Gerät nicht gefunden!"
    echo "Überprüfen Sie ob der nct6687 Treiber geladen ist:"
    echo "  lsmod | grep nct6687"
    exit 1
fi

echo "✓ NCT6687 Gerät gefunden: $hwmon_path"
echo

# Überprüfe Treiber-Parameter
echo "=== Treiber-Parameter ==="
if [ -f "/sys/module/nct6687/parameters/manual" ]; then
    manual_mode=$(cat /sys/module/nct6687/parameters/manual)
    echo "Manual Modus: $manual_mode"
else
    echo "Manual Parameter: Nicht verfügbar"
fi

if [ -f "/sys/module/nct6687/parameters/force" ]; then
    force_mode=$(cat /sys/module/nct6687/parameters/force)
    echo "Force Modus: $force_mode"
else
    echo "Force Parameter: Nicht verfügbar"
fi
echo

# Raw-Spannungswerte analysieren
echo "=== Raw-Spannungswerte (ohne Multiplier) ==="
echo "Format: Register | Raw-Wert (mV) | Berechnet (V) | Mögliche Zuordnung"
echo "----------------------------------------------------------------"

# Definiere erwartete Spannungsbereiche für Z890
declare -A expected_voltages=(
    ["12V"]="11400:12600"
    ["5V"]="4750:5250"
    ["3.3V"]="3135:3465"
    ["VCore"]="600:1400"
    ["DRAM"]="1100:1350"
    ["CPU_SA"]="800:1200"
    ["CPU_IO"]="900:1300"
    ["PCH"]="800:1200"
)

# Analysiere alle Spannungsregister
for i in {0..13}; do
    in_file="$hwmon_path/in${i}_input"
    if [ -f "$in_file" ]; then
        raw_value=$(cat "$in_file" 2>/dev/null)
        if [ -n "$raw_value" ] && [ "$raw_value" != "0" ]; then
            voltage=$(echo "scale=3; $raw_value/1000" | bc 2>/dev/null || echo "?.???")
            
            # Bestimme mögliche Zuordnung basierend auf Spannungswert
            possible_assignment=""
            
            # Teste verschiedene Multiplier
            for mult in 1 2 5 12; do
                test_voltage=$(echo "scale=3; $raw_value*$mult/1000" | bc 2>/dev/null || echo "0")
                
                # Prüfe gegen bekannte Spannungsbereiche
                for volt_name in "${!expected_voltages[@]}"; do
                    range="${expected_voltages[$volt_name]}"
                    min_val=$(echo $range | cut -d: -f1)
                    max_val=$(echo $range | cut -d: -f2)
                    
                    if [ -n "$test_voltage" ] && (( $(echo "$test_voltage*1000 >= $min_val && $test_voltage*1000 <= $max_val" | bc -l 2>/dev/null || echo "0") )); then
                        if [ -z "$possible_assignment" ]; then
                            possible_assignment="$volt_name (×$mult)"
                        else
                            possible_assignment="$possible_assignment, $volt_name (×$mult)"
                        fi
                    fi
                done
            done
            
            if [ -z "$possible_assignment" ]; then
                possible_assignment="Unbekannt"
            fi
            
            printf "in%-2d     | %-8d      | %-8s  | %s\n" "$i" "$raw_value" "$voltage" "$possible_assignment"
        fi
    fi
done

echo
echo "=== Aktuelle Sensors-Ausgabe ==="
sensors_output=$(sensors 2>/dev/null | grep -A 50 nct6687)
if [ -n "$sensors_output" ]; then
    echo "$sensors_output"
else
    echo "Keine sensors-Ausgabe verfügbar. Installieren Sie lm-sensors:"
    echo "  sudo pacman -S lm_sensors"
fi

echo
echo "=== Empfohlene Multiplier-Konfiguration ==="
echo "Basierend auf der Analyse und Z890-Spezifikationen:"
echo

# Erstelle Multiplier-Empfehlungen
cat << 'EOF'
# Empfohlene compute-Statements für /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf:

# Hauptversorgungsspannungen (typisch für alle Motherboards)
compute in0       (@ * 12), (@ / 12)    # +12V Hauptversorgung
compute in1       (@ * 5), (@ / 5)      # +5V Standby

# Intel Z890 spezifische Spannungen
# VCore (CPU Kernspannung) - normalerweise 1:1
# compute in2       (@ * 1), (@ / 1)    # VCore (falls nötig)

# DRAM Spannung - oft mit Multiplier 2 für DDR5
compute in4       (@ * 2), (@ / 2)      # DRAM (DDR5: ~1.1V)

# 3.3V Rail - normalerweise 1:1
# compute in8       (@ * 1), (@ / 1)    # +3.3V (falls nötig)

# CPU Hilfsspannungen - normalerweise 1:1
# compute in3       (@ * 1), (@ / 1)    # CPU SA
# compute in5       (@ * 1), (@ / 1)    # CPU I/O
# compute in6       (@ * 1), (@ / 1)    # CPU AUX
EOF

echo
echo "=== Spannungsvalidierung ==="
echo "Vergleichen Sie die aktuellen Werte mit BIOS/UEFI-Anzeigen:"
echo

# Extrahiere aktuelle Spannungswerte aus sensors
if [ -n "$sensors_output" ]; then
    echo "Aktuelle Sensor-Werte:"
    echo "$sensors_output" | grep -E "V|mV" | head -10
else
    echo "Keine Sensor-Werte verfügbar"
fi

echo
echo "=== Erwartete Spannungsbereiche für Z890 ==="
echo "+12V:     11.4V - 12.6V  (Hauptversorgung)"
echo "+5V:      4.75V - 5.25V  (Standby)"
echo "+3.3V:    3.135V - 3.465V (I/O)"
echo "VCore:    0.6V - 1.4V    (CPU, abhängig von Last)"
echo "DRAM:     1.1V - 1.35V   (DDR5) oder 1.2V - 1.35V (DDR4)"
echo "CPU SA:   0.8V - 1.2V    (System Agent)"
echo "CPU I/O:  0.9V - 1.3V    (I/O Controller)"
echo "PCH:      0.8V - 1.2V    (Platform Controller Hub)"

echo
echo "=== Troubleshooting-Tipps ==="
echo "1. Wenn Spannungen unrealistisch sind:"
echo "   - Überprüfen Sie die Multiplier in der sensors.d Konfiguration"
echo "   - Testen Sie manual=1 Parameter: sudo modprobe nct6687 manual=1"
echo
echo "2. Wenn bestimmte Spannungen fehlen:"
echo "   - Aktivieren Sie alle Register mit manual=1"
echo "   - Überprüfen Sie BIOS Hardware Monitor Einstellungen"
echo
echo "3. Für genaue Kalibrierung:"
echo "   - Vergleichen Sie mit BIOS/UEFI Werten"
echo "   - Verwenden Sie ein Multimeter für kritische Spannungen"
echo "   - Passen Sie Multiplier schrittweise an"

echo
echo "=== Nächste Schritte ==="
echo "1. Kopieren Sie die empfohlenen compute-Statements in Ihre sensors.d Konfiguration"
echo "2. Laden Sie die Sensor-Konfiguration neu: sudo sensors -s"
echo "3. Testen Sie mit: sensors"
echo "4. Vergleichen Sie mit BIOS-Werten und passen Sie bei Bedarf an"

echo
echo "=== Analyse abgeschlossen ==="
