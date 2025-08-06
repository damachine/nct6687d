# NCT6687D Installation für MSI MAG Z890 TOMAHAWK WIFI

## Schnellstart

### Automatische Installation (Empfohlen)
```bash
# Alle Dateien herunterladen und ausführbar machen
chmod +x *.sh

# Vollständige automatische Installation
sudo bash install_nct6687d_z890.sh
```

### Nach der Installation
```bash
# Validierung durchführen
bash validate_z890_config.sh

# Sensoren anzeigen
sensors

# Bei Problemen Diagnose ausführen
bash diagnose_fans_z890.sh
bash analyze_voltages_z890.sh
```

## Übersicht der Dateien

### Installations-Scripts
- **`install_nct6687d_z890.sh`** - Vollständige automatische Installation
- **`detect_nct_chip.sh`** - Hardware-Chip-Erkennung (optional, da ioport veraltet)

### Diagnose-Scripts
- **`diagnose_fans_z890.sh`** - Lüfter-Sensoren und PWM-Kontrollen analysieren
- **`analyze_voltages_z890.sh`** - Spannungssensoren und Multiplier analysieren
- **`validate_z890_config.sh`** - Vollständige Konfigurationsvalidierung
- **`performance_test_z890.sh`** - Performance und Stabilität testen

### Konfigurationsdateien
- **`Z890_TOMAHAWK_WIFI.conf`** - Optimierte Sensor-Konfiguration für sensors.d
- **`testing_validation_guide.md`** - Detaillierte Test- und Validierungsanleitung
- **`nct6687d_installation_guide.md`** - Umfassende Installationsanleitung

### Dokumentation
- **`Z890_final_config_documentation.md`** - Vollständige Dokumentation der Konfiguration
- **`README_Z890_Installation.md`** - Diese Datei

## Schritt-für-Schritt Installation

### 1. Vorbereitung
```bash
# Abhängigkeiten installieren
sudo pacman -S base-devel linux-headers dkms bc lm_sensors git

# Baseline-Daten sammeln (optional)
sensors > baseline_sensors.txt
lsmod | grep nct > baseline_modules.txt
```

### 2. Installation
```bash
# Automatische Installation ausführen
sudo bash install_nct6687d_z890.sh
```

**Oder manuelle Installation:**
```bash
# Repository klonen
git clone https://github.com/Fred78290/nct6687d
cd nct6687d

# DKMS Installation
sudo make dkms/install

# Konfiguration
sudo cp ../Z890_TOMAHAWK_WIFI.conf /etc/sensors.d/
echo "nct6687 manual=1" | sudo tee /etc/modules-load.d/nct6687.conf

# Modul laden
sudo modprobe nct6687 manual=1
sudo sensors -s
```

### 3. Validierung
```bash
# Grundlegende Überprüfung
lsmod | grep nct6687
sensors

# Umfassende Validierung
bash validate_z890_config.sh
```

### 4. Diagnose (bei Problemen)
```bash
# Lüfter-Probleme
bash diagnose_fans_z890.sh

# Spannungs-Probleme
bash analyze_voltages_z890.sh

# Performance-Test
bash performance_test_z890.sh
```

## Erwartete Ergebnisse

### Erfolgreiche Installation zeigt:
```
nct6687-isa-0a20
Adapter: ISA adapter
+12V:           12.17 V
+5V:             5.14 V
VCore:           1.05 V
CPU SA:          1.11 V
DRAM:            1.34 V
CPU I/O:         1.84 V
+3.3V:           3.38 V
CPU_FAN:       1192 RPM
SYS_FAN1:       922 RPM
CPU Package:    +59.0°C
System:         +34.0°C
VRM MOS:        +31.0°C
PCH:            +40.0°C
```

### Verfügbare PWM-Kontrollen:
- `/sys/class/hwmon/hwmon*/pwm1` bis `pwm8`
- Manual-Modus (1) und Auto-Modus (99)

## Troubleshooting

### Problem: Modul lädt nicht
```bash
# Lösung 1: ACPI-Konflikte
sudo nano /etc/default/grub
# Hinzufügen: acpi_enforce_resources=lax
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Lösung 2: Force-Parameter
sudo modprobe nct6687 manual=1 force=1
```

### Problem: Keine Lüfter erkannt
```bash
# BIOS-Einstellungen überprüfen:
# - Hardware Monitor: Enabled
# - Smart Fan Control: Enabled

# Diagnose ausführen
bash diagnose_fans_z890.sh
```

### Problem: Falsche Spannungswerte
```bash
# Spannungsanalyse
bash analyze_voltages_z890.sh

# Multiplier in /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf anpassen
sudo nano /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf
sudo sensors -s
```

### Problem: Boot-Probleme
```bash
# i2c_i801 Abhängigkeit hinzufügen
echo "softdep nct6687 pre: i2c_i801" | sudo tee -a /etc/modprobe.d/nct6687.conf
```

## Deinstallation

### Vollständige Entfernung
```bash
# Modul entladen
sudo modprobe -r nct6687

# DKMS entfernen
sudo dkms remove nct6687d/1 --all

# Konfigurationsdateien entfernen
sudo rm -f /etc/modules-load.d/nct6687.conf
sudo rm -f /etc/modprobe.d/nct6687.conf
sudo rm -f /etc/sensors.d/Z890_TOMAHAWK_WIFI.conf

# Zurück zu nct6683 (falls gewünscht)
sudo modprobe nct6683
```

### Recovery-Script verwenden
```bash
# Automatisches Recovery (falls vom Installations-Script erstellt)
sudo bash /root/nct6687d_backup_*/recovery.sh
```

## Wartung

### Regelmäßige Überprüfungen
```bash
# Wöchentlich
sensors > /var/log/sensors_$(date +%Y%m%d).log

# Monatlich
bash validate_z890_config.sh > /var/log/validation_$(date +%Y%m).log
```

### Kernel-Updates
```bash
# DKMS sollte automatisch neu kompilieren
# Bei Problemen manuell:
cd nct6687d
sudo make dkms/clean
sudo make dkms/install
```

## Support

### Logs sammeln für Support
```bash
# Diagnose-Informationen sammeln
dmesg | grep nct6687 > nct6687_dmesg.log
sensors -u > sensors_detailed.log
bash validate_z890_config.sh > validation_report.log
```

### Bekannte Arbeitsumgebung
- **Motherboard**: MSI MAG Z890 TOMAHAWK WIFI
- **Betriebssystem**: Arch Linux
- **Kernel**: 6.x
- **Treiber**: nct6687d (GitHub: Fred78290/nct6687d)

## Weiterführende Informationen

- **Vollständige Dokumentation**: `Z890_final_config_documentation.md`
- **Detaillierte Tests**: `testing_validation_guide.md`
- **Installationsanleitung**: `nct6687d_installation_guide.md`
- **Original Repository**: https://github.com/Fred78290/nct6687d

---

**Hinweis**: Diese Konfiguration ist speziell für das MSI MAG Z890 TOMAHAWK WIFI optimiert. Für andere Motherboards können Anpassungen erforderlich sein.
