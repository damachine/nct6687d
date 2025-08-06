#!/bin/bash

# Lüfter-Diagnose Script für MSI MAG Z890 TOMAHAWK WIFI
# Dieses Script analysiert die Lüfter-Sensoren und PWM-Kontrollen

echo "=== Lüfter-Diagnose für MSI MAG Z890 TOMAHAWK WIFI ==="
echo "Datum: $(date)"
echo

# Überprüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "WARNUNG: Dieses Script sollte als root ausgeführt werden für vollständigen Zugriff"
    echo "Führen Sie aus: sudo bash $0"
    echo
fi

# Finde nct6687 hwmon Gerät
echo "=== NCT6687 Gerät-Erkennung ==="
hwmon_path=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
if [ -z "$hwmon_path" ]; then
    echo "FEHLER: nct6687 hwmon Gerät nicht gefunden!"
    echo "Überprüfen Sie ob der nct6687 Treiber geladen ist:"
    echo "  lsmod | grep nct6687"
    echo "  sudo modprobe nct6687"
    exit 1
fi

echo "✓ NCT6687 Gerät gefunden: $hwmon_path"
echo

# Überprüfe Treiber-Status
echo "=== Treiber-Status ==="
if lsmod | grep -q nct6687; then
    echo "✓ nct6687 Modul geladen"
    modinfo nct6687 | grep -E "(version|description|parm)" | head -5
else
    echo "✗ nct6687 Modul nicht geladen"
fi
echo

# Prüfe alle Fan-Eingänge und PWM-Kontrollen
echo "=== Detaillierte Fan-Analyse ==="
fan_detected=0
pwm_detected=0

for i in {1..8}; do
    echo "--- Fan/PWM $i ---"
    
    # Fan Input prüfen
    fan_input="$hwmon_path/fan${i}_input"
    fan_min="$hwmon_path/fan${i}_min"
    fan_max="$hwmon_path/fan${i}_max"
    fan_label="$hwmon_path/fan${i}_label"
    
    if [ -f "$fan_input" ]; then
        rpm=$(cat "$fan_input" 2>/dev/null || echo "Fehler")
        echo "  Fan ${i} RPM: $rpm"
        
        if [ "$rpm" != "0" ] && [ "$rpm" != "Fehler" ]; then
            ((fan_detected++))
            echo "  Status: ✓ AKTIV"
        else
            echo "  Status: - Nicht angeschlossen oder inaktiv"
        fi
        
        # Zusätzliche Fan-Attribute
        if [ -f "$fan_min" ]; then
            min_rpm=$(cat "$fan_min" 2>/dev/null || echo "N/A")
            echo "  Min RPM: $min_rpm"
        fi
        
        if [ -f "$fan_max" ]; then
            max_rpm=$(cat "$fan_max" 2>/dev/null || echo "N/A")
            echo "  Max RPM: $max_rpm"
        fi
        
        if [ -f "$fan_label" ]; then
            label=$(cat "$fan_label" 2>/dev/null || echo "N/A")
            echo "  Label: $label"
        fi
    else
        echo "  Fan ${i}: Nicht verfügbar"
    fi
    
    # PWM Kontrolle prüfen
    pwm_file="$hwmon_path/pwm${i}"
    pwm_enable="$hwmon_path/pwm${i}_enable"
    pwm_mode="$hwmon_path/pwm${i}_mode"
    
    if [ -f "$pwm_file" ]; then
        pwm_val=$(cat "$pwm_file" 2>/dev/null || echo "N/A")
        echo "  PWM ${i} Wert: $pwm_val ($(echo "scale=1; $pwm_val*100/255" | bc 2>/dev/null || echo "?")%)"
        ((pwm_detected++))
        
        if [ -f "$pwm_enable" ]; then
            pwm_enable_val=$(cat "$pwm_enable" 2>/dev/null || echo "N/A")
            case $pwm_enable_val in
                0) echo "  PWM Modus: Deaktiviert" ;;
                1) echo "  PWM Modus: ✓ Manual" ;;
                2) echo "  PWM Modus: Thermal Cruise" ;;
                3) echo "  PWM Modus: Fan Speed Cruise" ;;
                4) echo "  PWM Modus: Smart Fan III" ;;
                5) echo "  PWM Modus: Smart Fan IV" ;;
                99) echo "  PWM Modus: ✓ Firmware/Auto" ;;
                *) echo "  PWM Modus: $pwm_enable_val (Unbekannt)" ;;
            esac
        fi
        
        if [ -f "$pwm_mode" ]; then
            mode_val=$(cat "$pwm_mode" 2>/dev/null || echo "N/A")
            case $mode_val in
                0) echo "  PWM Typ: DC" ;;
                1) echo "  PWM Typ: PWM" ;;
                *) echo "  PWM Typ: $mode_val" ;;
            esac
        fi
    else
        echo "  PWM ${i}: Nicht verfügbar"
    fi
    echo
done

# Zusammenfassung
echo "=== Zusammenfassung ==="
echo "Erkannte aktive Lüfter: $fan_detected"
echo "Verfügbare PWM-Kontrollen: $pwm_detected"
echo

# Zusätzliche Hardware-Informationen
echo "=== Hardware-Informationen ==="
echo "Motherboard: $(dmidecode -s baseboard-product-name 2>/dev/null || echo "Unbekannt")"
echo "BIOS Version: $(dmidecode -s bios-version 2>/dev/null || echo "Unbekannt")"
echo

# Alle verfügbaren Fan/PWM Dateien auflisten
echo "=== Alle verfügbaren Fan/PWM Attribute ==="
find "$hwmon_path" -name "fan*" -o -name "pwm*" | sort | while read file; do
    if [ -f "$file" ]; then
        value=$(cat "$file" 2>/dev/null || echo "Nicht lesbar")
        echo "$(basename "$file"): $value"
    fi
done

echo
echo "=== Empfehlungen ==="
if [ $fan_detected -eq 0 ]; then
    echo "⚠ Keine aktiven Lüfter erkannt. Mögliche Ursachen:"
    echo "  - Lüfter sind nicht angeschlossen"
    echo "  - BIOS Hardware Monitor ist deaktiviert"
    echo "  - Falsche Sensor-Zuordnung"
    echo "  - Treiber benötigt 'manual=1' Parameter"
elif [ $fan_detected -lt 3 ]; then
    echo "⚠ Wenige Lüfter erkannt ($fan_detected). Überprüfen Sie:"
    echo "  - Alle Lüfter-Anschlüsse am Motherboard"
    echo "  - BIOS Fan-Einstellungen"
else
    echo "✓ Gute Lüfter-Erkennung ($fan_detected aktive Lüfter)"
fi

if [ $pwm_detected -gt 0 ]; then
    echo "✓ PWM-Kontrollen verfügbar ($pwm_detected)"
    echo "  Sie können Lüftergeschwindigkeiten manuell steuern"
else
    echo "⚠ Keine PWM-Kontrollen verfügbar"
fi

echo
echo "=== Nächste Schritte ==="
echo "1. Überprüfen Sie BIOS-Einstellungen:"
echo "   - Hardware Monitor: Enabled"
echo "   - Smart Fan Control: Enabled"
echo "2. Testen Sie manual=1 Parameter:"
echo "   sudo modprobe -r nct6687"
echo "   sudo modprobe nct6687 manual=1"
echo "3. Überprüfen Sie Sensor-Konfiguration in /etc/sensors.d/"

echo
echo "=== Diagnose abgeschlossen ==="
