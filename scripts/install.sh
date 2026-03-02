#!/bin/bash
set -e

AWG_DIR="/data/amneziawg"
SYSTEMD_DIR="/etc/systemd/system"

echo "Installing AmneziaWG for UniFi..."

OS_VERSION="$(ubnt-device-info firmware_detail | grep -oE '^[0-9]+')"

#detect major firmware version
if [ "$OS_VERSION" = '1' ]
then
    echo "This script is not compatible with this router's firmware."
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "Error: This package is for ARM64 (aarch64), but this device is $ARCH"
    exit 1
fi

# Install systemd service
echo "Installing systemd service..."
cp "$AWG_DIR/amneziawg.service" "$SYSTEMD_DIR/"
systemctl daemon-reload

# Create config directory if not exists
mkdir -p "$AWG_DIR/conf"

# Copy example config if no config exists
if [ ! -f "$AWG_DIR/conf/awg0.conf" ]; then
    cp "$AWG_DIR/conf/awg0.conf.example" "$AWG_DIR/conf/awg0.conf"
    echo ""
    echo "Example config created at: $AWG_DIR/conf/awg0.conf"
    echo "Edit it with your VPN credentials before starting the service."
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Edit your config: vi $AWG_DIR/conf/awg0.conf"
echo "  2. Start the VPN:    systemctl enable --now amneziawg@awg0"
echo "  3. Check status:     systemctl status amneziawg@awg0"
echo ""
echo "After firmware updates, run: $AWG_DIR/reinstall.sh"
