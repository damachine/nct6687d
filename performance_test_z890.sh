#!/bin/bash

# Performance-Test Script für NCT6687D auf MSI MAG Z890 TOMAHAWK WIFI
# Testet Sensor-Performance, Stabilität und Funktionalität

echo "=== NCT6687D Performance-Test für MSI MAG Z890 TOMAHAWK WIFI ==="
echo "Datum: $(date)"
echo "Kernel: $(uname -r)"
echo

# Überprüfen ob notwendige Tools verfügbar sind
missing_tools=()
for tool in bc sensors; do
    if ! command -v $tool &> /dev/null; then
        missing_tools+=($tool)
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "WARNUNG: Fehlende Tools: ${missing_tools[*]}"
    echo "Installieren Sie mit: sudo pacman -S bc lm_sensors"
    echo
fi

# Überprüfe NCT6687 Status
if ! lsmod | grep -q nct6687; then
    echo "FEHLER: nct6687 Modul nicht geladen!"
    echo "Laden Sie es mit: sudo modprobe nct6687 manual=1"
    exit 1
fi

hwmon_path=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
if [ -z "$hwmon_path" ]; then
    echo "FEHLER: NCT6687 hwmon Gerät nicht gefunden!"
    exit 1
fi

echo "✓ NCT6687 Gerät gefunden: $hwmon_path"
echo

# Funktion für Zeitstempel
timestamp() {
    date '+%H:%M:%S.%3N' 2>/dev/null || date '+%H:%M:%S'
}

echo "=== 1. Baseline-Messung (10 Sekunden) ==="
echo "Sammle Baseline-Daten für Stabilität und Konsistenz..."
echo

baseline_file="/tmp/nct6687_baseline_$(date +%s).txt"
echo "Zeitstempel,CPU_Temp,System_Temp,VCore,+12V,Fan1_RPM" > "$baseline_file"

for i in {1..10}; do
    timestamp_val=$(timestamp)
    
    # Sammle Sensor-Daten
    cpu_temp=$(cat "$hwmon_path/temp1_input" 2>/dev/null | head -1)
    sys_temp=$(cat "$hwmon_path/temp2_input" 2>/dev/null | head -1)
    vcore=$(cat "$hwmon_path/in2_input" 2>/dev/null | head -1)
    v12=$(cat "$hwmon_path/in0_input" 2>/dev/null | head -1)
    fan1=$(cat "$hwmon_path/fan1_input" 2>/dev/null | head -1)
    
    # Konvertiere zu lesbaren Werten
    cpu_temp_c=$(echo "scale=1; ${cpu_temp:-0}/1000" | bc 2>/dev/null || echo "0")
    sys_temp_c=$(echo "scale=1; ${sys_temp:-0}/1000" | bc 2>/dev/null || echo "0")
    vcore_v=$(echo "scale=3; ${vcore:-0}/1000" | bc 2>/dev/null || echo "0")
    v12_v=$(echo "scale=2; ${v12:-0}*12/1000" | bc 2>/dev/null || echo "0")
    
    echo "$timestamp_val,$cpu_temp_c,$sys_temp_c,$vcore_v,$v12_v,${fan1:-0}" >> "$baseline_file"
    
    printf "Messung %2d: CPU: %5.1f°C, System: %5.1f°C, VCore: %5.3fV, +12V: %5.2fV, Fan1: %4d RPM\n" \
           "$i" "$cpu_temp_c" "$sys_temp_c" "$vcore_v" "$v12_v" "${fan1:-0}"
    
    sleep 1
done

echo "✓ Baseline-Daten gespeichert in: $baseline_file"
echo

echo "=== 2. Sensor-Update-Rate Test ==="
echo "Teste Geschwindigkeit der Sensor-Abfragen..."

# Test verschiedene Abfrage-Methoden
echo "Test 1: Direkte hwmon-Dateien (10 Abfragen)"
start_time=$(date +%s.%N 2>/dev/null || date +%s)
for i in {1..10}; do
    cat "$hwmon_path"/temp*_input "$hwmon_path"/in*_input "$hwmon_path"/fan*_input > /dev/null 2>&1
done
end_time=$(date +%s.%N 2>/dev/null || date +%s)
direct_duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "?")
echo "Direkte Abfrage: ${direct_duration}s ($(echo "scale=3; $direct_duration/10" | bc 2>/dev/null || echo "?")s pro Abfrage)"

echo "Test 2: sensors-Befehl (5 Abfragen)"
start_time=$(date +%s.%N 2>/dev/null || date +%s)
for i in {1..5}; do
    sensors > /dev/null 2>&1
