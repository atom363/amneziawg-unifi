# AmneziaWG for UniFi

Run [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go) (WireGuard with DPI obfuscation) on UniFi Dream Router 7 (UDR7) and other UniFi OS devices.

## Features

- Pre-built ARM64 binaries for UniFi devices
- **Multiple tunnel support** via systemd instances (e.g., `amneziawg@awg0`, `amneziawg@awg1`)
- **Selective routing** via ipset - only route specific source IPs through VPN
- Automatic routing table management with conflict detection
- Survives reboots via systemd service
- Easy recovery after firmware updates
- Client mode for connecting to external VPN servers

## Supported Devices

| Device | Architecture | UniFi OS | Status |
|--------|-------------|----------|--------|
| UDR7 | ARM64 (IPQ5322) | 4.x | Should work |
| UDR | ARM64 | 3.x/4.x | Should work |
| UDM-SE | ARM64 | 3.x/4.x | Tested |
| UDM Pro | ARM64 | 2.x/3.x | Untested |

## Quick Start

### 1. Deploy to router

```bash

# SSH to router and install
ssh root@172.16.0.1
cd /data
curl -L https://github.com/atom363/amneziawg-unifi/releases/latest/download/amneziawg-unifi-arm64.tar.gz | tar xvzf -
./amneziawg/install.sh
```

### 2. Configure

```bash
# Edit your config (example provided)
vi /data/amneziawg/conf/awg0.conf

# Start VPN (using systemd instance for multiple tunnels)
systemctl start amneziawg@awg0

# Enable auto-start on boot
systemctl enable amneziawg@awg0
```

## Configuration

### Basic Config (must be without DNS option)

If you don't want to send all traffic through vpn set Table = off in [Interface] section of config for managing routing manually
Example client config (`/data/amneziawg/conf/awg0.conf`):

```ini
[Interface]
Table = off
PrivateKey = YOUR_PRIVATE_KEY
Address = 10.8.0.2/24
# AmneziaWG obfuscation parameters
Jc = 4
Jmin = 40
Jmax = 70
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### Multiple Tunnels

Create additional config files and start as separate instances:

```bash
# Create config for second tunnel
cp /data/amneziawg/conf/awg0.conf /data/amneziawg/conf/awg1.conf
vi /data/amneziawg/conf/awg1.conf  # Edit with different settings

# Start second tunnel
systemctl start amneziawg@awg1
systemctl enable amneziawg@awg1
```

Each tunnel gets unique routing parameters automatically derived from the interface number:
- `awg0`: table 100, fwmark 0x1, priority 32100
- `awg1`: table 101, fwmark 0x2, priority 32101
- etc.

### Selective Routing (ipset)

By default, no traffic is routed through VPN. Add source IPs to the ipset to route them through the tunnel:

```bash
# Add a specific IP to route through VPN (for awg0)
ipset add vpn_sources_awg0 192.168.1.100

# Add a subnet
ipset add vpn_sources_awg0 192.168.1.0/24

# List current IPs
ipset list vpn_sources_awg0

# Remove an IP
ipset del vpn_sources_awg0 192.168.1.100
```

Each tunnel has its own ipset (e.g., `vpn_sources_awg0`, `vpn_sources_awg1`).

## Managing Tunnels

```bash
# Check status
systemctl status amneziawg@awg0

# View tunnel info
/data/amneziawg/bin/awg show

# Restart tunnel
systemctl restart amneziawg@awg0

# Stop tunnel
systemctl stop amneziawg@awg0
```

## After Firmware Update

UniFi firmware updates overwrite `/etc/systemd/system/`. Run:

```bash
ssh root@172.16.0.1 "/data/amneziawg/reinstall.sh"
```

This restores all enabled tunnel services.

## Building from Source

Requires Go 1.21+ and cross-compilation toolchain:

```bash
make build-arm64
make package
```

## How It Works

1. **amneziawg-go**: Userspace WireGuard implementation with obfuscation
2. **awg/awg-quick**: CLI tools for managing tunnels
3. **setup.sh**: Manages routing tables, ipset, iptables rules, and ip rules for selective routing
4. **systemd service**: Template service (`amneziawg@.service`) supports multiple tunnel instances
5. **/data/ persistence**: Survives reboots (but not firmware updates for systemd)

### Routing Flow

1. Traffic from IPs in `vpn_sources_<interface>` ipset is marked with fwmark
2. ip rule routes marked traffic to a custom routing table
3. Custom routing table has default route through the WireGuard interface
4. MASQUERADE handles NAT for outgoing traffic

## License

BSD-3-Clause

## Credits

- [AmneziaVPN](https://github.com/amnezia-vpn) for the obfuscated WireGuard implementation
- [tusc/wireguard-kmod](https://github.com/tusc/wireguard-kmod) for UDM WireGuard inspiration
