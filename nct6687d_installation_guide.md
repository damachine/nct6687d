# NCT6687D Driver Installation Guide for MSI MAG Z890 TOMAHAWK WIFI

## Driver Comparison: nct6683 vs nct6687d

### Key Differences

| Feature | nct6683 (Current) | nct6687d (This Repo) |
|---------|-------------------|----------------------|
| **Chip Support** | NCT6683 only | NCT6683, NCT6686D, NCT6687, NCT6687D |
| **Voltage Channels** | 14 (limited) | 14-21 depending on chip |
| **Fan Control** | Basic | Advanced PWM control |
| **Temperature Sensors** | 7 | 7-32 depending on chip |
| **Manual Configuration** | Limited | Full manual voltage mapping |
| **Intel Z890 Support** | Partial | Better compatibility |
| **Fan Speed Control** | Read-only | Read/Write with firmware modes |
| **Voltage Multipliers** | Fixed | Configurable per motherboard |

### Advantages of nct6687d Driver

1. **Better Hardware Support**: Supports newer NCT chips likely present on Z890 motherboards
2. **Enhanced Fan Control**: Manual PWM control with firmware fallback modes
3. **Flexible Voltage Configuration**: Manual voltage mapping for different motherboard layouts
4. **Active Development**: Regular updates and bug fixes
5. **Z890 Compatibility**: Better support for newer Intel chipsets

## Vollständige Implementierung - Alle Scripts und Konfigurationsdateien

Die folgenden Dateien werden für die komplette Installation und Konfiguration benötigt:

1. `diagnose_fans_z890.sh` - Lüfter-Diagnose Script
2. `analyze_voltages_z890.sh` - Spannungsanalyse Script
3. `Z890_TOMAHAWK_WIFI_optimized.conf` - Optimierte Sensor-Konfiguration
4. `validate_z890_config.sh` - Validierungs-Script
5. `performance_test_z890.sh` - Performance-Test Script
6. `install_nct6687d_z890.sh` - Automatisches Installations-Script

## Installation Process for Arch Linux

### Prerequisites

```bash
# Install required packages
sudo pacman -S base-devel linux-headers dkms git

# Install ioport for chip detection (optional)
sudo pacman -S ioport
```

### Step 1: Detect Current Hardware

```bash
# Run the detection script
sudo bash detect_nct_chip.sh

# Check current sensors output
sensors
```

### Step 2: Backup Current Configuration

```bash
# Backup current module configuration
sudo cp /etc/modules-load.d/modules.conf /etc/modules-load.d/modules.conf.backup 2>/dev/null || true

# Check current loaded modules
lsmod | grep nct
```

### Step 3: Install nct6687d Driver

```bash
# Clone the repository
git clone https://github.com/Fred78290/nct6687d
cd nct6687d

# Install using DKMS (recommended)
sudo make dkms/install
```

### Step 4: Handle Module Conflicts

```bash
# Remove old nct6683 module if loaded
sudo modprobe -r nct6683

# Blacklist nct6683 to prevent conflicts
echo "blacklist nct6683" | sudo tee /etc/modprobe.d/blacklist-nct6683.conf

# Load new nct6687 module
sudo modprobe nct6687
```

### Step 5: Configure Auto-loading

```bash
# For Arch Linux with systemd
echo "nct6687" | sudo tee /etc/modules-load.d/nct6687.conf

# Remove old nct6683 auto-loading if present
sudo sed -i '/nct6683/d' /etc/modules-load.d/*.conf 2>/dev/null || true
```

### Step 6: Test Installation

```bash
# Check if module is loaded
lsmod | grep nct6687

# Test sensors output
sensors

# Check dmesg for any errors
dmesg | grep nct6687
```

## Troubleshooting

### Common Issues and Solutions

#### 1. ACPI Resource Conflicts
```bash
# Add kernel parameter to GRUB
sudo nano /etc/default/grub
# Add: GRUB_CMDLINE_LINUX_DEFAULT="... acpi_enforce_resources=lax"
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

#### 2. Module Loading Fails at Boot
```bash
# Add dependency for i2c_i801
echo "softdep nct6687 pre: i2c_i801" | sudo tee /etc/modprobe.d/nct6687.conf
```

#### 3. Unknown Chip ID
```bash
# Force load with unknown chip support
echo "nct6687 force=1" | sudo tee /etc/modules-load.d/nct6687.conf
```

#### 4. Incorrect Voltage Readings
```bash
# Enable manual voltage configuration
echo "nct6687 manual=1" | sudo tee -a /etc/modules-load.d/nct6687.conf
# Then create custom sensor configuration (see next section)
```

## Uninstallation (if needed)

```bash
# Remove DKMS module
sudo dkms remove nct6687d/1 --all

# Remove configuration files
sudo rm -f /etc/modules-load.d/nct6687.conf
sudo rm -f /etc/modprobe.d/blacklist-nct6683.conf
sudo rm -f /etc/modprobe.d/nct6687.conf

# Re-enable nct6683 if desired
sudo modprobe nct6683
```

## Expected Benefits for Z890 Motherboard

1. **More Accurate Readings**: Better chip detection and register mapping
2. **Fan Control**: Ability to manually control fan speeds
3. **Voltage Monitoring**: More precise voltage readings with custom multipliers
4. **Temperature Sensors**: Access to additional temperature sensors
5. **Future Compatibility**: Support for newer NCT chips

## Next Steps

After installation, you may need to:
1. Create a motherboard-specific sensor configuration file
2. Test and validate sensor readings
3. Configure fan control curves if needed

Run the detection script first to determine your exact chip model, then proceed with installation.
