# NCT6687D Konfiguration für MSI MAG Z890 TOMAHAWK WIFI

## Übersicht
Diese Dokumentation beschreibt die vollständige Installation und Konfiguration des NCT6687D Treibers für das MSI MAG Z890 TOMAHAWK WIFI Motherboard unter Arch Linux.

## Hardware-Spezifikationen
- **Motherboard**: MSI MAG Z890 TOMAHAWK WIFI
- **Chipsatz**: Intel Z890
- **Super-I/O Chip**: NCT6687D/NCT6687 (Nuvoton)
- **Betriebssystem**: Arch Linux
- **Kernel**: Linux 6.x

## Installation

### Automatische Installation
```bash
# Vollständige automatische Installation
sudo bash install_nct6687d_z890.sh
```

### Manuelle Installation
```bash
# 1. Abhängigkeiten installieren
sudo pacman -S base-devel linux-headers dkms bc lm_sensors

# 2. Repository klonen
git clone https://github.com/Fred78290/nct6687d
cd nct6687d

# 3. DKMS Installation
sudo make dkms/install

# 4. Module konfigurieren
echo "nct6687" | sudo tee /etc/modules-load.d/nct6687.conf
echo "options nct6687 manual=1 force=1" | sudo tee /etc/modprobe.d/nct6687.conf

# 5. Sensor-Konfiguration installieren
sudo cp Z890_TOMAHAWK_WIFI.conf /etc/sensors.d/

# 6. Modul laden
sudo modprobe nct6687 manual=1 force=1
sudo sensors -s
```

## Konfigurationsdateien

### /etc/modules-load.d/nct6687.conf
```
# NCT6687D Treiber für MSI MAG Z890 TOMAHAWK WIFI
nct6687
```

### /etc/modprobe.d/nct6687.conf
```
# NCT6687D Parameter für MSI MAG Z890 TOMAHAWK WIFI
options nct6687 manual=1 force=1
softdep nct6687 pre: i2c_i801
blacklist nct6683
```

### /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf
Siehe separate Konfigurationsdatei mit vollständiger Sensor-Zuordnung.

## Erkannte Hardware

### Spannungssensoren (14 Kanäle)
| Register | Label | Beschreibung | Multiplier |
|----------|-------|--------------|------------|
| in0 | +12V | Hauptversorgung 12V | ×12 |
| in1 | +5V | Standby 5V | ×5 |
| in2 | VCore | CPU Kernspannung | ×1 |
| in3 | CPU SA | CPU System Agent | ×1 |
| in4 | DRAM | Arbeitsspeicher | ×2 |
| in5 | CPU I/O | CPU I/O Controller | ×1 |
| in6 | CPU AUX | CPU Hilfsspannung | ×1 |
| in7 | PCH Core | Chipsatz Kernspannung | ×1 |
| in8 | +3.3V | 3.3V Rail | ×1 |
| in9-13 | Weitere | Zusätzliche Spannungen | ×1 |

### Temperatursensoren (7 Kanäle)
| Sensor | Label | Beschreibung |
|--------|-------|--------------|
| temp1 | CPU Package | CPU Gesamttemperatur |
| temp2 | System | Systemtemperatur |
| temp3 | VRM MOS | Spannungsregler |
| temp4 | PCH | Platform Controller Hub |
| temp5 | CPU Socket | CPU Sockel |
| temp6 | M.2_1 | M.2 Slot 1 |
| temp7 | M.2_2 | M.2 Slot 2 |

### Lüftersensoren (8 Kanäle)
| Fan | Label | Beschreibung |
|-----|-------|--------------|
| fan1 | CPU_FAN | CPU Lüfter |
| fan2 | SYS_FAN1 | System Lüfter 1 |
| fan3 | SYS_FAN2 | System Lüfter 2 |
| fan4 | SYS_FAN3 | System Lüfter 3 |
| fan5 | SYS_FAN4 | System Lüfter 4 |
| fan6 | SYS_FAN5 | System Lüfter 5 |
| fan7 | PUMP_FAN | AIO Pumpe |
| fan8 | SYS_FAN6 | System Lüfter 6 |

### PWM-Kontrollen (8 Kanäle)
Alle Lüfter unterstützen PWM-Steuerung mit Modi:
- **1**: Manual (manuelle Steuerung)
- **99**: Firmware/Auto (automatische Steuerung)

## Diagnose und Wartung

