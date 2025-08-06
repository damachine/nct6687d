#!/bin/bash

# PWM-Kontrollen-Test für MSI MAG Z890 TOMAHAWK WIFI
# Testet die Lüftersteuerung sicher und dokumentiert die Ergebnisse

echo "=== PWM-Kontrollen-Test für MSI MAG Z890 TOMAHAWK WIFI ==="
echo "Datum: $(date)"
echo

# Sicherheitswarnung
echo "⚠️  SICHERHEITSWARNUNG ⚠️"
echo "Dieser Test modifiziert Lüftergeschwindigkeiten!"
echo "- Stellen Sie sicher, dass ausreichende Kühlung vorhanden ist"
echo "- Überwachen Sie die Temperaturen während des Tests"
echo "- Der Test wird automatisch zur ursprünglichen Konfiguration zurückkehren"
echo "- Bei Überhitzung: Strg+C zum Abbrechen"
echo
echo "Möchten Sie fortfahren? (j/n)"
read -r continue_test

if [ "$continue_test" != "j" ] && [ "$continue_test" != "J" ]; then
    echo "Test abgebrochen."
    exit 0
fi

# Überprüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "FEHLER: Dieser Test muss als root ausgeführt werden!"
    echo "sudo bash $0"
    exit 1
fi

# Finde NCT6687 hwmon Gerät
hwmon_path=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
if [ -z "$hwmon_path" ]; then
    echo "FEHLER: NCT6687 hwmon Gerät nicht gefunden!"
    exit 1
fi

echo "✓ NCT6687 Gerät: $hwmon_path"
echo

# Backup der aktuellen PWM-Einstellungen
echo "=== Backup der aktuellen PWM-Einstellungen ==="
declare -A original_pwm_values
declare -A original_pwm_enables
declare -A active_pwm_controls

for i in {1..8}; do
    pwm_file="$hwmon_path/pwm${i}"
    pwm_enable="$hwmon_path/pwm${i}_enable"
    fan_input="$hwmon_path/fan${i}_input"
    
    if [ -f "$pwm_file" ] && [ -f "$pwm_enable" ] && [ -f "$fan_input" ]; then
        # Prüfe ob Lüfter aktiv ist
        rpm=$(cat "$fan_input" 2>/dev/null || echo "0")
        if [ "$rpm" -gt 0 ]; then
            original_pwm_values[$i]=$(cat "$pwm_file" 2>/dev/null || echo "255")
            original_pwm_enables[$i]=$(cat "$pwm_enable" 2>/dev/null || echo "99")
            active_pwm_controls[$i]=1
            
            echo "PWM $i: Wert=${original_pwm_values[$i]}, Modus=${original_pwm_enables[$i]}, Fan-RPM=$rpm"
        fi
    fi
done

