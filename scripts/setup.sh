#!/bin/bash
set -e

AWG_DIR="/data/amneziawg"
AWG_CONF="$AWG_DIR/conf/awg0.conf"
AWG_IFACE="awg0"
AWG_TABLE="100"

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

        # Configure iproute2 custom routing table
        RT_TABLES_FILE="/etc/iproute2/rt_tables.d/custom.conf"
        if [ ! -f "$RT_TABLES_FILE" ]; then
            mkdir -p "$(dirname "$RT_TABLES_FILE")"
            touch "$RT_TABLES_FILE"
        fi
        if ! grep -q "^${AWG_TABLE}[[:space:]]" "$RT_TABLES_FILE" 2>/dev/null; then
            echo "$AWG_TABLE $AWG_IFACE" >> "$RT_TABLES_FILE"
            echo "Added routing table entry: $AWG_TABLE $AWG_IFACE"
        fi

        ip route add default dev "$AWG_IFACE" table "$AWG_TABLE" 2>/dev/null || ip route replace default dev "$AWG_IFACE" table "$AWG_TABLE"
        echo "Added default route through $AWG_IFACE in table $AWG_TABLE"

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