### Verfügbare Diagnose-Scripts
```bash
# Lüfter-Diagnose
bash diagnose_fans_z890.sh

# Spannungsanalyse
bash analyze_voltages_z890.sh

# Vollständige Validierung
bash validate_z890_config.sh

# Performance-Test
bash performance_test_z890.sh
```

### Manuelle Überprüfung
```bash
# Modul-Status
lsmod | grep nct6687

# Sensor-Ausgabe
sensors

# Hardware-Pfad
find /sys/class/hwmon -name "*nct6687*"

# Kernel-Logs
dmesg | grep nct6687
```

## Erwartete Sensor-Werte

### Spannungen
- **+12V**: 11.4V - 12.6V
- **+5V**: 4.75V - 5.25V
- **+3.3V**: 3.135V - 3.465V
- **VCore**: 0.6V - 1.4V (lastabhängig)
- **DRAM**: 1.1V - 1.35V (DDR5)
- **CPU SA**: 0.8V - 1.2V

### Temperaturen
- **CPU**: 30°C - 85°C (normal)
- **System**: 25°C - 50°C
- **VRM**: 30°C - 80°C
- **PCH**: 30°C - 70°C

## Troubleshooting

### Häufige Probleme

#### 1. Modul lädt nicht
```bash
# Lösung: ACPI-Konflikte beheben
sudo nano /etc/default/grub
# Hinzufügen: GRUB_CMDLINE_LINUX_DEFAULT="... acpi_enforce_resources=lax"
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

#### 2. Keine Lüfter erkannt
- BIOS Hardware Monitor aktivieren
- Smart Fan Control aktivieren
- Lüfter-Anschlüsse überprüfen

#### 3. Falsche Spannungswerte
- Multiplier in sensors.d Konfiguration anpassen
- Mit BIOS-Werten vergleichen
- manual=1 Parameter verwenden

#### 4. Boot-Probleme
```bash
# i2c_i801 Abhängigkeit hinzufügen
echo "softdep nct6687 pre: i2c_i801" | sudo tee -a /etc/modprobe.d/nct6687.conf
```

### Recovery
```bash
# Notfall-Wiederherstellung
sudo modprobe -r nct6687
sudo rm -f /etc/modules-load.d/nct6687.conf
sudo rm -f /etc/modprobe.d/nct6687.conf
sudo modprobe nct6683
```

## Optimierung

### BIOS-Einstellungen
- **Hardware Monitor**: Enabled
- **Smart Fan Control**: Enabled
- **Fan Control Mode**: PWM oder DC je nach Lüfter
- **CPU Fan Speed**: Normal oder Silent

### Lüftersteuerung
```bash
# Manuelle PWM-Steuerung (Beispiel)
echo 1 > /sys/class/hwmon/hwmon*/pwm1_enable    # Manual-Modus
echo 128 > /sys/class/hwmon/hwmon*/pwm1         # 50% Geschwindigkeit
echo 99 > /sys/class/hwmon/hwmon*/pwm1_enable   # Zurück zu Auto
```

## Wartung

### Regelmäßige Überprüfungen
```bash
# Wöchentliche Sensor-Überprüfung
sensors > /var/log/sensors_$(date +%Y%m%d).log

# Monatliche Validierung
bash validate_z890_config.sh > /var/log/nct6687_validation_$(date +%Y%m).log
```

### Updates
```bash
# DKMS automatisch bei Kernel-Updates
sudo dkms autoinstall

# Manuelle Neuinstallation bei Problemen
cd nct6687d
sudo make dkms/clean
sudo make dkms/install
```

## Support und Weiterentwicklung

### Logs für Support
```bash
# Sammle Diagnose-Informationen
dmesg | grep nct6687 > nct6687_dmesg.log
sensors -u > sensors_detailed.log
lsmod | grep nct > modules.log
```

### Bekannte Einschränkungen
- Einige M.2-Temperatursensoren möglicherweise nicht verfügbar
- PWM-Steuerung abhängig von BIOS-Konfiguration
- Spannungs-Multiplier können motherboard-spezifisch variieren

### Verbesserungsvorschläge
- Automatische Multiplier-Erkennung
- Erweiterte Lüfterkurven-Konfiguration
- Integration mit systemd für bessere Boot-Unterstützung

## Changelog

### Version 1.0 (Initial)
- Grundlegende Z890 Unterstützung
- Vollständige Sensor-Zuordnung
- Automatische Installation
- Umfassende Diagnose-Tools

---

**Erstellt**: $(date)  
**Für**: MSI MAG Z890 TOMAHAWK WIFI  
**Treiber**: nct6687d  
**System**: Arch Linux
