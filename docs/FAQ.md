# Frequently Asked Questions

## General Questions

### What is CF-Firewall?

CF-Firewall is a Linux firewall management tool that restricts access to specific ports only from Cloudflare's IP ranges. This ensures that your origin server can only be accessed through Cloudflare's CDN, providing an additional layer of security.

### Why do I need CF-Firewall?

If you're using Cloudflare as a CDN/proxy:
- **Security**: Prevents direct attacks on your origin server
- **DDoS Protection**: Forces all traffic through Cloudflare's DDoS protection
- **Performance**: Ensures all visitors benefit from Cloudflare's caching
- **Analytics**: All traffic is logged by Cloudflare

### Is CF-Firewall free?

Yes, CF-Firewall is open-source software released under the MIT License.

## Installation

### What are the system requirements?

- Linux-based operating system
- iptables and ip6tables
- ipset
- curl
- systemd (optional, for service management)
- Root/sudo access

### Which Linux distributions are supported?

CF-Firewall works on:
- Ubuntu 18.04+
- Debian 9+
- CentOS/RHEL 7+
- Fedora 30+
- Any Linux distribution with iptables and ipset

### How do I install CF-Firewall?

```bash
curl -sSL https://raw.githubusercontent.com/axiilay/cf-firewall/main/install.sh | sudo bash
```

Or manually:

```bash
sudo wget -O /usr/local/bin/cf-firewall https://raw.githubusercontent.com/axiilay/cf-firewall/main/cf-firewall.sh
sudo chmod +x /usr/local/bin/cf-firewall
sudo cf-firewall init
```

## Configuration

### How do I add a new port?

```bash
sudo cf-firewall add-port 8080
```

### How do I add my IP for debugging?

```bash
sudo cf-firewall add-ip YOUR_IP_ADDRESS
```

### Where are configuration files stored?

All configuration files are in `/etc/cloudflare-firewall/`:
- `config.conf` - Main configuration
- `ports.conf` - Protected ports list
- `debug_ips.conf` - Debug IP addresses
- `cloudflare_ipv4.txt` - Cached Cloudflare IPv4 ranges
- `cloudflare_ipv6.txt` - Cached Cloudflare IPv6 ranges

### How often should I update Cloudflare IPs?

Cloudflare rarely changes their IP ranges, but we recommend updating weekly:

```bash
# Add to crontab
0 3 * * 0 /usr/local/bin/cf-firewall update
```

## Troubleshooting

### I'm locked out! How do I regain access?

1. **Console/Physical Access**:
   ```bash
   sudo systemctl stop cloudflare-firewall
   ```

2. **Recovery/Rescue Mode**:
   ```bash
   iptables -F
   ip6tables -F
   ```

3. **Via hosting provider's console**:
   ```bash
   sudo cf-firewall add-ip YOUR_IP
   ```

### The firewall isn't blocking connections

Check if rules are active:

```bash
sudo cf-firewall status
sudo iptables -L | grep CF_PORT
```

Verify the port is protected:

```bash
sudo cf-firewall list-ports
```

### How do I check if an IP is allowed?

Check if IP is in Cloudflare ranges:

```bash
sudo ipset test cloudflare_ipv4 IP_ADDRESS
```

Check debug IPs:

```bash
sudo ipset test debug_ipv4 IP_ADDRESS
```

### The service won't start

Check for errors:

```bash
sudo systemctl status cloudflare-firewall
sudo journalctl -xe | grep cloudflare
```

Common issues:
- Missing ipset kernel module
- iptables service not running
- Syntax error in configuration files

## Security

### Is this 100% secure?

No security solution is 100% secure. CF-Firewall adds a layer of protection but should be part of a comprehensive security strategy including:
- Regular security updates
- Strong authentication
- Application-level security
- Regular security audits

### Can attackers bypass Cloudflare?

CF-Firewall prevents direct access to your server, but:
- Ensure your real IP isn't leaked (check DNS records, email headers, etc.)
- Use Cloudflare's authenticated origin pulls
- Implement rate limiting
- Keep your server updated

### What about UDP traffic?

