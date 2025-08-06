#!/bin/bash

# Hardware-Mapping-Analyse für MSI MAG Z890 TOMAHAWK WIFI
# Identifiziert die korrekte Zuordnung von Lüfter-Anschlüssen zu Sensor-Registern

echo "=== Hardware-Mapping-Analyse für MSI MAG Z890 TOMAHAWK WIFI ==="
echo "Datum: $(date)"
echo

# Überprüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "WARNUNG: Für vollständigen Hardware-Zugriff als root ausführen"
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

echo "✓ NCT6687 Gerät gefunden: $hwmon_path"
echo

# MSI Z890 TOMAHAWK WIFI Motherboard-Layout (basierend auf Handbuch)
echo "=== MSI MAG Z890 TOMAHAWK WIFI Lüfter-Anschlüsse (Motherboard-Layout) ==="
echo "Laut MSI-Spezifikation sollten folgende Anschlüsse vorhanden sein:"
echo "1. CPU_FAN1 (4-Pin PWM) - Hauptprozessor-Lüfter"
echo "2. CPU_OPT1 (4-Pin PWM) - Optionaler CPU-Lüfter oder AIO-Pumpe"
echo "3. SYS_FAN1 (4-Pin PWM) - System-Lüfter 1"
echo "4. SYS_FAN2 (4-Pin PWM) - System-Lüfter 2"
echo "5. SYS_FAN3 (4-Pin PWM) - System-Lüfter 3"
echo "6. SYS_FAN4 (4-Pin PWM) - System-Lüfter 4"
echo "7. SYS_FAN5 (4-Pin PWM) - System-Lüfter 5"
echo "8. PUMP_FAN1 (4-Pin PWM) - AIO-Pumpe"
echo

# Aktuelle NCT6687 Treiber-Labels (aus nct6687.c)
echo "=== NCT6687 Treiber Standard-Labels ==="
echo "fan1: CPU Fan"
echo "fan2: Pump Fan"
echo "fan3: System Fan #1"
echo "fan4: System Fan #2"
echo "fan5: System Fan #3"
echo "fan6: System Fan #4"
echo "fan7: System Fan #5"
echo "fan8: System Fan #6"
echo

# Analysiere aktuelle Hardware-Register
echo "=== Aktuelle Hardware-Register-Analyse ==="
echo "Register | RPM-Wert | PWM-Wert | PWM-Modus | Mögliche Zuordnung"
echo "---------|----------|----------|-----------|-------------------"

# Arrays für Analyse
declare -a rpm_values
declare -a pwm_values
declare -a pwm_modes
declare -a active_fans

for i in {1..8}; do
    fan_input="$hwmon_path/fan${i}_input"
    pwm_file="$hwmon_path/pwm${i}"
    pwm_enable="$hwmon_path/pwm${i}_enable"
    
    # RPM auslesen
    if [ -f "$fan_input" ]; then
        rpm=$(cat "$fan_input" 2>/dev/null || echo "0")
        rpm_values[$i]=$rpm
    else
        rpm="N/A"
        rpm_values[$i]=0
    fi
    
    # PWM Wert auslesen
    if [ -f "$pwm_file" ]; then
        pwm=$(cat "$pwm_file" 2>/dev/null || echo "0")
        pwm_values[$i]=$pwm
        pwm_percent=$(echo "scale=1; $pwm*100/255" | bc 2>/dev/null || echo "?")
    else
        pwm="N/A"
        pwm_values[$i]=0
        pwm_percent="N/A"
    fi
    
    # PWM Modus auslesen
    if [ -f "$pwm_enable" ]; then
        mode=$(cat "$pwm_enable" 2>/dev/null || echo "0")
        case $mode in
            1) mode_text="Manual" ;;
            99) mode_text="Auto" ;;
            *) mode_text="Mode $mode" ;;
        esac
        pwm_modes[$i]=$mode
    else
        mode_text="N/A"
        pwm_modes[$i]=0
    fi
    
    # Bestimme mögliche Zuordnung basierend auf RPM-Werten
    possible_assignment=""
    if [ "$rpm" != "N/A" ] && [ "$rpm" -gt 0 ]; then
        active_fans+=($i)
        
        # Heuristik für Zuordnung basierend auf typischen RPM-Bereichen
        if [ "$rpm" -gt 2000 ]; then
            possible_assignment="CPU_FAN (hohe RPM)"
        elif [ "$rpm" -gt 1500 ]; then
            possible_assignment="PUMP_FAN oder CPU_OPT"
        elif [ "$rpm" -gt 800 ]; then
            possible_assignment="SYS_FAN (Standard)"
        elif [ "$rpm" -gt 300 ]; then
            possible_assignment="SYS_FAN (langsam)"
        else
            possible_assignment="Unbekannt/Fehler"
        fi
    else
        possible_assignment="Nicht angeschlossen"
    fi
    
    printf "fan%-5d | %-8s | %-8s | %-9s | %s\n" "$i" "$rpm" "$pwm ($pwm_percent%)" "$mode_text" "$possible_assignment"
