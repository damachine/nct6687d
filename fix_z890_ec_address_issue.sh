#!/bin/bash

# Spezifische Lösung für MSI MAG Z890 TOMAHAWK WIFI EC-Adress-Problem
# Basierend auf LibreHardwareMonitor-Analyse und Linux nct6687d Code-Review

echo "=== MSI Z890 TOMAHAWK WIFI EC-Adress-Problem Behebung ==="
echo "Datum: $(date)"
echo

# Überprüfen ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
    echo "FEHLER: Dieses Script muss als root ausgeführt werden!"
    echo "sudo bash $0"
    exit 1
fi

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

print_step "1. Diagnose des aktuellen Problems"

# Überprüfe aktuellen Status
echo "Aktuelle Kernel-Logs (NCT6687):"
dmesg | grep nct6687 | tail -5 | sed 's/^/  /'

# Überprüfe ob Modul geladen ist
if lsmod | grep -q nct6687; then
    print_success "nct6687 Modul ist geladen"
else
    print_error "nct6687 Modul nicht geladen"
    exit 1
fi

# Überprüfe hwmon-Gerät
hwmon_device=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
if [ -n "$hwmon_device" ]; then
    print_success "hwmon-Gerät gefunden: $hwmon_device"
    echo "Das Problem ist bereits behoben!"
    exit 0
else
    print_warning "Kein hwmon-Gerät gefunden - EC-Adress-Problem bestätigt"
fi

print_step "2. Analyse der EC-Adress-Erkennung"

# Prüfe auf spezifische Fehlermeldung
if dmesg | grep -q "EC Invalid address: 0xFFFF"; then
    print_error "EC Invalid address: 0xFFFF Problem bestätigt"
    echo "Dies ist ein bekanntes Problem mit MSI Z890 Motherboards"
elif dmesg | grep -q "EC base I/O port unconfigured"; then
    print_error "EC base I/O port unconfigured Problem erkannt"
    echo "Dies deutet auf BIOS-Konfigurationsprobleme hin"
else
    print_warning "Unbekanntes EC-Problem - führe erweiterte Diagnose durch"
fi

print_step "3. ACPI-Ressourcen-Konflikt-Lösung"

# Überprüfe ACPI-Konflikte
acpi_conflicts=$(dmesg | grep -i "acpi.*conflict\|resource.*conflict" | wc -l)
if [ $acpi_conflicts -gt 0 ]; then
    print_warning "$acpi_conflicts ACPI-Konflikte gefunden"
    echo "ACPI-Konflikte:"
    dmesg | grep -i "acpi.*conflict\|resource.*conflict" | tail -3 | sed 's/^/  /'
    
    echo
    print_step "3a. Temporäre ACPI-Lösung (ohne Neustart)"
    
    # Versuche Treiber mit verschiedenen Kombinationen neu zu laden
    print_warning "Teste verschiedene Treiber-Parameter-Kombinationen..."
    
    # Test 1: Entlade und lade mit force=1
    modprobe -r nct6687 2>/dev/null
    sleep 2
    
    echo "Test 1: force=1"
    modprobe nct6687 force=1 2>/dev/null
    sleep 3
    
    hwmon_device=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
    if [ -n "$hwmon_device" ]; then
        print_success "Erfolg mit force=1 Parameter!"
        echo "hwmon-Gerät: $hwmon_device"
        
        # Mache es permanent
        echo "options nct6687 force=1" > /etc/modprobe.d/nct6687.conf
        print_success "Permanente Konfiguration gespeichert"
        
        # Teste Sensoren
        if command -v sensors &> /dev/null; then
            echo
            echo "Sensor-Test:"
            sensors | grep -A 20 nct6687 | sed 's/^/  /'
        fi
        
        exit 0
    else
        print_warning "force=1 allein reicht nicht"
        modprobe -r nct6687 2>/dev/null
        sleep 2
    fi
    
    # Test 2: manual=1 force=1
    echo "Test 2: manual=1 force=1"
    modprobe nct6687 manual=1 force=1 2>/dev/null
    sleep 3
    
    hwmon_device=$(find /sys/class/hwmon -name "*nct6687*" -type d | head -1)
    if [ -n "$hwmon_device" ]; then
        print_success "Erfolg mit manual=1 force=1 Parametern!"
        echo "hwmon-Gerät: $hwmon_device"
        
        # Mache es permanent
        echo "options nct6687 manual=1 force=1" > /etc/modprobe.d/nct6687.conf
        print_success "Permanente Konfiguration gespeichert"
        
        # Teste Sensoren
        if command -v sensors &> /dev/null; then
            echo
            echo "Sensor-Test:"
            sensors | grep -A 20 nct6687 | sed 's/^/  /'
        fi
        
        exit 0
    else
        print_error "Auch manual=1 force=1 funktioniert nicht"
        modprobe -r nct6687 2>/dev/null
    fi
fi

print_step "4. Permanente ACPI-Lösung (erfordert Neustart)"