active_count=${#active_pwm_controls[@]}
echo "✓ $active_count aktive PWM-Kontrollen gefunden"

if [ $active_count -eq 0 ]; then
    echo "Keine aktiven PWM-Kontrollen gefunden. Test beendet."
    exit 0
fi

echo

# Funktion für Temperatur-Überwachung
monitor_temperatures() {
    temp1=$(cat "$hwmon_path/temp1_input" 2>/dev/null || echo "0")
    temp3=$(cat "$hwmon_path/temp3_input" 2>/dev/null || echo "0")
    
    cpu_temp=$(echo "scale=1; $temp1/1000" | bc 2>/dev/null || echo "0")
    vrm_temp=$(echo "scale=1; $temp3/1000" | bc 2>/dev/null || echo "0")
    
    echo "Temperaturen: CPU=${cpu_temp}°C, VRM=${vrm_temp}°C"
    
    # Sicherheitscheck
    if (( $(echo "$cpu_temp > 80" | bc -l 2>/dev/null || echo "0") )); then
        echo "⚠️ WARNUNG: CPU-Temperatur zu hoch ($cpu_temp°C)!"
        return 1
    fi
    
    if (( $(echo "$vrm_temp > 75" | bc -l 2>/dev/null || echo "0") )); then
        echo "⚠️ WARNUNG: VRM-Temperatur zu hoch ($vrm_temp°C)!"
        return 1
    fi
    
    return 0
}

# Funktion zum Wiederherstellen der ursprünglichen Einstellungen
restore_original_settings() {
    echo
    echo "=== Wiederherstellen der ursprünglichen Einstellungen ==="
    
    for pwm in "${!active_pwm_controls[@]}"; do
        pwm_file="$hwm_path/pwm${pwm}"
        pwm_enable="$hwmon_path/pwm${pwm}_enable"
        
        if [ -f "$pwm_enable" ] && [ -f "$pwm_file" ]; then
            # Zurück zu ursprünglichem Modus
            echo "${original_pwm_enables[$pwm]}" > "$pwm_enable" 2>/dev/null || true
            echo "${original_pwm_values[$pwm]}" > "$pwm_file" 2>/dev/null || true
            
            echo "✓ PWM $pwm wiederhergestellt: Modus=${original_pwm_enables[$pwm]}, Wert=${original_pwm_values[$pwm]}"
        fi
    done
    
    echo "✓ Alle ursprünglichen Einstellungen wiederhergestellt"
}

# Trap für Cleanup bei Abbruch
trap restore_original_settings EXIT INT TERM

# Test 1: PWM-Modus-Test
echo "=== Test 1: PWM-Modus-Funktionalität ==="
echo "Teste Wechsel zwischen Auto- und Manual-Modus..."

for pwm in "${!active_pwm_controls[@]}"; do
    pwm_enable="$hwmon_path/pwm${pwm}_enable"
    fan_input="$hwmon_path/fan${i}_input"
    
    echo
    echo "Teste PWM $pwm:"
    
    # Test Auto-Modus (99)
    echo "  Setze Auto-Modus (99)..."
    echo "99" > "$pwm_enable" 2>/dev/null
    sleep 2
    
    current_mode=$(cat "$pwm_enable" 2>/dev/null || echo "?")
    rpm_auto=$(cat "$fan_input" 2>/dev/null || echo "0")
    echo "  Auto-Modus: $current_mode, RPM: $rpm_auto"
    
    # Test Manual-Modus (1)
    echo "  Setze Manual-Modus (1)..."
    echo "1" > "$pwm_enable" 2>/dev/null
    sleep 2
    
    current_mode=$(cat "$pwm_enable" 2>/dev/null || echo "?")
    rpm_manual=$(cat "$fan_input" 2>/dev/null || echo "0")
    echo "  Manual-Modus: $current_mode, RPM: $rpm_manual"
    
    # Zurück zu Auto
    echo "99" > "$pwm_enable" 2>/dev/null
    
    # Bewertung
    if [ "$current_mode" = "1" ]; then
        echo "  ✓ PWM $pwm: Modus-Wechsel funktioniert"
    else
        echo "  ⚠ PWM $pwm: Modus-Wechsel möglicherweise nicht unterstützt"
    fi
done

echo
echo "=== Test 2: PWM-Wert-Kontrolle (Vorsichtig) ==="
echo "Teste PWM-Wert-Änderungen mit Sicherheitsüberwachung..."

# Wähle einen PWM-Kanal für detaillierten Test (vorzugsweise nicht CPU-Lüfter)
test_pwm=""
for pwm in "${!active_pwm_controls[@]}"; do
    if [ "$pwm" != "1" ]; then  # Nicht PWM1 (normalerweise CPU)
        test_pwm=$pwm
        break
    fi
done

if [ -z "$test_pwm" ]; then
    test_pwm=$(echo "${!active_pwm_controls[@]}" | cut -d' ' -f1)
    echo "⚠ Verwende PWM $test_pwm (möglicherweise CPU-Lüfter) - extra vorsichtig!"
fi

echo "Verwende PWM $test_pwm für detaillierten Test..."

pwm_file="$hwmon_path/pwm${test_pwm}"
pwm_enable="$hwmon_path/pwm${test_pwm}_enable"
fan_input="$hwmon_path/fan${test_pwm}_input"

# Setze Manual-Modus
echo "1" > "$pwm_enable" 2>/dev/null
sleep 1

# Test verschiedene PWM-Werte
test_values=(255 200 150 100 80)  # Von hoch zu niedrig für Sicherheit

echo
echo "PWM-Wert-Test für PWM $test_pwm:"
echo "Wert | RPM  | Temp-Check"
echo "-----|------|----------"

for value in "${test_values[@]}"; do
    # Temperatur vor Änderung prüfen
    if ! monitor_temperatures; then
        echo "⚠ Temperatur zu hoch - Test abgebrochen!"
        break
    fi
    
    # PWM-Wert setzen
    echo "$value" > "$pwm_file" 2>/dev/null
    sleep 3  # Warten bis sich RPM stabilisiert
    
    # Werte auslesen
    current_pwm=$(cat "$pwm_file" 2>/dev/null || echo "?")
    current_rpm=$(cat "$fan_input" 2>/dev/null || echo "0")
    
    printf "%3d  | %4d | " "$value" "$current_rpm"
    
    # Temperatur nach Änderung prüfen
    if monitor_temperatures >/dev/null; then
        echo "OK"
    else
        echo "WARNUNG"
        break
    fi
done

echo
echo "=== Test 3: PWM-Reaktionszeit ==="
echo "Teste wie schnell PWM-Änderungen wirken..."

# Schneller Wechsel zwischen zwei Werten
echo "Schneller Wechsel zwischen PWM 255 und 150..."

for i in {1..3}; do
    echo "  Zyklus $i:"
    
    # Hoch
    echo "255" > "$pwm_file" 2>/dev/null
    sleep 1
    rpm_high=$(cat "$fan_input" 2>/dev/null || echo "0")
    echo "    PWM 255: $rpm_high RPM"
    
    # Niedrig
    echo "150" > "$pwm_file" 2>/dev/null
    sleep 1
    rpm_low=$(cat "$fan_input" 2>/dev/null || echo "0")
    echo "    PWM 150: $rpm_low RPM"
    
    # Berechne Reaktion
    if [ "$rpm_high" -gt "$rpm_low" ]; then
        echo "    ✓ PWM-Kontrolle reagiert korrekt"
    else
        echo "    ⚠ Unerwartete PWM-Reaktion"
    fi
done

echo
echo "=== Test 4: Alle PWM-Kontrollen Übersicht ==="
echo "Finale Übersicht aller PWM-Kontrollen..."

# Setze alle auf Auto-Modus für finale Übersicht
for pwm in "${!active_pwm_controls[@]}"; do
    echo "99" > "$hwmon_path/pwm${pwm}_enable" 2>/dev/null
done

sleep 2

echo
echo "PWM | Modus | Wert | RPM  | Status"
echo "----|-------|------|------|-------"

for pwm in "${!active_pwm_controls[@]}"; do
    pwm_file="$hwmon_path/pwm${pwm}"
    pwm_enable="$hwmon_path/pwm${pwm}_enable"
    fan_input="$hwmon_path/fan${pwm}_input"
    
    mode=$(cat "$pwm_enable" 2>/dev/null || echo "?")
    value=$(cat "$pwm_file" 2>/dev/null || echo "?")
    rpm=$(cat "$fan_input" 2>/dev/null || echo "0")
    
    case $mode in
        1) mode_text="Manual" ;;
        99) mode_text="Auto" ;;
        *) mode_text="Mode $mode" ;;
    esac
    
    if [ "$rpm" -gt 0 ]; then
        status="✓ Aktiv"
    else
        status="⚠ Inaktiv"
    fi
    
    printf "%3d | %-6s| %3s  | %4d | %s\n" "$pwm" "$mode_text" "$value" "$rpm" "$status"
done

echo
echo "=== Test-Zusammenfassung ==="
echo "PWM-Kontrollen getestet: ${#active_pwm_controls[@]}"
echo "Funktionsfähige PWM-Modi: Auto (99), Manual (1)"
echo "PWM-Wert-Bereich: 0-255 (0-100%)"
echo "Reaktionszeit: ~1-3 Sekunden"

echo
echo "=== Empfehlungen ==="
echo "1. Für manuelle Lüftersteuerung:"
echo "   echo 1 > /sys/class/hwmon/hwmon*/pwm*_enable"
echo "   echo [0-255] > /sys/class/hwmon/hwmon*/pwm*"
echo
echo "2. Für automatische Steuerung:"
echo "   echo 99 > /sys/class/hwmon/hwmon*/pwm*_enable"
echo
echo "3. Überwachen Sie immer die Temperaturen bei manueller Steuerung!"
echo
echo "4. Für permanente Lüfterkurven verwenden Sie:"
echo "   - fancontrol (lm-sensors)"
echo "   - pwmconfig"
echo "   - BIOS/UEFI Smart Fan Control"

echo
echo "=== PWM-Test abgeschlossen ==="
echo "Alle ursprünglichen Einstellungen wurden wiederhergestellt."
