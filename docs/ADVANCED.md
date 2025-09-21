# Advanced Configuration Guide

This guide covers advanced configuration options and use cases for CF-Firewall.

## Table of Contents

- [Custom Configuration](#custom-configuration)
- [Port Ranges](#port-ranges)
- [Advanced IP Management](#advanced-ip-management)
- [Integration with Other Services](#integration-with-other-services)
- [Performance Tuning](#performance-tuning)
- [Troubleshooting](#troubleshooting)

## Custom Configuration

### Configuration File Structure

The main configuration file is located at `/etc/cloudflare-firewall/config.conf`:

```bash
# Cloudflare IP update URLs
CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

# Enable IPv6 support
ENABLE_IPV6=true

# Enable auto-update
AUTO_UPDATE=true

# Log level (DEBUG, INFO, WARN, ERROR)
LOG_LEVEL="INFO"
```

### Disabling IPv6

If you don't need IPv6 support:

```bash
# Edit config file
sudo nano /etc/cloudflare-firewall/config.conf
# Set ENABLE_IPV6=false

# Reload service
sudo cf-firewall reload
```

## Port Ranges

### Adding Multiple Ports at Once

Create a script to add multiple ports:

```bash
#!/bin/bash
ports=(8080 8081 8082 8083 8084)
for port in "${ports[@]}"; do
    sudo cf-firewall add-port $port
done
```

### Protecting Non-HTTP Services

CF-Firewall can protect any TCP service:

```bash
# SSH (not recommended unless you know what you're doing)
sudo cf-firewall add-port 22

# Custom application
sudo cf-firewall add-port 3000

# Database ports (be very careful!)
sudo cf-firewall add-port 3306  # MySQL
sudo cf-firewall add-port 5432  # PostgreSQL
```

## Advanced IP Management

### Bulk IP Import

Import multiple debug IPs from a file:

```bash
#!/bin/bash
# Create a file with IPs (one per line)
cat > /tmp/debug_ips.txt << EOF
192.168.1.0/24
10.0.0.0/8
172.16.0.0/16
EOF

# Import all IPs
while IFS= read -r ip; do
    sudo cf-firewall add-ip "$ip"
done < /tmp/debug_ips.txt
```

### Temporary Access

Grant temporary access for a specific duration:

```bash
#!/bin/bash
# Grant 1-hour access
IP="203.0.113.10"
sudo cf-firewall add-ip $IP
echo "cf-firewall remove-ip $IP" | at now + 1 hour
```

### Dynamic IP Updates

For dynamic IPs (like home connections):

```bash
#!/bin/bash
# Update dynamic IP script
CURRENT_IP=$(curl -s https://api.ipify.org)
OLD_IP_FILE="/var/lib/cf-firewall/my_dynamic_ip"

if [ -f "$OLD_IP_FILE" ]; then
    OLD_IP=$(cat "$OLD_IP_FILE")
    if [ "$OLD_IP" != "$CURRENT_IP" ]; then
        sudo cf-firewall remove-ip "$OLD_IP"
    fi
fi

sudo cf-firewall add-ip "$CURRENT_IP"
echo "$CURRENT_IP" > "$OLD_IP_FILE"
```

Add to crontab for automatic updates:

```bash
*/5 * * * * /usr/local/bin/update_dynamic_ip.sh
```

## Integration with Other Services

### Docker Integration

Ensure CF-Firewall rules are applied before Docker:

```bash
# Edit systemd service
sudo systemctl edit cloudflare-firewall.service

# Add:
[Unit]
Before=docker.service
```

### Nginx Real IP Configuration

Configure Nginx to get real visitor IPs:

```nginx
# /etc/nginx/conf.d/cloudflare-real-ip.conf
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;

# IPv6
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;

real_ip_header CF-Connecting-IP;
```

### Fail2ban Integration

Use with fail2ban for additional protection:

```ini
# /etc/fail2ban/jail.local
[cf-firewall-abuse]
enabled = true
filter = cf-firewall-abuse
logpath = /var/log/syslog
maxretry = 10
findtime = 60
bantime = 3600
action = iptables-ipset-proto6[name=fail2ban_cf, port=all, protocol=tcp, bantime=3600]
```

## Performance Tuning

### ipset Optimization

Optimize ipset for large IP lists:

```bash
# Increase hash size for better performance
ipset create cloudflare_ipv4_optimized hash:net family inet hashsize 4096 maxelem 65536
```

### Connection Tracking

Optimize connection tracking for high traffic:

```bash
# /etc/sysctl.d/99-cf-firewall.conf
net.netfilter.nf_conntrack_max = 524288
net.netfilter.nf_conntrack_buckets = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 21600
```

Apply settings:

```bash
sudo sysctl -p /etc/sysctl.d/99-cf-firewall.conf
```

### Logging Optimization

Reduce logging overhead:

```bash
# Disable logging for high-traffic ports
sudo iptables -R CF_PORT_443 3 -j DROP  # Remove logging rule
```

## Troubleshooting

### Debug Mode

Enable debug logging:

```bash
# Edit config
sudo nano /etc/cloudflare-firewall/config.conf
# Set LOG_LEVEL="DEBUG"

# Watch logs
sudo journalctl -f | grep CF-
```

### Connection Testing

Test if connections are being blocked:

```bash
# From a non-Cloudflare IP
curl -v http://your-server:8443

# Check dropped packets
sudo iptables -L CF_PORT_8443 -n -v
```

### Recovery Mode

If locked out, boot into recovery mode:

```bash
# In recovery/rescue mode
mount /dev/sda1 /mnt  # Mount root partition
chroot /mnt
systemctl disable cloudflare-firewall
reboot
```

### Manual Rule Inspection

Inspect current rules:

```bash
# List all CF-Firewall chains
sudo iptables -L | grep CF_PORT

# Show detailed rules for a specific port
sudo iptables -L CF_PORT_443 -n -v --line-numbers

# Check ipset contents
sudo ipset list cloudflare_ipv4 | head -20
```

### Reset Everything

Complete reset if needed:

```bash
#!/bin/bash
# Stop service
sudo systemctl stop cloudflare-firewall

# Remove all rules
for chain in $(sudo iptables -L | grep CF_PORT | awk '{print $2}'); do
    sudo iptables -F $chain
    sudo iptables -X $chain
done

# Clear ipsets
sudo ipset destroy cloudflare_ipv4
sudo ipset destroy cloudflare_ipv6
sudo ipset destroy debug_ipv4
sudo ipset destroy debug_ipv6

# Remove config
sudo rm -rf /etc/cloudflare-firewall

# Reinstall
sudo cf-firewall init
```

## Security Best Practices

1. **Always maintain debug access**: Keep at least one debug IP active
2. **Regular updates**: Update Cloudflare IPs weekly
3. **Monitor logs**: Check for unusual blocking patterns
4. **Backup configuration**: Regular backup of `/etc/cloudflare-firewall/`
5. **Test changes**: Always test in a development environment first
6. **Use version control**: Track configuration changes
7. **Implement monitoring**: Set up alerts for firewall issues

## Performance Metrics

Monitor firewall performance:

```bash
#!/bin/bash
# Performance monitoring script
echo "=== CF-Firewall Performance ==="
echo "Active connections:"
ss -s

echo -e "\nIPTables rules count:"
iptables -S | wc -l

echo -e "\nIPSet entries:"
ipset list -t | grep "Number of entries"

echo -e "\nDropped packets (last hour):"
journalctl --since="1 hour ago" | grep -c "CF-Blocked"
```
