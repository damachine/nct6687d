#!/bin/bash

# Erstellt eine korrigierte sensors.d Konfiguration für MSI MAG Z890 TOMAHAWK WIFI
# Basierend auf Hardware-Analyse und BIOS-Vergleich

echo "=== Korrigierte Z890 Sensor-Konfiguration erstellen ==="
echo "Datum: $(date)"
echo

# Überprüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "WARNUNG: Als root ausführen für vollständigen Zugriff"
    echo "sudo bash $0"
    echo
fi

# Finde NCT6687 hwmon Gerät
hwmon_path=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
if [ -z "$hwmon_path" ]; then
    echo "FEHLER: NCT6687 hwmon Gerät nicht gefunden!"
    exit 1
fi

echo "✓ NCT6687 Gerät: $hwmon_path"
echo

# Analysiere aktuelle Hardware
echo "=== Aktuelle Hardware-Analyse ==="
declare -a active_fans
declare -a fan_rpms
declare -a fan_pwms

for i in {1..8}; do
    fan_input="$hwmon_path/fan${i}_input"
    pwm_file="$hwmon_path/pwm${i}"
    
    if [ -f "$fan_input" ]; then
        rpm=$(cat "$fan_input" 2>/dev/null || echo "0")
        fan_rpms[$i]=$rpm
        
        if [ "$rpm" -gt 0 ]; then
            active_fans+=($i)
            echo "Fan $i: $rpm RPM (AKTIV)"
        else
            echo "Fan $i: $rpm RPM (inaktiv)"
        fi
    fi
    
    if [ -f "$pwm_file" ]; then
        pwm=$(cat "$pwm_file" 2>/dev/null || echo "0")
        fan_pwms[$i]=$pwm
    fi
done

echo
echo "Aktive Lüfter gefunden: ${#active_fans[@]} (Register: ${active_fans[*]})"

# Interaktive Zuordnung (falls gewünscht)
echo
echo "=== Lüfter-Zuordnung konfigurieren ==="
echo "Möchten Sie die Lüfter-Zuordnung interaktiv konfigurieren? (j/n)"
read -r interactive

declare -A fan_labels
declare -A fan_descriptions

if [ "$interactive" = "j" ] || [ "$interactive" = "J" ]; then
    echo
    echo "Bitte ordnen Sie jeden aktiven Lüfter dem entsprechenden Motherboard-Anschluss zu:"
    echo
    
    for fan in "${active_fans[@]}"; do
        rpm=${fan_rpms[$fan]}
        echo "Fan $fan (aktuell $rpm RPM):"
        echo "1) CPU_FAN1 (Hauptprozessor)"
        echo "2) CPU_OPT1 (Optionaler CPU/AIO)"
        echo "3) SYS_FAN1 (System-Lüfter 1)"
        echo "4) SYS_FAN2 (System-Lüfter 2)"
        echo "5) SYS_FAN3 (System-Lüfter 3)"
        echo "6) SYS_FAN4 (System-Lüfter 4)"
        echo "7) SYS_FAN5 (System-Lüfter 5)"
        echo "8) PUMP_FAN1 (AIO-Pumpe)"
        echo "9) Unbekannt/Andere"
        echo -n "Wählen Sie (1-9): "
        read -r choice
        
        case $choice in
            1) fan_labels[$fan]="CPU_FAN1"; fan_descriptions[$fan]="CPU Hauptlüfter" ;;
            2) fan_labels[$fan]="CPU_OPT1"; fan_descriptions[$fan]="CPU Optional/AIO" ;;
            3) fan_labels[$fan]="SYS_FAN1"; fan_descriptions[$fan]="System Lüfter 1" ;;
            4) fan_labels[$fan]="SYS_FAN2"; fan_descriptions[$fan]="System Lüfter 2" ;;
            5) fan_labels[$fan]="SYS_FAN3"; fan_descriptions[$fan]="System Lüfter 3" ;;
            6) fan_labels[$fan]="SYS_FAN4"; fan_descriptions[$fan]="System Lüfter 4" ;;
            7) fan_labels[$fan]="SYS_FAN5"; fan_descriptions[$fan]="System Lüfter 5" ;;
            8) fan_labels[$fan]="PUMP_FAN1"; fan_descriptions[$fan]="AIO Pumpe" ;;
            *) fan_labels[$fan]="FAN_$fan"; fan_descriptions[$fan]="Unbekannter Lüfter" ;;
        esac
        echo "✓ Fan $fan → ${fan_labels[$fan]} (${fan_descriptions[$fan]})"
        echo
    done
