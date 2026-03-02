#!/bin/bash
set -e

AWG_DIR="/data/amneziawg"

# Get interface name from second argument (for systemd instance support), default to awg0
AWG_IFACE="${2:-awg0}"
AWG_CONF="$AWG_DIR/conf/${AWG_IFACE}.conf"

# Extract number from interface name (e.g., awg0 -> 0, awg1 -> 1, awg10 -> 10)
IFACE_NUM=$(echo "$AWG_IFACE" | grep -oE '[0-9]+$' || echo "0")

# Calculate unique values based on interface number
BASE_TABLE=100
BASE_FWMARK=1
BASE_PRIORITY=32100

# Function to check if a table number is available
check_table_available() {
    local table_num=$1
    # Check main rt_tables file
    if grep -q "^[[:space:]]*${table_num}[[:space:]]" /etc/iproute2/rt_tables 2>/dev/null; then
        return 1
    fi
    # Check rt_tables.d directory
    if [ -d "/etc/iproute2/rt_tables.d/" ]; then
        if grep -q "^[[:space:]]*${table_num}[[:space:]]" /etc/iproute2/rt_tables.d/* 2>/dev/null; then
            return 1
        fi
    fi
    return 0
}

AWG_FWMARK=$(printf "0x%x" $((BASE_FWMARK + IFACE_NUM)))
IP_RULE_PRIORITY=$((BASE_PRIORITY + IFACE_NUM))
IPSET_NAME="vpn_sources_${AWG_IFACE}"

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

        # Find an available table number starting from the calculated base
        AWG_TABLE=$((BASE_TABLE + IFACE_NUM))
        while ! check_table_available "$AWG_TABLE"; do
            AWG_TABLE=$((AWG_TABLE + 10))
        done

        echo "Starting AmneziaWG interface $AWG_IFACE..."
        "$AWG_DIR/bin/awg-quick" up "$AWG_CONF"
        echo "AmneziaWG is up"

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

        # Create ipset for source IPs that should use VPN (if not exists)
        ipset create "$IPSET_NAME" hash:net 2>/dev/null || true
        echo "Created/verified ipset '$IPSET_NAME'"

        # Mark traffic from ipset with fwmark
        iptables -t mangle -A PREROUTING -m set --match-set "$IPSET_NAME" src -j MARK --set-mark "$AWG_FWMARK" 2>/dev/null || true
        iptables -t mangle -A OUTPUT -m set --match-set "$IPSET_NAME" src -j MARK --set-mark "$AWG_FWMARK" 2>/dev/null || true
        echo "Added iptables rules to mark traffic from $IPSET_NAME with mark $AWG_FWMARK"

        # Add ip rule to route marked traffic through custom table
        ip rule add fwmark "$AWG_FWMARK" lookup "$AWG_TABLE" priority "$IP_RULE_PRIORITY" 2>/dev/null || true
        echo "Added ip rule: fwmark $AWG_FWMARK -> table $AWG_TABLE (priority $IP_RULE_PRIORITY)"

        iptables -t nat -A POSTROUTING -o "$AWG_IFACE" -j MASQUERADE
        echo "Added MASQUERADE rule for $AWG_IFACE"

        "$AWG_DIR/bin/awg" show
        ;;
    down)
        echo "Stopping AmneziaWG interface $AWG_IFACE..."

        # Read the actual table number used by this interface from rt_tables.d
        RT_TABLES_FILE="/etc/iproute2/rt_tables.d/custom.conf"
        AWG_TABLE=""
        if [ -f "$RT_TABLES_FILE" ]; then
            AWG_TABLE=$(grep -E "^[0-9]+[[:space:]]+${AWG_IFACE}$" "$RT_TABLES_FILE" | awk '{print $1}' | head -1)
        fi
        if [ -z "$AWG_TABLE" ]; then
            # Fallback to calculated value
            AWG_TABLE=$((BASE_TABLE + IFACE_NUM))
            echo "Warning: Could not find routing table for $AWG_IFACE in $RT_TABLES_FILE, using calculated value: $AWG_TABLE"
        fi

        # Remove MASQUERADE rule
        iptables -t nat -D POSTROUTING -o "$AWG_IFACE" -j MASQUERADE 2>/dev/null || true
        echo "Removed MASQUERADE rule for $AWG_IFACE"

        # Remove ip rule
        ip rule del fwmark "$AWG_FWMARK" lookup "$AWG_TABLE" priority "$IP_RULE_PRIORITY" 2>/dev/null || true
        echo "Removed ip rule for fwmark $AWG_FWMARK"

        # Remove iptables mangle rules
        iptables -t mangle -D PREROUTING -m set --match-set "$IPSET_NAME" src -j MARK --set-mark "$AWG_FWMARK" 2>/dev/null || true
        iptables -t mangle -D OUTPUT -m set --match-set "$IPSET_NAME" src -j MARK --set-mark "$AWG_FWMARK" 2>/dev/null || true
        echo "Removed iptables mangle rules for $IPSET_NAME"

        # Destroy ipset
        ipset destroy "$IPSET_NAME" 2>/dev/null || true
        echo "Destroyed ipset '$IPSET_NAME'"

        # Remove default route from custom table
        ip route del default dev "$AWG_IFACE" table "$AWG_TABLE" 2>/dev/null || true
        echo "Removed default route from table $AWG_TABLE"

        # Remove routing table entry from rt_tables.d
        RT_TABLES_FILE="/etc/iproute2/rt_tables.d/custom.conf"
        if [ -f "$RT_TABLES_FILE" ]; then
            sed -i "/^${AWG_TABLE}[[:space:]]/d" "$RT_TABLES_FILE" 2>/dev/null || true
            echo "Removed routing table entry from $RT_TABLES_FILE"
        fi

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
