#!/bin/bash

# Validierungs-Script für NCT6687D Konfiguration auf MSI MAG Z890 TOMAHAWK WIFI
# Überprüft Installation, Sensor-Funktionalität und Hardware-Erkennung

echo "=== NCT6687D Konfigurationsvalidierung für MSI MAG Z890 TOMAHAWK WIFI ==="
echo "Datum: $(date)"
echo "Kernel: $(uname -r)"
echo

# Überprüfen ob bc verfügbar ist
if ! command -v bc &> /dev/null; then
    echo "WARNUNG: 'bc' nicht verfügbar. Installieren für Berechnungen: sudo pacman -S bc"
fi

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funktionen für farbige Ausgabe
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "ℹ $1"; }

# Zähler für Statistiken
total_tests=0
passed_tests=0
warnings=0

run_test() {
    ((total_tests++))
    if eval "$1"; then
        print_success "$2"
        ((passed_tests++))
        return 0
    else
        print_error "$2"
        return 1
    fi
}

run_warning_test() {
    ((total_tests++))
    if eval "$1"; then
        print_success "$2"
        ((passed_tests++))
        return 0
    else
        print_warning "$2"
        ((warnings++))
        return 1
    fi
}

echo "=== 1. Modul-Status Überprüfung ==="
run_test "lsmod | grep -q nct6687" "nct6687 Modul geladen"

if lsmod | grep -q nct6687; then
    echo "Modul-Informationen:"
    modinfo nct6687 | grep -E "(version|description|parm)" | sed 's/^/  /'
    
    # Parameter prüfen
    if [ -f "/sys/module/nct6687/parameters/manual" ]; then
        manual_val=$(cat /sys/module/nct6687/parameters/manual)
        if [ "$manual_val" = "Y" ]; then
            print_success "Manual-Modus aktiviert"
        else
            print_warning "Manual-Modus nicht aktiviert (empfohlen für Z890)"
        fi
    fi
    
    if [ -f "/sys/module/nct6687/parameters/force" ]; then
        force_val=$(cat /sys/module/nct6687/parameters/force)
        if [ "$force_val" = "Y" ]; then
            print_info "Force-Modus aktiviert"
        fi
    fi
else
    print_error "nct6687 Modul nicht geladen - Installation überprüfen"
    echo "Versuchen Sie: sudo modprobe nct6687 manual=1"
    exit 1
fi
echo

echo "=== 2. Hardware-Erkennung ==="
hwmon_path=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
run_test "[ -n '$hwmon_path' ]" "NCT6687 hwmon Gerät gefunden"

if [ -n "$hwmon_path" ]; then
    print_info "Gerätepfad: $hwmon_path"
    
    # Chip-Name prüfen
    if [ -f "$hwmon_path/name" ]; then
        chip_name=$(cat "$hwmon_path/name")
        print_info "Chip-Name: $chip_name"
    fi
else
    print_error "NCT6687 hwmon Gerät nicht gefunden"
    exit 1
fi
echo

echo "=== 3. Sensor-Ausgabe Überprüfung ==="
sensors_output=$(sensors 2>&1)
run_test "echo '$sensors_output' | grep -q nct6687" "nct6687 in sensors-Ausgabe erkannt"

if echo "$sensors_output" | grep -q nct6687; then
    echo "Aktuelle Sensor-Ausgabe:"
    echo "$sensors_output" | grep -A 50 "nct6687" | sed 's/^/  /'
else
    print_error "nct6687 nicht in sensors-Ausgabe - lm-sensors installiert?"
fi
echo

echo "=== 4. Spannungsvalidierung ==="
# Definiere erwartete Spannungsbereiche
declare -A voltage_ranges=(
    ["+12V"]="11.4:12.6"
    ["+5V"]="4.75:5.25"
    ["+3.3V"]="3.135:3.465"
    ["VCore"]="0.6:1.4"
    ["DRAM"]="1.0:1.4"
    ["CPU SA"]="0.8:1.2"
    ["CPU I/O"]="0.9:1.3"
    ["CPU AUX"]="0.8:1.3"
    ["PCH"]="0.8:1.2"
)

voltage_count=0
valid_voltages=0

