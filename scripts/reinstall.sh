#!/bin/bash
set -e

AWG_DIR="/data/amneziawg"
SYSTEMD_DIR="/etc/systemd/system"

echo "Reinstalling AmneziaWG after firmware update..."

# Check if service file exists in /data
if [ ! -f "$AWG_DIR/amneziawg.service" ]; then
    echo "Error: Service file not found at $AWG_DIR/amneziawg.service"
    echo "Please reinstall from the original package."
    exit 1
fi

# Reinstall systemd service
echo "Reinstalling systemd service..."
cp "$AWG_DIR/amneziawg.service" "$SYSTEMD_DIR/"
systemctl daemon-reload
systemctl enable amneziawg

# Check if config exists
if [ ! -f "$AWG_DIR/conf/awg0.conf" ]; then
    echo "Warning: No config found at $AWG_DIR/conf/awg0.conf"
    echo "Create your config before starting the service."
else
    echo "Starting AmneziaWG..."
    systemctl start amneziawg
    systemctl status amneziawg --no-pager
fi

echo ""
echo "Reinstallation complete!"