else
    echo "Verwende automatische Zuordnung basierend auf RPM-Werten..."
    
    # Automatische Zuordnung basierend auf typischen RPM-Bereichen
    for fan in "${active_fans[@]}"; do
        rpm=${fan_rpms[$fan]}
        
        if [ "$rpm" -gt 2000 ]; then
            fan_labels[$fan]="CPU_FAN1"
            fan_descriptions[$fan]="CPU Hauptlüfter"
        elif [ "$rpm" -gt 1500 ]; then
            fan_labels[$fan]="PUMP_FAN1"
            fan_descriptions[$fan]="AIO Pumpe"
        else
            # Zuordnung basierend auf Register-Nummer für System-Lüfter
            case $fan in
                3) fan_labels[$fan]="SYS_FAN1"; fan_descriptions[$fan]="System Lüfter 1" ;;
                4) fan_labels[$fan]="SYS_FAN2"; fan_descriptions[$fan]="System Lüfter 2" ;;
                5) fan_labels[$fan]="SYS_FAN3"; fan_descriptions[$fan]="System Lüfter 3" ;;
                6) fan_labels[$fan]="SYS_FAN4"; fan_descriptions[$fan]="System Lüfter 4" ;;
                7) fan_labels[$fan]="SYS_FAN5"; fan_descriptions[$fan]="System Lüfter 5" ;;
                8) fan_labels[$fan]="CPU_OPT1"; fan_descriptions[$fan]="CPU Optional" ;;
                *) fan_labels[$fan]="SYS_FAN$fan"; fan_descriptions[$fan]="System Lüfter $fan" ;;
            esac
        fi
        
        echo "✓ Fan $fan ($rpm RPM) → ${fan_labels[$fan]} (${fan_descriptions[$fan]})"
    done
fi

# Backup der aktuellen Konfiguration
echo
echo "=== Backup der aktuellen Konfiguration ==="
if [ -f "/etc/sensors.d/Z890_TOMAHAWK_WIFI.conf" ]; then
    backup_file="/etc/sensors.d/Z890_TOMAHAWK_WIFI.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "/etc/sensors.d/Z890_TOMAHAWK_WIFI.conf" "$backup_file"
    echo "✓ Backup erstellt: $backup_file"
else
    echo "Keine vorherige Konfiguration gefunden"
fi

# Erstelle korrigierte Konfigurationsdatei
config_file="/tmp/Z890_TOMAHAWK_WIFI_corrected.conf"
echo "=== Erstelle korrigierte Konfiguration ==="

cat > "$config_file" << EOF
# MSI MAG Z890 TOMAHAWK WIFI - Korrigierte Sensor-Konfiguration
# Automatisch generiert am $(date)
# Basierend auf Hardware-Analyse und Lüfter-Zuordnung
#
# Installation:
# sudo cp $config_file /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf
# sudo sensors -s
# sensors

chip "nct6687-*"
    # Spannungen - Intel Z890 spezifische Zuordnung
    label in0         "+12V"          # 12V Hauptversorgung
    label in1         "+5V"           # 5V Standby
    label in2         "VCore"         # CPU Kernspannung
    label in3         "CPU SA"        # CPU System Agent
    label in4         "DRAM"          # Arbeitsspeicher-Spannung
    label in5         "CPU I/O"       # CPU I/O Spannung
    label in6         "CPU AUX"       # CPU Hilfsspannung
    label in7         "PCH Core"      # Chipsatz-Kernspannung
    label in8         "+3.3V"         # 3.3V Rail
    label in9         "VTT"           # Terminierungsspannung
    label in10        "VCCIO"         # I/O Spannung
    label in11        "VSB"           # Standby-Spannung
    label in12        "AVSB"          # Auxiliary Standby
    label in13        "VBat"          # CMOS Batterie

    # Temperaturen - Z890 Motherboard Layout
    label temp1       "CPU Package"   # CPU Gesamttemperatur
    label temp2       "System"        # Systemtemperatur
    label temp3       "VRM MOS"       # Spannungsregler
    label temp4       "PCH"           # Platform Controller Hub
    label temp5       "CPU Socket"    # CPU Sockel
    label temp6       "M.2_1"         # M.2 Slot 1
    label temp7       "M.2_2"         # M.2 Slot 2

EOF

# Füge Lüfter-Labels basierend auf Analyse hinzu
echo "    # Lüfter - Korrigierte Zuordnung basierend auf Hardware-Analyse" >> "$config_file"

for i in {1..8}; do
    if [[ " ${active_fans[*]} " =~ " $i " ]]; then
        # Aktiver Lüfter - verwende korrigierte Zuordnung
        label="${fan_labels[$i]}"
        description="${fan_descriptions[$i]}"
        echo "    label fan$i        \"$label\"       # $description" >> "$config_file"
    else
        # Inaktiver Lüfter - Standard-Label aber auskommentiert
        echo "    # label fan$i        \"SYS_FAN$i\"     # Nicht angeschlossen" >> "$config_file"
    fi
done

