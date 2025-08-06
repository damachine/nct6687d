#!/bin/bash

# Debug-Script für NCT6687 Register-Analyse
# Hilft bei der Identifizierung von Hardware-Mapping-Problemen

echo "=== NCT6687 Register-Debug für MSI MAG Z890 TOMAHAWK WIFI ==="
echo "Datum: $(date)"
echo

# Überprüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "WARNUNG: Für vollständigen Register-Zugriff als root ausführen"
    echo "sudo bash $0"
    echo
fi

# Finde NCT6687 hwmon Gerät
hwmon_path=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
if [ -z "$hwmon_path" ]; then
    echo "FEHLER: NCT6687 hwmon Gerät nicht gefunden!"
    echo "Überprüfen Sie: lsmod | grep nct6687"
    exit 1
fi

echo "✓ NCT6687 Gerät: $hwmon_path"
echo

# Chip-Informationen
echo "=== Chip-Informationen ==="
if [ -f "$hwmon_path/name" ]; then
    chip_name=$(cat "$hwmon_path/name")
    echo "Chip-Name: $chip_name"
fi

# Kernel-Modul-Informationen
echo "Modul-Parameter:"
if [ -d "/sys/module/nct6687/parameters" ]; then
    for param in /sys/module/nct6687/parameters/*; do
        if [ -f "$param" ]; then
            param_name=$(basename "$param")
            param_value=$(cat "$param" 2>/dev/null || echo "nicht lesbar")
            echo "  $param_name: $param_value"
        fi
    done
else
    echo "  Keine Parameter-Informationen verfügbar"
fi

echo

# Vollständige Register-Analyse
echo "=== Vollständige Register-Analyse ==="

# Fan-Register
echo "--- Fan-Register ---"
echo "Register | Raw-Wert | RPM  | PWM  | PWM-Enable | Status"
echo "---------|----------|------|------|------------|-------"

for i in {1..8}; do
    fan_input="$hwmon_path/fan${i}_input"
    pwm_file="$hwmon_path/pwm${i}"
    pwm_enable="$hwmon_path/pwm${i}_enable"
    fan_min="$hwmon_path/fan${i}_min"
    fan_max="$hwmon_path/fan${i}_max"
    
    # Werte auslesen
    rpm=$(cat "$fan_input" 2>/dev/null || echo "N/A")
    pwm=$(cat "$pwm_file" 2>/dev/null || echo "N/A")
    enable=$(cat "$pwm_enable" 2>/dev/null || echo "N/A")
    min_rpm=$(cat "$fan_min" 2>/dev/null || echo "N/A")
    max_rpm=$(cat "$fan_max" 2>/dev/null || echo "N/A")
    
    # Status bestimmen
    if [ "$rpm" != "N/A" ] && [ "$rpm" -gt 0 ]; then
        status="AKTIV"
    elif [ "$rpm" = "0" ]; then
        status="INAKTIV"
    else
        status="FEHLER"
    fi
    
    printf "fan%-5d | %-8s | %-4s | %-4s | %-10s | %s\n" "$i" "$rpm" "$rpm" "$pwm" "$enable" "$status"
    
    # Zusätzliche Details für aktive Lüfter
    if [ "$status" = "AKTIV" ]; then
        echo "         | Min: $min_rpm, Max: $max_rpm"
    fi
done

echo

# Temperatur-Register
echo "--- Temperatur-Register ---"
echo "Register | Raw-Wert | Celsius | Status"
echo "---------|----------|---------|-------"

for i in {1..7}; do
    temp_input="$hwmon_path/temp${i}_input"
    temp_max="$hwmon_path/temp${i}_max"
    temp_crit="$hwmon_path/temp${i}_crit"
    
    raw_temp=$(cat "$temp_input" 2>/dev/null || echo "N/A")
    max_temp=$(cat "$temp_max" 2>/dev/null || echo "N/A")
    crit_temp=$(cat "$temp_crit" 2>/dev/null || echo "N/A")
    
    if [ "$raw_temp" != "N/A" ]; then
        celsius=$(echo "scale=1; $raw_temp/1000" | bc 2>/dev/null || echo "?")
        
        # Status bestimmen
        if (( $(echo "$celsius > 0 && $celsius < 100" | bc -l 2>/dev/null || echo "0") )); then
            status="GÜLTIG"
        else
            status="UNGÜLTIG"
        fi
    else
        celsius="N/A"
        status="FEHLER"
    fi
    
    printf "temp%-4d | %-8s | %-7s | %s\n" "$i" "$raw_temp" "$celsius" "$status"
    
    if [ "$max_temp" != "N/A" ] || [ "$crit_temp" != "N/A" ]; then
        echo "         | Max: $max_temp, Crit: $crit_temp"
    fi
done

echo

# Spannungs-Register
echo "--- Spannungs-Register ---"
echo "Register | Raw-Wert | Volt    | Multiplier | Mögliche Zuordnung"
echo "---------|----------|---------|------------|-------------------"

for i in {0..13}; do
    in_input="$hwmon_path/in${i}_input"
    in_min="$hwmon_path/in${i}_min"
    in_max="$hwmon_path/in${i}_max"
    
    raw_voltage=$(cat "$in_input" 2>/dev/null || echo "N/A")
    min_voltage=$(cat "$in_min" 2>/dev/null || echo "N/A")
    max_voltage=$(cat "$in_max" 2>/dev/null || echo "N/A")
    
    if [ "$raw_voltage" != "N/A" ] && [ "$raw_voltage" != "0" ]; then
        voltage=$(echo "scale=3; $raw_voltage/1000" | bc 2>/dev/null || echo "?")
        
        # Bestimme mögliche Zuordnung basierend auf Spannungswert
        possible_assignment=""
        
        # Teste verschiedene Multiplier
        for mult in 1 2 5 12; do
            test_voltage=$(echo "scale=3; $raw_voltage*$mult/1000" | bc 2>/dev/null || echo "0")
            
            # Prüfe gegen bekannte Spannungsbereiche
            if (( $(echo "$test_voltage >= 11.4 && $test_voltage <= 12.6" | bc -l 2>/dev/null || echo "0") )); then
                possible_assignment="$possible_assignment +12V(×$mult)"
            elif (( $(echo "$test_voltage >= 4.75 && $test_voltage <= 5.25" | bc -l 2>/dev/null || echo "0") )); then
                possible_assignment="$possible_assignment +5V(×$mult)"
            elif (( $(echo "$test_voltage >= 3.135 && $test_voltage <= 3.465" | bc -l 2>/dev/null || echo "0") )); then
                possible_assignment="$possible_assignment +3.3V(×$mult)"
            elif (( $(echo "$test_voltage >= 0.6 && $test_voltage <= 1.4" | bc -l 2>/dev/null || echo "0") )); then
                possible_assignment="$possible_assignment VCore(×$mult)"
            elif (( $(echo "$test_voltage >= 1.1 && $test_voltage <= 1.35" | bc -l 2>/dev/null || echo "0") )); then
                possible_assignment="$possible_assignment DRAM(×$mult)"
            fi
        done
        
        if [ -z "$possible_assignment" ]; then
            possible_assignment="Unbekannt"
        fi
        
        printf "in%-6d | %-8s | %-7s | %-10s | %s\n" "$i" "$raw_voltage" "$voltage" "1" "$possible_assignment"
    else
        printf "in%-6d | %-8s | %-7s | %-10s | %s\n" "$i" "$raw_voltage" "N/A" "N/A" "Nicht verfügbar"
    fi
done

echo

# Erweiterte Hardware-Informationen
echo "=== Erweiterte Hardware-Informationen ==="

# Alle verfügbaren Attribute auflisten
echo "--- Alle verfügbaren hwmon-Attribute ---"
find "$hwmon_path" -name "*" -type f | sort | while read file; do
    attr_name=$(basename "$file")
    attr_value=$(cat "$file" 2>/dev/null || echo "nicht lesbar")
    
    # Nur interessante Attribute anzeigen
    case "$attr_name" in
        *_input|*_enable|*_min|*_max|*_crit|*_label|name)
            printf "%-20s: %s\n" "$attr_name" "$attr_value"
            ;;
    esac
done

echo

# Kernel-Debug-Informationen
echo "=== Kernel-Debug-Informationen ==="
echo "--- Aktuelle dmesg-Logs (NCT6687) ---"
dmesg | grep -i nct6687 | tail -10 | while read line; do
    echo "  $line"
done

echo
echo "--- Modul-Informationen ---"
if lsmod | grep -q nct6687; then
    lsmod | grep nct6687
    echo
    modinfo nct6687 | grep -E "(version|description|parm|depends)" | sed 's/^/  /'
else
    echo "  nct6687 Modul nicht geladen"
fi

echo

# Hardware-Konfiguration aus /proc
echo "=== System-Hardware-Informationen ==="
echo "--- DMI/BIOS-Informationen ---"
echo "Motherboard: $(dmidecode -s baseboard-product-name 2>/dev/null || echo "Unbekannt")"
echo "Hersteller: $(dmidecode -s baseboard-manufacturer 2>/dev/null || echo "Unbekannt")"
echo "BIOS Version: $(dmidecode -s bios-version 2>/dev/null || echo "Unbekannt")"
echo "BIOS Datum: $(dmidecode -s bios-release-date 2>/dev/null || echo "Unbekannt")"

echo
echo "--- I/O-Ports (NCT-relevant) ---"
if [ -f "/proc/ioports" ]; then
    grep -E "(002e|004e|0a20)" /proc/ioports 2>/dev/null | sed 's/^/  /' || echo "  Keine NCT-relevanten Ports gefunden"
fi

echo

# Vergleich mit sensors-Ausgabe
echo "=== Vergleich mit sensors-Ausgabe ==="
if command -v sensors &> /dev/null; then
    echo "--- Aktuelle sensors-Ausgabe ---"
    sensors | grep -A 50 nct6687 | sed 's/^/  /'
else
    echo "sensors-Befehl nicht verfügbar"
fi

echo

# Problemdiagnose
echo "=== Problemdiagnose ==="
echo "--- Häufige Probleme und Lösungsansätze ---"

# Prüfe auf häufige Probleme
problem_count=0

# Problem 1: Keine aktiven Lüfter
active_fans=$(find "$hwmon_path" -name "fan*_input" -exec sh -c 'val=$(cat {} 2>/dev/null); [ "$val" -gt 0 ] 2>/dev/null && echo {}' \; | wc -l)
if [ "$active_fans" -eq 0 ]; then
    echo "⚠ Problem: Keine aktiven Lüfter erkannt"
    echo "  Lösungen:"
    echo "  - BIOS Hardware Monitor aktivieren"
    echo "  - Lüfter-Anschlüsse überprüfen"
    echo "  - manual=1 Parameter testen"
    ((problem_count++))
fi

# Problem 2: Unrealistische Spannungswerte
unrealistic_voltages=$(find "$hwmon_path" -name "in*_input" -exec sh -c 'val=$(cat {} 2>/dev/null); [ "$val" -gt 20000 ] 2>/dev/null && echo {}' \; | wc -l)
if [ "$unrealistic_voltages" -gt 0 ]; then
    echo "⚠ Problem: Unrealistische Spannungswerte erkannt"
    echo "  Lösungen:"
    echo "  - Spannungs-Multiplier in sensors.d anpassen"
    echo "  - manual=1 Parameter verwenden"
    echo "  - Sensor-Konfiguration überprüfen"
    ((problem_count++))
fi

# Problem 3: PWM-Kontrollen nicht verfügbar
pwm_controls=$(find "$hwmon_path" -name "pwm*" -not -name "*_*" | wc -l)
if [ "$pwm_controls" -eq 0 ]; then
    echo "⚠ Problem: Keine PWM-Kontrollen verfügbar"
    echo "  Lösungen:"
    echo "  - BIOS Smart Fan Control aktivieren"
    echo "  - force=1 Parameter testen"
    echo "  - Hardware-Kompatibilität prüfen"
    ((problem_count++))
fi

if [ "$problem_count" -eq 0 ]; then
    echo "✓ Keine offensichtlichen Probleme erkannt"
fi

echo
echo "=== Empfohlene nächste Schritte ==="
echo "1. Vergleichen Sie Register-Werte mit BIOS-Anzeigen"
echo "2. Erstellen Sie korrigierte sensors.d Konfiguration:"
echo "   bash create_corrected_z890_config.sh"
echo "3. Testen Sie PWM-Funktionalität:"
echo "   bash test_pwm_controls.sh"
echo "4. Bei anhaltenden Problemen: Hardware-Dokumentation konsultieren"

echo
echo "=== Register-Debug abgeschlossen ==="
