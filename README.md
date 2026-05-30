# Imagitech Enterprise Deployment Pipeline

An automated, idempotent, and highly secure VPN & SSH tunneling orchestration script built for modern VPS infrastructure. This platform provisions a multi-protocol proxy environment complete with real-time monitoring, bandwidth tracking, anti-DDoS features, and a dynamic CLI dashboard.

## 🚀 Features

### Core Protocols & Tunnels
- **OpenSSH & Dropbear:** Multi-port SSH tunneling (Ports 22, 109, 143).
- **Stunnel4 (SSL/TLS):** Encrypted tunneling bridging (Ports 447, 777).
- **Asynchronous WebSocket Proxy:** High-performance, async WS multiplexer supporting HTTP Injection and ISP Bypassing on ports 80, 443, and 8880.
- **UDP Custom:** High-performance direct UDP tunneling for intensive gaming/voice packets (Ports 1-65535).
- **DNSTT (SlowDNS):** Advanced payload encapsulation through DNS queries for deeply restricted networks (Ports 53, 5300).
- **Dante SOCKS5 Proxy:** Standalone SOCKS proxy (Port 1080).

### Security & Monitoring
- **Real-time Session Monitoring:** Python daemon tracks active SSH/WS logins to strictly enforce concurrent multi-login limits.
- **Fail2Ban Integration:** Configured out-of-the-box to drop bots and prevent SSH brute force attacks.
- **Bandwidth Accounting:** Granular byte tracking using low-level IPTables hooks integrated into an SQLite3 database.
- **OS Reaper:** Automatically deletes Linux accounts and kills active sessions exactly when a user's subscription expires.
- **Encrypted Backups:** AES-256-CBC powered backups for databases, TLS certificates, and DNS keys.

## 📦 Installation

To deploy the platform on a fresh Ubuntu/Debian server, run the following as `root`:

```bash
apt-get update -y && apt-get install -y curl wget
bash <(curl -sS -L https://raw.githubusercontent.com/dexteree11/autoscriptssh/main/install.sh)
```

## 🛠️ Usage

Once the installation is complete, you can access the platform in two ways:

1. **Interactive Dashboard:** Type `menu` to launch the comprehensive TUI panel for managing users, monitoring connections, and modifying system settings.
2. **Headless API:** Type `imagitech` followed by an API command for automation and scripting.
   - Example: `imagitech user add test 12345 30` (Create user 'test' with pass '12345' for 30 days)
   - Example: `imagitech service restart all`

## 📂 Architecture

The system avoids cluttering your global namespace. All configurations, binaries, and databases are strictly sandboxed inside `/opt/imagitech/`.

- `/opt/imagitech/core/`: SQLite3 Databases, SSL certificates, DNSTT public/private keys.
- `/opt/imagitech/services/`: Python daemons (Monitor, Async Routing Proxy).
- `/opt/imagitech/lib/`: Core bash modules (system, users, database).
- `/opt/imagitech/logs/`: Managed logs with built-in rotation.

## ⚠️ Disclaimer
This script is intended for educational purposes, privacy enhancement, and network administration. Abuse of this service for spam, DDoS, or illegal torrenting is strictly prohibited. Use responsibly.