for voltage in "${!voltage_ranges[@]}"; do
    range="${voltage_ranges[$voltage]}"
    min_val=$(echo $range | cut -d: -f1)
    max_val=$(echo $range | cut -d: -f2)
    
    # Extrahiere Spannungswert aus sensors-Ausgabe
    value=$(echo "$sensors_output" | grep "$voltage" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    if [ -n "$value" ]; then
        ((voltage_count++))
        if command -v bc &> /dev/null && (( $(echo "$value >= $min_val && $value <= $max_val" | bc -l) )); then
            print_success "$voltage: $value V (Bereich: $min_val-$max_val V)"
            ((valid_voltages++))
        else
            print_warning "$voltage: $value V (außerhalb Bereich: $min_val-$max_val V)"
        fi
    else
        print_info "$voltage: Nicht gefunden oder nicht gelabelt"
    fi
done

print_info "Spannungssensoren gefunden: $voltage_count, davon gültig: $valid_voltages"
echo

echo "=== 5. Lüfter-Status Überprüfung ==="
fan_count=0
active_fans=0
pwm_count=0

for i in {1..8}; do
    # Fan RPM prüfen
    fan_file="$hwmon_path/fan${i}_input"
    if [ -f "$fan_file" ]; then
        rpm=$(cat "$fan_file" 2>/dev/null)
        if [ -n "$rpm" ] && [ "$rpm" != "0" ]; then
            print_success "Fan $i: $rpm RPM"
            ((active_fans++))
        else
            print_info "Fan $i: 0 RPM (nicht angeschlossen)"
        fi
        ((fan_count++))
    fi
    
    # PWM Kontrolle prüfen
    pwm_file="$hwmon_path/pwm${i}"
    if [ -f "$pwm_file" ]; then
        ((pwm_count++))
    fi
done

print_info "Fan-Eingänge verfügbar: $fan_count, aktive Lüfter: $active_fans"
print_info "PWM-Kontrollen verfügbar: $pwm_count"

if [ $active_fans -eq 0 ]; then
    print_warning "Keine aktiven Lüfter erkannt - BIOS-Einstellungen prüfen"
elif [ $active_fans -ge 2 ]; then
    print_success "Gute Lüfter-Erkennung ($active_fans aktive Lüfter)"
fi
echo

echo "=== 6. Temperatur-Sensoren ==="
temp_count=0
valid_temps=0

for i in {1..7}; do
    temp_file="$hwmon_path/temp${i}_input"
    if [ -f "$temp_file" ]; then
        temp_raw=$(cat "$temp_file" 2>/dev/null)
        if [ -n "$temp_raw" ] && [ "$temp_raw" != "0" ]; then
            temp_celsius=$(echo "scale=1; $temp_raw/1000" | bc 2>/dev/null || echo "?")
            if [ "$temp_celsius" != "?" ] && (( $(echo "$temp_celsius > 0 && $temp_celsius < 100" | bc -l 2>/dev/null || echo "0") )); then
                print_success "Temp $i: ${temp_celsius}°C"
                ((valid_temps++))
            else
                print_warning "Temp $i: ${temp_celsius}°C (ungewöhnlicher Wert)"
            fi
            ((temp_count++))
        fi
    fi
done

print_info "Temperatursensoren verfügbar: $temp_count, gültige Werte: $valid_temps"
echo

echo "=== 7. Konfigurationsdateien ==="
config_files=(
    "/etc/sensors.d/Z890_TOMAHAWK_WIFI.conf"
    "/etc/modules-load.d/nct6687.conf"
    "/etc/modprobe.d/nct6687.conf"
)

for config_file in "${config_files[@]}"; do
    if [ -f "$config_file" ]; then
        print_success "Konfigurationsdatei vorhanden: $config_file"
    else
        print_warning "Konfigurationsdatei fehlt: $config_file"
    fi
done
echo

echo "=== 8. Kernel-Logs Überprüfung ==="
recent_errors=$(dmesg | grep -i nct6687 | grep -i error | tail -5)
if [ -n "$recent_errors" ]; then
    print_warning "Aktuelle Kernel-Fehler gefunden:"
    echo "$recent_errors" | sed 's/^/  /'
else
    print_success "Keine aktuellen Kernel-Fehler"
fi

recent_logs=$(dmesg | grep -i nct6687 | tail -3)
if [ -n "$recent_logs" ]; then
    print_info "Letzte Kernel-Logs:"
    echo "$recent_logs" | sed 's/^/  /'
fi
echo

echo "=== 9. Performance-Test ==="
echo "Teste Sensor-Update-Geschwindigkeit..."
start_time=$(date +%s.%N 2>/dev/null || date +%s)
for i in {1..5}; do
    sensors > /dev/null 2>&1
done
end_time=$(date +%s.%N 2>/dev/null || date +%s)

if command -v bc &> /dev/null; then
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "?")
    if [ "$duration" != "?" ]; then
        avg_time=$(echo "scale=3; $duration/5" | bc)
        print_success "Sensor-Abfrage-Performance: ${avg_time}s pro Abfrage"
    fi
fi
echo

echo "=== Validierungs-Zusammenfassung ==="
echo "Tests durchgeführt: $total_tests"
echo "Erfolgreich: $passed_tests"
echo "Warnungen: $warnings"
echo "Fehlgeschlagen: $((total_tests - passed_tests - warnings))"

success_rate=$(echo "scale=1; $passed_tests*100/$total_tests" | bc 2>/dev/null || echo "?")
if [ "$success_rate" != "?" ]; then
    echo "Erfolgsrate: ${success_rate}%"
fi

echo
if [ $passed_tests -eq $total_tests ]; then
    print_success "Alle Tests bestanden! NCT6687D ist korrekt konfiguriert."
elif [ $((passed_tests + warnings)) -eq $total_tests ]; then
    print_warning "Installation funktional mit Warnungen. Überprüfen Sie die Hinweise oben."
else
    print_error "Einige Tests fehlgeschlagen. Überprüfen Sie die Installation."
fi

echo
echo "=== Empfehlungen ==="
if [ $active_fans -eq 0 ]; then
    echo "• Überprüfen Sie BIOS Hardware Monitor Einstellungen"
    echo "• Stellen Sie sicher, dass Lüfter angeschlossen sind"
fi

if [ $valid_voltages -lt 3 ]; then
    echo "• Überprüfen Sie Spannungs-Multiplier in /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf"
    echo "• Vergleichen Sie mit BIOS-Werten und passen Sie an"
fi

if [ $warnings -gt 0 ]; then
    echo "• Beachten Sie die Warnungen oben für optimale Konfiguration"
fi

echo "• Für weitere Diagnose verwenden Sie:"
echo "  bash diagnose_fans_z890.sh"
echo "  bash analyze_voltages_z890.sh"

echo
echo "=== Validierung abgeschlossen ==="
