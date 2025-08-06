#!/bin/bash

# NCT Chip Detection Script for MSI MAG Z890 TOMAHAWK WIFI
# This script helps determine what Super-I/O chip is present on your motherboard

echo "=== NCT Chip Detection for MSI MAG Z890 TOMAHAWK WIFI ==="
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root to access hardware registers"
    echo "Please run: sudo $0"
    exit 1
fi

# Function to read Super-I/O registers
read_superio() {
    local sioaddr=$1
    local reg=$2
    
    # Enter Super-I/O mode
    outb $sioaddr 0x87
    outb $sioaddr 0x87
    
    # Read register
    outb $sioaddr $reg
    local value=$(inb $((sioaddr + 1)))
    
    # Exit Super-I/O mode
    outb $sioaddr 0xaa
    outb $sioaddr 0x02
    outb $((sioaddr + 1)) 0x02
    
    echo $value
}

# Check if outb/inb commands are available
if ! command -v outb &> /dev/null || ! command -v inb &> /dev/null; then
    echo "ERROR: outb/inb commands not found. Please install ioport package:"
    echo "  Arch Linux: sudo pacman -S ioport"
    echo "  Ubuntu/Debian: sudo apt install ioport"
    echo "  Fedora: sudo dnf install ioport"
    exit 1
fi

echo "1. Current kernel modules loaded:"
echo "   nct6683: $(lsmod | grep nct6683 | wc -l > 0 && echo "LOADED" || echo "NOT LOADED")"
echo "   nct6687: $(lsmod | grep nct6687 | wc -l > 0 && echo "LOADED" || echo "NOT LOADED")"
echo

echo "2. Checking Super-I/O addresses for NCT chips..."
echo

# Standard Super-I/O addresses
sio_addresses=(0x2e 0x4e)

for sioaddr in "${sio_addresses[@]}"; do
    echo "Checking Super-I/O address: 0x$(printf "%02x" $sioaddr)"
    
    # Try to read device ID (registers 0x20 and 0x21)
    devid_high=$(read_superio $sioaddr 0x20 2>/dev/null)
    devid_low=$(read_superio $sioaddr 0x21 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$devid_high" ] && [ -n "$devid_low" ]; then
        # Convert to 16-bit value
        chip_id=$((($devid_high << 8) | $devid_low))
        chip_id_hex=$(printf "0x%04x" $chip_id)
        
        echo "  Device ID: $chip_id_hex"
        
        # Check against known NCT chip IDs
        case $chip_id_hex in
            0xc730|0xc732)
                echo "  -> NCT6683 detected (supported by nct6683 driver)"
                ;;
            0xd440)
                echo "  -> NCT6686D detected (supported by nct6687d driver)"
                ;;
            0xd450)
                echo "  -> NCT6687D detected (supported by nct6687d driver)"
                ;;
            0xd590|0xd592)
                echo "  -> NCT6687 detected (supported by nct6687d driver)"
                ;;
            0xb270)
                echo "  -> NCT6681 detected (future support planned)"
                ;;
            0xffff)
                echo "  -> No chip detected at this address"
                ;;
            *)
                echo "  -> Unknown chip ID: $chip_id_hex"
                echo "     This might be a newer NCT chip not yet supported"
                ;;
        esac
    else
        echo "  -> No response or error reading from this address"
    fi
    echo
done

echo "3. Current sensors output:"
if command -v sensors &> /dev/null; then
    sensors | grep -A 20 "nct6"
else
    echo "   sensors command not found. Install lm-sensors package."
fi
echo

echo "4. DMI/BIOS Information:"
echo "   Motherboard: $(dmidecode -s baseboard-product-name 2>/dev/null || echo "Unknown")"
echo "   Manufacturer: $(dmidecode -s baseboard-manufacturer 2>/dev/null || echo "Unknown")"
echo "   BIOS Version: $(dmidecode -s bios-version 2>/dev/null || echo "Unknown")"
echo

echo "5. Recommendations:"
echo "   Based on the detected chip ID above:"
echo "   - If NCT6687/NCT6687D/NCT6686D is detected: Use nct6687d driver"
echo "   - If NCT6683 is detected: Current nct6683 driver should work"
echo "   - If unknown chip: Try nct6687d driver with force=1 parameter"
echo

echo "=== Detection Complete ==="
