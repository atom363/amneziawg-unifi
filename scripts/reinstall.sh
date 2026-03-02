#!/bin/bash
set -e

AWG_DIR="/data/amneziawg"
SYSTEMD_DIR="/etc/systemd/system"

echo "Reinstalling AmneziaWG after firmware update..."

# Check if service file exists in /data
if [ ! -f "$AWG_DIR/amneziawg@.service" ]; then
    echo "Error: Service file not found at $AWG_DIR/amneziawg@.service"
    echo "Please reinstall from the original package."
    exit 1
fi

# Reinstall systemd service
echo "Reinstalling systemd service..."
cp "$AWG_DIR/amneziawg@.service" "$SYSTEMD_DIR/"
systemctl daemon-reload

echo ""
echo "Reinstallation complete!"
echo ""
echo "Next steps:"
echo "  Enable and start tunnels which you need manually:"
echo ""
for conf in "$AWG_DIR"/conf/awg*.conf; do
    if [ -f "$conf" ]; then
        iface=$(basename "$conf" .conf)
        echo "    systemctl enable --now amneziawg@$iface"
    fi
done
echo ""