done

echo
echo "=== Aktive Lüfter-Erkennung ==="
echo "Anzahl aktiver Lüfter: ${#active_fans[@]}"
if [ ${#active_fans[@]} -gt 0 ]; then
    echo "Aktive Register: ${active_fans[*]}"
    
    # Sortiere nach RPM für bessere Zuordnung
    echo
    echo "Sortiert nach RPM (höchste zuerst):"
    for fan in "${active_fans[@]}"; do
        rpm=${rpm_values[$fan]}
        echo "  fan$fan: $rpm RPM"
    done | sort -k2 -nr
else
    echo "⚠ Keine aktiven Lüfter erkannt!"
fi

echo
echo "=== BIOS/UEFI Vergleichsanalyse ==="
echo "Für eine korrekte Zuordnung sollten Sie folgende Schritte durchführen:"
echo
echo "1. Gehen Sie ins BIOS/UEFI (F2 beim Boot)"
echo "2. Navigieren Sie zu Hardware Monitor oder Fan Control"
echo "3. Notieren Sie sich die angezeigten Lüfter und deren RPM-Werte"
echo "4. Vergleichen Sie diese mit der obigen Tabelle"
echo
echo "Typische BIOS-Anzeige für Z890 TOMAHAWK WIFI:"
echo "- CPU Fan Speed: [RPM] → sollte fan1 entsprechen"
echo "- CPU OPT Fan Speed: [RPM] → könnte fan2 oder fan8 sein"
echo "- System Fan 1 Speed: [RPM] → sollte fan3 entsprechen"
echo "- System Fan 2 Speed: [RPM] → sollte fan4 entsprechen"
echo "- usw."

echo
echo "=== Empfohlene Zuordnung basierend auf Analyse ==="

# Erstelle Zuordnungsempfehlung
cat << 'EOF'
Basierend auf der Hardware-Analyse und MSI Z890 Layout:

Standard NCT6687 → MSI Z890 TOMAHAWK WIFI Zuordnung:
fan1 (CPU Fan) → CPU_FAN1 (Hauptprozessor)
fan2 (Pump Fan) → PUMP_FAN1 oder CPU_OPT1 (AIO/Pumpe)
fan3 (System Fan #1) → SYS_FAN1
fan4 (System Fan #2) → SYS_FAN2
fan5 (System Fan #3) → SYS_FAN3
fan6 (System Fan #4) → SYS_FAN4
fan7 (System Fan #5) → SYS_FAN5
fan8 (System Fan #6) → CPU_OPT1 oder zusätzlicher Anschluss

HINWEIS: Die tatsächliche Zuordnung kann je nach BIOS-Version variieren!
EOF

echo
echo "=== Problembehebung für nicht erkannte Lüfter ==="
echo
echo "Falls Lüfter nicht erkannt werden:"
echo
echo "1. BIOS-Einstellungen überprüfen:"
echo "   - Hardware Monitor: Enabled"
echo "   - Smart Fan Control: Enabled"
echo "   - Fan Speed Control: PWM oder DC (je nach Lüfter)"
echo "   - Fan Fail Warning: Enabled (optional)"
echo
echo "2. Hardware-Verbindungen überprüfen:"
echo "   - Alle Lüfter korrekt angeschlossen?"
echo "   - 4-Pin PWM oder 3-Pin DC Lüfter?"
echo "   - Ausreichende Stromversorgung?"
echo
echo "3. Treiber-Parameter testen:"
echo "   sudo modprobe -r nct6687"
echo "   sudo modprobe nct6687 manual=1 force=1"
echo "   sensors"
echo
echo "4. Register-Debugging (erweitert):"
echo "   # Direkte Register-Werte auslesen"
echo "   for i in {1..8}; do"
echo "     echo \"Fan \$i: \$(cat $hwmon_path/fan\${i}_input 2>/dev/null || echo 'N/A')\""
echo "   done"

echo
echo "=== Nächste Schritte ==="
echo "1. Führen Sie einen BIOS-Vergleich durch"
echo "2. Erstellen Sie eine korrigierte sensors.d Konfiguration"
echo "3. Testen Sie die neue Konfiguration"
echo "4. Bei anhaltenden Problemen: Hardware-Debugging"

echo
echo "Für automatische Konfigurationserstellung führen Sie aus:"
echo "bash create_corrected_z890_config.sh"

echo
echo "=== Hardware-Mapping-Analyse abgeschlossen ==="
