# AmneziaWG for UniFi

Run [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go) (WireGuard with DPI obfuscation) on UniFi Dream Router 7 (UDR7) and other UniFi OS devices.

## Features

- Pre-built ARM64 binaries for UniFi devices
- Survives reboots via systemd service
- Easy recovery after firmware updates
- Client mode for connecting to external VPN servers

## Supported Devices

| Device | Architecture | UniFi OS | Status |
|--------|-------------|----------|--------|
| UDR7 | ARM64 (IPQ5322) | 4.x | Tested |
| UDR | ARM64 | 3.x/4.x | Should work |
| UDM-SE | ARM64 | 3.x/4.x | Should work |
| UDM Pro | ARM64 | 2.x/3.x | Untested |

## Quick Start

### 1. Download release

```bash
# On your local machine
curl -LO https://github.com/atom363/amneziawg-unifi/releases/download/v0.0.4/amneziawg-unifi-v0.0.4-arm64.tar.gz
```

### 2. Deploy to router

```bash
# Upload to router
scp amneziawg-unifi-v0.0.4-arm64.tar.gz root@172.16.0.1:/tmp/

# SSH to router and install
ssh root@172.16.0.1
cd /data
tar xzf /tmp/amneziawg-unifi-v0.0.4-arm64.tar.gz
./amneziawg/install.sh
```

### 3. Configure

```bash
# Edit your config (example provided)
vi /data/amneziawg/conf/awg0.conf

# Start VPN
systemctl start amneziawg
```

## Configuration (must be without DNS option)

If you don't want to send all traffic through vpn set Table = off in [Interface] section of config for managing routing manually
Example client config (`/data/amneziawg/conf/awg0.conf`):

```ini
[Interface]
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

## After Firmware Update

UniFi firmware updates overwrite `/etc/systemd/system/`. Run:

```bash
ssh root@172.16.0.1 "/data/amneziawg/reinstall.sh"
```

## Building from Source

Requires Go 1.21+ and cross-compilation toolchain:

```bash
make build-arm64
make package
```

## How It Works

1. **amneziawg-go**: Userspace WireGuard implementation with obfuscation
2. **awg/awg-quick**: CLI tools for managing tunnels
3. **systemd service**: Starts VPN on boot
4. **/data/ persistence**: Survives reboots (but not firmware updates for systemd)

## License

BSD-3-Clause

## Credits

- [AmneziaVPN](https://github.com/amnezia-vpn) for the obfuscated WireGuard implementation
- [tusc/wireguard-kmod](https://github.com/tusc/wireguard-kmod) for UDM WireGuard inspiration