echo "Da die temporären Lösungen nicht funktioniert haben, ist eine permanente"
echo "ACPI-Konfiguration erforderlich:"
echo

# Überprüfe aktuelle GRUB-Konfiguration
if [ -f "/etc/default/grub" ]; then
    current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub)
    echo "Aktuelle GRUB-Konfiguration:"
    echo "  $current_cmdline"
    echo
    
    if echo "$current_cmdline" | grep -q "acpi_enforce_resources=lax"; then
        print_warning "acpi_enforce_resources=lax bereits konfiguriert"
        echo "Das Problem liegt möglicherweise tiefer - siehe erweiterte Lösungen"
    else
        print_step "4a. GRUB-Konfiguration aktualisieren"
        
        # Backup der GRUB-Konfiguration
        cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d_%H%M%S)
        print_success "GRUB-Backup erstellt"
        
        # Füge acpi_enforce_resources=lax hinzu
        if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub; then
            sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 acpi_enforce_resources=lax"/' /etc/default/grub
        else
            echo 'GRUB_CMDLINE_LINUX_DEFAULT="acpi_enforce_resources=lax"' >> /etc/default/grub
        fi
        
        # Aktualisiere GRUB
        grub-mkconfig -o /boot/grub/grub.cfg
        print_success "GRUB-Konfiguration aktualisiert"
        
        echo
        print_warning "NEUSTART ERFORDERLICH für ACPI-Änderungen"
        echo "Nach dem Neustart führen Sie aus:"
        echo "  sudo modprobe nct6687 manual=1 force=1"
        echo "  sensors"
    fi
else
    print_error "/etc/default/grub nicht gefunden - anderes Bootloader-System?"
fi

print_step "5. Alternative Lösungsansätze"

echo "Falls die ACPI-Lösung nicht funktioniert:"
echo

echo "5a. BIOS/UEFI-Einstellungen überprüfen:"
echo "  - Hardware Monitor: Enabled"
echo "  - Super I/O Configuration: Enabled"
echo "  - ACPI Settings: Standard oder Disabled"
echo "  - Secure Boot: Disabled (temporär testen)"
echo

echo "5b. Fallback auf nct6683 Treiber:"
echo "  sudo modprobe -r nct6687"
echo "  sudo modprobe nct6683"
echo "  sensors"
echo

echo "5c. Kernel-Parameter-Alternativen:"
echo "  - pci=noacpi"
echo "  - acpi=off (nur zum Testen!)"
echo "  - noapic"
echo

print_step "6. Erweiterte Diagnose für Entwickler"

echo "Für weitere Analyse sammeln Sie folgende Informationen:"
echo

# Sammle erweiterte Diagnose-Informationen
cat > /tmp/z890_ec_diagnosis.txt << EOF
=== MSI MAG Z890 TOMAHAWK WIFI EC-Diagnose ===
Datum: $(date)
Kernel: $(uname -r)

=== BIOS-Informationen ===
$(dmidecode -s baseboard-product-name 2>/dev/null || echo "Unbekannt")
$(dmidecode -s baseboard-manufacturer 2>/dev/null || echo "Unbekannt")
$(dmidecode -s bios-version 2>/dev/null || echo "Unbekannt")
$(dmidecode -s bios-release-date 2>/dev/null || echo "Unbekannt")

=== Kernel-Logs (NCT6687) ===
$(dmesg | grep -i nct6687)

=== I/O-Ports ===
$(grep -E "(002e|004e|0a20)" /proc/ioports 2>/dev/null || echo "Keine relevanten Ports")

=== ACPI-Konflikte ===
$(dmesg | grep -i "acpi.*conflict\|resource.*conflict" || echo "Keine ACPI-Konflikte")

=== Module-Parameter ===
$(cat /sys/module/nct6687/parameters/* 2>/dev/null || echo "Keine Parameter verfügbar")

=== Hardware-Monitoring-Geräte ===
$(ls -la /sys/class/hwmon/*/name 2>/dev/null | while read line; do echo "$line: $(cat $(echo $line | awk '{print $9}') 2>/dev/null)"; done)
EOF

print_success "Erweiterte Diagnose gespeichert: /tmp/z890_ec_diagnosis.txt"

print_step "7. Empfohlene nächste Schritte"

echo "1. Führen Sie einen Neustart durch (falls GRUB aktualisiert wurde)"
echo "2. Testen Sie nach dem Neustart:"
echo "   sudo modprobe nct6687 manual=1 force=1"
echo "3. Falls das nicht funktioniert, testen Sie nct6683:"
echo "   sudo modprobe nct6683"
echo "4. Überprüfen Sie BIOS-Einstellungen"
echo "5. Bei anhaltenden Problemen: Senden Sie /tmp/z890_ec_diagnosis.txt an die Entwickler"

echo
echo "=== EC-Adress-Problem-Behebung abgeschlossen ==="
echo "Weitere Hilfe: https://github.com/Fred78290/nct6687d/issues"
