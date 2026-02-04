#!/bin/bash
set -e

AWG_DIR="/data/amneziawg"
AWG_CONF="$AWG_DIR/conf/awg0.conf"
AWG_IFACE="awg0"

# Add binaries to PATH
export PATH="$AWG_DIR/bin:$PATH"

# Tell awg-quick to use our userspace implementation
export WG_QUICK_USERSPACE_IMPLEMENTATION="$AWG_DIR/bin/amneziawg-go"

case "$1" in
    up)
        if [ ! -f "$AWG_CONF" ]; then
            echo "Error: Config file not found: $AWG_CONF"
            exit 1
        fi
        echo "Starting AmneziaWG interface $AWG_IFACE..."
        "$AWG_DIR/bin/awg-quick" up "$AWG_CONF"
        echo "AmneziaWG is up"
        "$AWG_DIR/bin/awg" show
        ;;
    down)
        echo "Stopping AmneziaWG interface $AWG_IFACE..."
        "$AWG_DIR/bin/awg-quick" down "$AWG_IFACE" 2>/dev/null || true
        echo "AmneziaWG is down"
        ;;
    status)
        "$AWG_DIR/bin/awg" show
        ;;
    *)
        echo "Usage: $0 {up|down|status}"
        exit 1
        ;;
esac