CF-Firewall only manages TCP traffic. For UDP services, you'll need additional rules.

### Should I protect SSH (port 22)?

**Not recommended** unless you're accessing SSH through Cloudflare Spectrum. Instead:
- Use a different port for SSH
- Use key-based authentication
- Implement fail2ban
- Use a jump box/bastion host

## Performance

### Will this impact server performance?

Minimal impact:
- ipset is highly optimized for IP matching
- Rules are processed efficiently by netfilter
- Typical overhead: <1% CPU

### How many IPs can it handle?

ipset can handle thousands of IP ranges efficiently. Current Cloudflare IPs (~15 IPv4 + 7 IPv6 ranges) have negligible impact.

### What about high-traffic sites?

CF-Firewall is suitable for high-traffic sites. For optimization:
- Increase connection tracking limits
- Disable logging on high-traffic ports
- Use hardware firewall for additional capacity

## Maintenance

### How do I backup my configuration?

```bash
sudo tar -czf cf-firewall-backup.tar.gz /etc/cloudflare-firewall/
```

### How do I migrate to a new server?

1. Backup on old server:
   ```bash
   sudo tar -czf cf-firewall-config.tar.gz /etc/cloudflare-firewall/
   ```

2. Copy to new server and extract:
   ```bash
   sudo tar -xzf cf-firewall-config.tar.gz -C /
   ```

3. Install CF-Firewall:
   ```bash
   sudo cf-firewall init
   ```

### How do I uninstall CF-Firewall?

```bash
# Stop and disable service
sudo systemctl stop cloudflare-firewall
sudo systemctl disable cloudflare-firewall

# Remove files
sudo rm /usr/local/bin/cf-firewall
sudo rm -rf /etc/cloudflare-firewall/
sudo rm /etc/systemd/system/cloudflare-firewall.service

# Clean up iptables rules (optional)
sudo iptables -F
sudo ip6tables -F
```

## Advanced Usage

### Can I use this with Docker?

Yes, but there are considerations:

**If using iptables mode:**
```bash
sudo systemctl edit cloudflare-firewall.service
# Add: Before=docker.service
```

**If using nftables mode:**
Docker primarily uses iptables. You have two options:

1. Use iptables mode for compatibility:
```bash
sudo cf-firewall switch-backend iptables
```

2. Use both (advanced users):
- Let CF-Firewall use nftables
- Let Docker use iptables
- They can coexist with proper configuration

### What's the difference between iptables and nftables modes?

**iptables mode:**
- Uses traditional iptables + ipset
- Better compatibility with older systems
- Required for some applications (older Docker versions)
- Familiar to most administrators

**nftables mode:**
- Modern replacement for iptables
- Better performance (10-40% less CPU usage)
- Cleaner syntax and atomic updates
- Built-in set support (no ipset needed)
- Recommended for new installations

### How do I switch between iptables and nftables?

```bash
# Switch to nftables
sudo cf-firewall switch-backend nftables

# Switch to iptables
sudo cf-firewall switch-backend iptables

# Check current backend
sudo cf-firewall status
```

### Can I use this with other CDNs?

Yes, you can modify the IP sources. For example, for Fastly:
- Update the IP URLs in the configuration
- Or manually add IP ranges using `cf-firewall add-ip`

### Can I exclude certain IPs from blocking?

Yes, use debug IPs:

```bash
sudo cf-firewall add-ip TRUSTED_IP
```

### How do I integrate with monitoring tools?

Check firewall status programmatically:

```bash
# Check if service is running
systemctl is-active cloudflare-firewall

# Count blocked connections
journalctl --since="1 hour ago" | grep -c "CF-Blocked"
```

## Getting Help

### Where can I get support?

1. Check the [documentation](https://github.com/axiilay/cf-firewall)
2. Search [existing issues](https://github.com/axiilay/cf-firewall/issues)
3. Open a [new issue](https://github.com/axiilay/cf-firewall/issues/new)
4. Read the [Advanced Guide](ADVANCED.md)

### How can I contribute?

We welcome contributions! See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

### I found a security issue. How do I report it?

Please report security issues privately to the maintainers rather than opening a public issue.
