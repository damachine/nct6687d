# NCT6687D Driver Testing and Validation Guide

## Pre-Installation Testing

### 1. Baseline Measurements
Before installing the nct6687d driver, collect baseline data:

```bash
# Current sensor readings
sensors > baseline_sensors.txt

# Current loaded modules
lsmod | grep nct > baseline_modules.txt

# System information
dmidecode -s baseboard-product-name > baseline_motherboard.txt
dmidecode -s bios-version >> baseline_motherboard.txt

# Current kernel version
uname -r > baseline_kernel.txt
```

### 2. Hardware Detection
Run the chip detection script:

```bash
sudo bash detect_nct_chip.sh > chip_detection_results.txt
```

## Safe Installation Process

### 1. Create Recovery Plan
```bash
# Create a recovery script
cat > recovery_nct.sh << 'EOF'
#!/bin/bash
echo "Recovering from nct6687d installation..."
sudo modprobe -r nct6687 2>/dev/null
sudo dkms remove nct6687d/1 --all 2>/dev/null
sudo rm -f /etc/modules-load.d/nct6687.conf
sudo rm -f /etc/modprobe.d/blacklist-nct6683.conf
sudo modprobe nct6683
echo "Recovery complete. Original nct6683 driver restored."
EOF
chmod +x recovery_nct.sh
```

### 2. Install with Monitoring
```bash
# Monitor system logs during installation
sudo journalctl -f &
JOURNAL_PID=$!

# Install the driver
sudo make dkms/install

# Stop log monitoring
kill $JOURNAL_PID
```

## Post-Installation Validation

### 1. Module Loading Verification
```bash
# Check if module loaded successfully
if lsmod | grep -q nct6687; then
    echo "✓ nct6687 module loaded successfully"
else
    echo "✗ nct6687 module failed to load"
    exit 1
fi

# Check for errors in dmesg
if dmesg | grep -i "nct6687" | grep -i error; then
    echo "⚠ Errors found in dmesg"
else
    echo "✓ No errors in dmesg"
fi
```

### 2. Sensor Data Validation
```bash
# Test basic sensor functionality
sensors_output=$(sensors 2>&1)
if echo "$sensors_output" | grep -q "nct6687"; then
    echo "✓ nct6687 sensors detected"
    sensors | grep "nct6687" -A 20
else
    echo "✗ nct6687 sensors not found"
fi
```

### 3. Voltage Reading Validation
Create a validation script:

```bash
cat > validate_sensors.sh << 'EOF'
#!/bin/bash

echo "=== Sensor Validation for MSI MAG Z890 TOMAHAWK WIFI ==="
echo

# Expected voltage ranges (adjust based on your system)
declare -A voltage_ranges=(
    ["+12V"]="11.4:12.6"
    ["+5V"]="4.75:5.25"
    ["+3.3V"]="3.135:3.465"
    ["VCore"]="0.6:1.4"
    ["DRAM"]="1.1:1.35"
)

# Parse sensors output
sensors_data=$(sensors | grep -A 50 "nct6687")

echo "Current sensor readings:"
echo "$sensors_data"
echo

echo "Validation results:"
for voltage in "${!voltage_ranges[@]}"; do
    range="${voltage_ranges[$voltage]}"
    min_val=$(echo $range | cut -d: -f1)
    max_val=$(echo $range | cut -d: -f2)
    
    # Extract voltage value (this is a simplified extraction)
    value=$(echo "$sensors_data" | grep "$voltage" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    if [ -n "$value" ]; then
        if (( $(echo "$value >= $min_val && $value <= $max_val" | bc -l) )); then
            echo "✓ $voltage: $value V (within range $min_val-$max_val V)"
        else
            echo "⚠ $voltage: $value V (outside range $min_val-$max_val V)"
        fi
    else
        echo "? $voltage: No reading found"
    fi
done
EOF

chmod +x validate_sensors.sh
bash validate_sensors.sh
```

### 4. Fan Control Testing
```bash
# Test fan control functionality (be careful!)
echo "Testing fan control (will restore original settings)..."

# Find available PWM controls
pwm_controls=$(find /sys/class/hwmon -name "pwm*" -path "*/nct6687*" 2>/dev/null)

if [ -n "$pwm_controls" ]; then
    echo "✓ PWM controls found:"
    echo "$pwm_controls"
    
    # Test one PWM control safely
    for pwm in $pwm_controls; do
        if [ -f "$pwm" ]; then
            original_value=$(cat "$pwm")
            echo "Testing $pwm (original value: $original_value)"
            
            # Test manual control
            echo 1 > "${pwm}_enable" 2>/dev/null
            echo $original_value > "$pwm" 2>/dev/null
            
            # Restore firmware control
            echo 99 > "${pwm}_enable" 2>/dev/null
            echo "✓ PWM control test completed"
            break
        fi
    done
else
    echo "⚠ No PWM controls found"
fi
```

## Performance Comparison

### 1. Compare with Baseline
```bash
# Compare sensor counts
echo "=== Sensor Count Comparison ==="
echo "Baseline (nct6683):"
grep -c ":" baseline_sensors.txt || echo "0"

echo "Current (nct6687d):"
sensors | grep -c ":"

echo
echo "=== New Sensors Available ==="
sensors | grep "nct6687" -A 50 | grep ":"
```

### 2. Temperature Monitoring Test
```bash
# Monitor temperatures under load
echo "Starting temperature monitoring test..."
echo "Baseline temperatures:"
sensors | grep -E "(temp|°C)" | head -10

# You can add stress testing here if desired
# stress-ng --cpu 4 --timeout 30s &

sleep 5
echo "Current temperatures:"
sensors | grep -E "(temp|°C)" | head -10
```

## Troubleshooting Common Issues

### 1. No Sensor Data
```bash
# Check if manual mode is needed
sudo modprobe -r nct6687
sudo modprobe nct6687 manual=1
sensors
```

### 2. Incorrect Voltage Readings
```bash
# Copy and customize the Z890 configuration
sudo cp Z890_TOMAHAWK_WIFI.conf /etc/sensors.d/
sudo systemctl restart systemd-modules-load
sudo modprobe -r nct6687
sudo modprobe nct6687 manual=1
sensors
```

### 3. Module Loading Issues
```bash
# Check for ACPI conflicts
dmesg | grep -i acpi | grep -i conflict

# If conflicts found, add kernel parameter
echo "Add 'acpi_enforce_resources=lax' to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub"
```

## Success Criteria

The installation is considered successful if:

- ✓ nct6687 module loads without errors
- ✓ Sensors command shows nct6687 device
- ✓ Voltage readings are within expected ranges
- ✓ Temperature sensors provide reasonable values
- ✓ Fan speeds are detected (if fans are connected)
- ✓ PWM controls are available (optional)
- ✓ No system instability or crashes

## Rollback Procedure

If issues occur, use the recovery script:

```bash
# Run the recovery script created earlier
sudo bash recovery_nct.sh

# Verify rollback
lsmod | grep nct
sensors
```

## Long-term Monitoring

After successful installation:

1. Monitor system stability for 24-48 hours
2. Check sensor readings periodically
3. Verify fan control works as expected
4. Update configuration file if needed

## Reporting Issues

If you encounter problems:

1. Collect logs: `dmesg | grep nct > nct_logs.txt`
2. Save sensor output: `sensors > sensor_output.txt`
3. Note motherboard BIOS version and settings
4. Report to the nct6687d GitHub repository with logs
