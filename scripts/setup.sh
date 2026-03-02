#!/bin/bash
set -e

AWG_DIR="/data/amneziawg"
AWG_CONF="$AWG_DIR/conf/awg0.conf"
AWG_IFACE="awg0"
AWG_FWMARK="0x1"
IPSET_NAME="vpn_sources_${AWG_IFACE}"
IP_RULE_PRIORITY="32100"

# Function to find an available routing table number
find_available_table_number() {
    local base_table=${1:-100}
    local current_table=$base_table
    
    while true; do
        # Check if the table number exists in /etc/iproute2/rt_tables
        if grep -q "^[[:space:]]*${current_table}[[:space:]]\+" /etc/iproute2/rt_tables 2>/dev/null; then
            current_table=$((current_table + 10))
            continue
        fi
        
        # Check if the table number exists in files under /etc/iproute2/rt_tables.d/
        if [ -d "/etc/iproute2/rt_tables.d/" ]; then
            if grep -q "^[[:space:]]*${current_table}[[:space:]]\+" /etc/iproute2/rt_tables.d/* 2>/dev/null; then
                current_table=$((current_table + 10))
                continue
            fi
        fi
        
        # Table number is available
        echo $current_table
        return 0
    done
}

# Find an available routing table number (only for 'up' command)
if [ "$1" = "up" ]; then
    AWG_TABLE=$(find_available_table_number 100)
fi

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

        # Find the table number used by this interface from rt_tables.d
        RT_TABLES_FILE="/etc/iproute2/rt_tables.d/custom.conf"
        if [ -f "$RT_TABLES_FILE" ]; then
            AWG_TABLE=$(grep -E "^[0-9]+[[:space:]]+${AWG_IFACE}$" "$RT_TABLES_FILE" | awk '{print $1}' | head -1)
        fi
        if [ -z "$AWG_TABLE" ]; then
            echo "Warning: Could not find routing table for $AWG_IFACE, using default 100"
            AWG_TABLE="100"
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