# Füge PWM-Labels hinzu
echo "" >> "$config_file"
echo "    # PWM-Kontrollen - Entsprechend den Lüfter-Zuordnungen" >> "$config_file"

for i in {1..8}; do
    if [[ " ${active_fans[*]} " =~ " $i " ]]; then
        label="${fan_labels[$i]}"
        echo "    label pwm$i        \"$label PWM\"" >> "$config_file"
    else
        echo "    # label pwm$i        \"SYS_FAN$i PWM\"  # Nicht angeschlossen" >> "$config_file"
    fi
done

# Füge Spannungs-Multiplier hinzu
cat >> "$config_file" << 'EOF'

    # Spannungs-Multiplier (basierend auf Z890 Hardware)
    compute in0       (@ * 12), (@ / 12)    # +12V
    compute in1       (@ * 5), (@ / 5)      # +5V
    compute in4       (@ * 2), (@ / 2)      # DRAM (DDR5: ~1.1V)
    # VCore, CPU SA, CPU I/O normalerweise 1:1
    # compute in8       (@ * 1), (@ / 1)    # +3.3V falls nötig

    # Ignoriere unzuverlässige oder nicht verwendete Sensoren
    # Aktivieren Sie diese Zeilen bei Bedarf:
    # ignore in9        # VTT falls nicht verwendet
    # ignore in10       # VCCIO falls unzuverlässig
    # ignore in11       # VSB falls nicht benötigt
    # ignore in12       # AVSB falls nicht benötigt
    # ignore in13       # VBat falls unzuverlässig
    # ignore temp6      # M.2_1 falls kein Sensor
    # ignore temp7      # M.2_2 falls kein Sensor

    # Temperatur-Limits (optional)
    set temp1_max     85              # CPU max
    set temp1_crit    95              # CPU kritisch
    set temp3_max     80              # VRM max
    set temp4_max     70              # PCH max

EOF

# Füge Lüfter-Mindestdrehzahlen nur für aktive Lüfter hinzu
echo "    # Lüfter-Mindestdrehzahlen (nur für aktive Lüfter)" >> "$config_file"
for fan in "${active_fans[@]}"; do
    case "${fan_labels[$fan]}" in
        *CPU*|*PUMP*) echo "    set fan${fan}_min      300             # ${fan_labels[$fan]} min" >> "$config_file" ;;
        *) echo "    set fan${fan}_min      200             # ${fan_labels[$fan]} min" >> "$config_file" ;;
    esac
done

echo "✓ Korrigierte Konfiguration erstellt: $config_file"

# Zeige Zusammenfassung
echo
echo "=== Konfigurationszusammenfassung ==="
echo "Aktive Lüfter-Zuordnungen:"
for fan in "${active_fans[@]}"; do
    rpm=${fan_rpms[$fan]}
    label="${fan_labels[$fan]}"
    description="${fan_descriptions[$fan]}"
    echo "  fan$fan → $label ($description) - $rpm RPM"
done

echo
echo "=== Installation der korrigierten Konfiguration ==="
echo "Möchten Sie die korrigierte Konfiguration jetzt installieren? (j/n)"
read -r install_now

if [ "$install_now" = "j" ] || [ "$install_now" = "J" ]; then
    # Installiere neue Konfiguration
    cp "$config_file" "/etc/sensors.d/Z890_TOMAHAWK_WIFI.conf"
    echo "✓ Konfiguration installiert: /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf"
    
    # Lade Sensor-Konfiguration neu
    sensors -s
    echo "✓ Sensor-Konfiguration neu geladen"
    
    echo
    echo "=== Test der neuen Konfiguration ==="
    echo "Neue sensors-Ausgabe:"
    sensors | grep -A 30 nct6687
    
    echo
    echo "✓ Installation abgeschlossen!"
    echo
    echo "Überprüfen Sie die Ausgabe und vergleichen Sie mit BIOS-Werten."
    echo "Bei Problemen können Sie das Backup wiederherstellen:"
    if [ -n "$backup_file" ]; then
        echo "  sudo cp $backup_file /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf"
        echo "  sudo sensors -s"
    fi
else
    echo "Konfiguration nicht installiert."
    echo "Manuelle Installation:"
    echo "  sudo cp $config_file /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf"
    echo "  sudo sensors -s"
    echo "  sensors"
fi

echo
echo "=== Weitere Optimierung ==="
echo "Für weitere Feinabstimmung:"
echo "1. Vergleichen Sie sensors-Ausgabe mit BIOS-Werten"
echo "2. Passen Sie Spannungs-Multiplier bei Bedarf an"
echo "3. Aktivieren/deaktivieren Sie ignore-Statements für ungenutzte Sensoren"
echo "4. Testen Sie PWM-Kontrollen: bash test_pwm_controls.sh"

echo
echo "=== Korrigierte Konfiguration erstellt ==="
