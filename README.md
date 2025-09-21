# CF-Firewall

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/shell_script-%23121011.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?logo=Cloudflare&logoColor=white)](https://www.cloudflare.com/)

A comprehensive firewall management tool for restricting access to specific ports only from Cloudflare IP ranges and custom debug IPs. Perfect for protecting origin servers behind Cloudflare's CDN.

## Features

- 🔒 **Multi-port Support**: Manage multiple ports (HTTP, HTTPS, custom ports)
- 🌐 **Dual Stack**: Full IPv4 and IPv6 support
- 🔄 **Auto-update**: Automatically fetch latest Cloudflare IP ranges
- 🛠️ **Debug Mode**: Easily add/remove temporary IPs for development
- 💾 **Persistent Rules**: Survives reboots with systemd integration
- 📊 **Status Monitoring**: View connection statistics and firewall status
- 🚀 **High Performance**: Uses ipset (iptables) or native sets (nftables)
- 📝 **Logging**: Optional connection rejection logging
- 🔧 **Dual Backend Support**: Works with both iptables and nftables

## Quick Start

### Installation

```bash
# Or use the install script
curl -sSL https://raw.githubusercontent.com/axiilay/cf-firewall/main/install.sh | sudo bash
```

```bash
# Download the script
sudo wget -O /usr/local/bin/cf-firewall https://raw.githubusercontent.com/axiilay/cf-firewall/main/cf-firewall.sh
sudo chmod +x /usr/local/bin/cf-firewall
```

### Initialize (First Use)

```bash
sudo cf-firewall init
```

This will:
- Create configuration directory `/etc/cloudflare-firewall/`
- Set up default ports (80, 443, 8443)
- Download and configure Cloudflare IPs
- Create systemd service for persistence

## Usage

### Port Management

```bash
# Add a new port
sudo cf-firewall add-port 8080

# Remove a port
sudo cf-firewall remove-port 8080

# List all protected ports
sudo cf-firewall list-ports
```

### Debug IP Management

```bash
# Add debug IPs
sudo cf-firewall add-ip 192.168.1.100
sudo cf-firewall add-ip 10.0.0.0/24
sudo cf-firewall add-ip 2001:db8::1/64

# Remove debug IP
sudo cf-firewall remove-ip 192.168.1.100

# List all IPs
sudo cf-firewall list-ips

# Clear all debug IPs
sudo cf-firewall clear-ips
```

### System Management

```bash
# View status
sudo cf-firewall status

# Update Cloudflare IPs
sudo cf-firewall update

# Service control
sudo systemctl start cloudflare-firewall
sudo systemctl stop cloudflare-firewall
sudo systemctl reload cloudflare-firewall
sudo systemctl status cloudflare-firewall
```

## Firewall Backend (iptables vs nftables)

CF-Firewall supports both iptables and nftables. It automatically detects which one to use based on your system.

### Auto-detection

The script automatically detects your firewall backend during initialization:
- **nftables** is preferred if available and active
- Falls back to **iptables** if nftables is not available

### Manual Selection

You can manually switch between backends:

```bash
# Switch to nftables (recommended for modern systems)
sudo cf-firewall switch-backend nftables

# Switch to iptables (for compatibility)
sudo cf-firewall switch-backend iptables
```

### Which Should I Use?

**Use nftables if:**
- You're on a modern Linux distribution (Debian 10+, Ubuntu 20.04+, RHEL 8+, Fedora 32+)
- You want better performance
- You prefer cleaner syntax and rules
- You're starting fresh

**Use iptables if:**
- You're on an older system
- You have existing iptables rules you need to maintain
- You're using software that requires iptables
- You're more familiar with iptables

## Configuration

All configuration files are stored in `/etc/cloudflare-firewall/`:

| File | Description |
|------|-------------|
| `config.conf` | Main configuration file |
| `ports.conf` | List of protected ports |
| `debug_ips.conf` | List of debug IPs |
| `cloudflare_ipv4.txt` | Cached Cloudflare IPv4 ranges |
| `cloudflare_ipv6.txt` | Cached Cloudflare IPv6 ranges |

## Auto-update Cloudflare IPs

Set up a cron job to automatically update Cloudflare IPs daily:

```bash
# Edit crontab
sudo crontab -e

# Add this line (updates at 3 AM daily)
0 3 * * * /usr/local/bin/cf-firewall update >/dev/null 2>&1
```

## Requirements

### For iptables mode:
- iptables and ip6tables
- ipset
- curl
- systemd (optional, for service management)
- Root/sudo access

### For nftables mode:
- nftables (v0.9.0+)
- curl
- systemd (optional, for service management)
- Root/sudo access

## Supported Distributions

- Ubuntu 18.04+
- Debian 9+
- CentOS/RHEL 7+
- Fedora 30+
- Any Linux distribution with iptables and ipset

## How It Works

1. **IP Sets**: Creates ipset collections for Cloudflare and debug IPs
2. **Custom Chains**: Creates dedicated iptables chains for each protected port
3. **Rule Matching**: Allows connections from Cloudflare/debug IPs, drops others
4. **Persistence**: Uses systemd service to restore rules on reboot

## Security Considerations

- Always keep at least one debug IP when testing to avoid lockout
- Regularly update Cloudflare IPs to ensure legitimate traffic isn't blocked
- Monitor logs for blocked connection attempts
- Use fail2ban in conjunction for additional protection

## Troubleshooting

### Locked Out?

If you're locked out, boot into recovery mode or use console access:

```bash
# Stop the firewall
sudo systemctl stop cloudflare-firewall

# Or flush all rules
sudo iptables -F
sudo ip6tables -F
```

### Verify Cloudflare IPs

```bash
# List current Cloudflare IPs
sudo cf-firewall list-ips

# Force update from Cloudflare
sudo cf-firewall update
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Cloudflare](https://www.cloudflare.com/) for providing their IP ranges publicly
- The iptables and ipset projects for powerful firewall capabilities

## Support

If you find this project useful, please consider:
- ⭐ Starring the repository
- 🐛 Reporting bugs
- 💡 Suggesting new features
- 🤝 Contributing code

## Related Projects

- [cloudflare-ufw](https://github.com/Paul-Reed/cloudflare-ufw) - UFW rules for Cloudflare
- [nginx-cloudflare-real-ip](https://github.com/ergin/nginx-cloudflare-real-ip) - Nginx real IP configuration for Cloudflare