done
end_time=$(date +%s.%N 2>/dev/null || date +%s)
sensors_duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "?")
echo "sensors-Befehl: ${sensors_duration}s ($(echo "scale=3; $sensors_duration/5" | bc 2>/dev/null || echo "?")s pro Abfrage)"
echo

echo "=== 3. Stabilität-Test (30 Sekunden) ==="
echo "Teste Sensor-Stabilität unter kontinuierlicher Abfrage..."

stable_count=0
error_count=0
temp_readings=()
voltage_readings=()

for i in {1..30}; do
    # Lese kritische Sensoren
    temp1=$(cat "$hwmon_path/temp1_input" 2>/dev/null)
    in0=$(cat "$hwmon_path/in0_input" 2>/dev/null)
    
    if [ -n "$temp1" ] && [ -n "$in0" ]; then
        temp_readings+=($temp1)
        voltage_readings+=($in0)
        ((stable_count++))
        printf "."
    else
        ((error_count++))
        printf "E"
    fi
    
    sleep 1
done

echo
echo "Stabilität: $stable_count/30 erfolgreiche Abfragen, $error_count Fehler"

# Berechne Statistiken
if [ ${#temp_readings[@]} -gt 0 ]; then
    temp_sum=0
    for temp in "${temp_readings[@]}"; do
        temp_sum=$((temp_sum + temp))
    done
    temp_avg=$(echo "scale=1; $temp_sum/${#temp_readings[@]}/1000" | bc 2>/dev/null || echo "?")
    echo "Durchschnittstemperatur: ${temp_avg}°C"
fi

if [ ${#voltage_readings[@]} -gt 0 ]; then
    volt_sum=0
    for volt in "${voltage_readings[@]}"; do
        volt_sum=$((volt_sum + volt))
    done
    volt_avg=$(echo "scale=2; $volt_sum*12/${#voltage_readings[@]}/1000" | bc 2>/dev/null || echo "?")
    echo "Durchschnitt +12V: ${volt_avg}V"
fi
echo

echo "=== 4. PWM-Funktionalitäts-Test ==="
echo "Teste PWM-Kontrollen (VORSICHTIG - nur Lese-Test)..."

pwm_functional=0
pwm_total=0

for i in {1..8}; do
    pwm_file="$hwmon_path/pwm${i}"
    pwm_enable="$hwmon_path/pwm${i}_enable"
    
    if [ -f "$pwm_file" ] && [ -f "$pwm_enable" ]; then
        ((pwm_total++))
        
        pwm_val=$(cat "$pwm_file" 2>/dev/null)
        enable_val=$(cat "$pwm_enable" 2>/dev/null)
        
        if [ -n "$pwm_val" ] && [ -n "$enable_val" ]; then
            ((pwm_functional++))
            pwm_percent=$(echo "scale=1; $pwm_val*100/255" | bc 2>/dev/null || echo "?")
            
            case $enable_val in
                1) mode="Manual" ;;
                99) mode="Auto" ;;
                *) mode="Mode $enable_val" ;;
            esac
            
            echo "PWM $i: $pwm_val (${pwm_percent}%) - $mode"
        else
            echo "PWM $i: Lesefehler"
        fi
    fi
done

echo "PWM-Kontrollen: $pwm_functional/$pwm_total funktional"
echo

echo "=== 5. Speicher- und CPU-Verbrauch ==="
echo "Teste Ressourcenverbrauch des nct6687 Treibers..."

# Prozess-Informationen
nct_processes=$(ps aux | grep -E "(nct6687|hwmon)" | grep -v grep)
if [ -n "$nct_processes" ]; then
    echo "NCT6687-bezogene Prozesse:"
    echo "$nct_processes" | sed 's/^/  /'
else
    echo "Keine spezifischen NCT6687-Prozesse gefunden (normal für Kernel-Module)"
fi

# Kernel-Modul Speicherverbrauch
if [ -f "/proc/modules" ]; then
    nct_module_info=$(grep nct6687 /proc/modules 2>/dev/null)
    if [ -n "$nct_module_info" ]; then
        module_size=$(echo "$nct_module_info" | awk '{print $2}')
        echo "Kernel-Modul Speicherverbrauch: $module_size Bytes"
    fi
fi
echo

echo "=== 6. Vergleich mit Baseline ==="
if [ -f "baseline_sensors.txt" ]; then
    echo "Vergleiche mit ursprünglicher Baseline (nct6683)..."
    
    baseline_sensor_count=$(grep -c ":" baseline_sensors.txt 2>/dev/null || echo "0")
    current_sensor_count=$(sensors | grep -c ":" 2>/dev/null || echo "0")
    
    echo "Sensor-Anzahl:"
    echo "  Baseline (nct6683): $baseline_sensor_count"
    echo "  Aktuell (nct6687): $current_sensor_count"
    
    if [ "$current_sensor_count" -gt "$baseline_sensor_count" ]; then
        improvement=$((current_sensor_count - baseline_sensor_count))
        echo "  ✓ Verbesserung: +$improvement Sensoren"
    elif [ "$current_sensor_count" -eq "$baseline_sensor_count" ]; then
        echo "  = Gleiche Anzahl Sensoren"
    else
        reduction=$((baseline_sensor_count - current_sensor_count))
        echo "  ⚠ Reduzierung: -$reduction Sensoren"
    fi
else
    echo "Keine Baseline-Datei gefunden (baseline_sensors.txt)"
fi
echo

echo "=== 7. Stress-Test (optional) ==="
echo "Führe kurzen Stress-Test durch um Sensor-Verhalten unter Last zu testen..."

# Kurzer CPU-Stress (falls stress-ng verfügbar)
if command -v stress-ng &> /dev/null; then
    echo "Starte 10-Sekunden CPU-Stress-Test..."
    
    # Vor Stress
    temp_before=$(cat "$hwmon_path/temp1_input" 2>/dev/null)
    temp_before_c=$(echo "scale=1; ${temp_before:-0}/1000" | bc 2>/dev/null || echo "0")
    
    # Stress starten
    stress-ng --cpu 2 --timeout 10s > /dev/null 2>&1 &
    stress_pid=$!
    
    # Überwache Temperatur während Stress
    max_temp=0
    for i in {1..10}; do
        current_temp=$(cat "$hwmon_path/temp1_input" 2>/dev/null || echo "0")
        if [ "$current_temp" -gt "$max_temp" ]; then
            max_temp=$current_temp
        fi
        sleep 1
    done
    
    wait $stress_pid 2>/dev/null
    
    # Nach Stress
    sleep 2
    temp_after=$(cat "$hwmon_path/temp1_input" 2>/dev/null)
    temp_after_c=$(echo "scale=1; ${temp_after:-0}/1000" | bc 2>/dev/null || echo "0")
    max_temp_c=$(echo "scale=1; $max_temp/1000" | bc 2>/dev/null || echo "0")
    
    echo "Temperatur vor Stress: ${temp_before_c}°C"
    echo "Maximale Temperatur: ${max_temp_c}°C"
    echo "Temperatur nach Stress: ${temp_after_c}°C"
    
    temp_rise=$(echo "scale=1; $max_temp_c - $temp_before_c" | bc 2>/dev/null || echo "0")
    echo "Temperaturanstieg: ${temp_rise}°C"
    
    if (( $(echo "$temp_rise > 0" | bc -l 2>/dev/null || echo "0") )); then
        echo "✓ Sensor reagiert auf Temperaturänderungen"
    else
        echo "⚠ Sensor zeigt keine Temperaturänderung"
    fi
else
    echo "stress-ng nicht verfügbar - Stress-Test übersprungen"
    echo "Installieren mit: sudo pacman -S stress-ng"
fi
echo

echo "=== Performance-Test Zusammenfassung ==="
echo "Baseline-Messungen: 10 Datenpunkte gesammelt"
echo "Sensor-Update-Rate: Getestet"
echo "Stabilität: $stable_count/30 erfolgreiche Abfragen"
echo "PWM-Funktionalität: $pwm_functional/$pwm_total Kontrollen"
echo "Ressourcenverbrauch: Minimal (Kernel-Modul)"

if [ $stable_count -ge 28 ]; then
    echo "✓ Ausgezeichnete Stabilität"
elif [ $stable_count -ge 25 ]; then
    echo "✓ Gute Stabilität"
else
    echo "⚠ Stabilitätsprobleme erkannt"
fi

echo
echo "=== Empfehlungen ==="
if [ $error_count -gt 2 ]; then
    echo "• Hohe Fehlerrate - überprüfen Sie Hardware-Verbindungen"
fi

if [ $pwm_functional -eq 0 ]; then
    echo "• Keine PWM-Kontrollen verfügbar - BIOS-Einstellungen prüfen"
fi

echo "• Baseline-Daten verfügbar in: $baseline_file"
echo "• Für kontinuierliche Überwachung: watch -n 1 sensors"
echo "• Für detaillierte Logs: dmesg | grep nct6687"

echo
echo "=== Performance-Test abgeschlossen ==="
