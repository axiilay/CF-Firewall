#!/bin/bash

# CF-Firewall - Cloudflare IP Firewall Management Tool
# https://github.com/axiilay/cf-firewall
# License: MIT
# Version: 2.0.0

# Color output
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color

# Configuration paths
CONFIG_DIR="/etc/cloudflare-firewall"
CONFIG_FILE="$CONFIG_DIR/config.conf"
PORTS_FILE="$CONFIG_DIR/ports.conf"
DEBUG_IPS_FILE="$CONFIG_DIR/debug_ips.conf"
FIREWALL_MODE_FILE="$CONFIG_DIR/firewall_mode"

# Cloudflare IP sources
CLOUDFLARE_IPV4_URL="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPV6_URL="https://www.cloudflare.com/ips-v6"

# Firewall backend (auto-detected or configured)
FIREWALL_BACKEND=""

# iptables/ipset names
IPSET_CF_V4="cloudflare_ipv4"
IPSET_CF_V6="cloudflare_ipv6"
IPSET_DEBUG_V4="debug_ipv4"
IPSET_DEBUG_V6="debug_ipv6"

# nftables names
NFT_TABLE="cloudflare_firewall"
NFT_SET_CF_V4="cf_ipv4"
NFT_SET_CF_V6="cf_ipv6"
NFT_SET_DEBUG_V4="debug_ipv4"
NFT_SET_DEBUG_V6="debug_ipv6"
NFT_SET_PORTS="protected_ports"

# Chain name prefix
CHAIN_PREFIX="CF_PORT_"

# Default ports
DEFAULT_PORTS=(80 443 8443)

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Detect firewall backend
detect_firewall_backend() {
    local detected=""
    
    # Check if mode is already configured
    if [[ -f "$FIREWALL_MODE_FILE" ]]; then
        FIREWALL_BACKEND=$(cat "$FIREWALL_MODE_FILE")
        echo -e "${GREEN}Using configured firewall backend: $FIREWALL_BACKEND${NC}"
        return
    fi
    
    # Auto-detect
    if command -v nft &> /dev/null; then
        # Check if nftables is actually in use
        if nft list tables &> /dev/null && [[ $(nft list tables 2>/dev/null | wc -l) -gt 0 ]]; then
            detected="nftables"
        elif systemctl is-active --quiet nftables; then
            detected="nftables"
        fi
    fi
    
    if [[ -z "$detected" ]] && command -v iptables &> /dev/null; then
        # Check if iptables is actually usable
        if iptables -L &> /dev/null; then
            detected="iptables"
        fi
    fi
    
    if [[ -z "$detected" ]]; then
        echo -e "${RED}Error: No supported firewall backend found${NC}"
        echo "Please install either iptables or nftables"
        exit 1
    fi
    
    FIREWALL_BACKEND="$detected"
    echo -e "${GREEN}Auto-detected firewall backend: $FIREWALL_BACKEND${NC}"
    
    # Save detected mode
    echo "$FIREWALL_BACKEND" > "$FIREWALL_MODE_FILE"
}

# Initialize configuration directory
init_config_dir() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        echo -e "${GREEN}Created configuration directory: $CONFIG_DIR${NC}"
    fi
    
    # Initialize ports configuration file
    if [[ ! -f "$PORTS_FILE" ]]; then
        printf "%s\n" "${DEFAULT_PORTS[@]}" > "$PORTS_FILE"
        echo -e "${GREEN}Initialized default ports: ${DEFAULT_PORTS[*]}${NC}"
    fi
    
    # Initialize debug IPs file
    if [[ ! -f "$DEBUG_IPS_FILE" ]]; then
        touch "$DEBUG_IPS_FILE"
    fi
    
    # Create main configuration file
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << EOF
# Cloudflare Firewall Configuration
# Generated: $(date)

# Cloudflare IP update URLs
CF_IPV4_URL="$CLOUDFLARE_IPV4_URL"
CF_IPV6_URL="$CLOUDFLARE_IPV6_URL"

# Enable IPv6 support
ENABLE_IPV6=true

# Enable auto-update
AUTO_UPDATE=true

# Firewall backend (auto, iptables, nftables)
FIREWALL_BACKEND="auto"

# Log level (DEBUG, INFO, WARN, ERROR)
LOG_LEVEL="INFO"

# Log rejected connections
LOG_REJECTED=true

# Log rate limit (per minute)
LOG_RATE_LIMIT=1
EOF
        echo -e "${GREEN}Created configuration file: $CONFIG_FILE${NC}"
    fi
}

# Get configured ports
get_configured_ports() {
    if [[ -f "$PORTS_FILE" ]]; then
        grep -v '^#' "$PORTS_FILE" | grep -v '^$'
    else
        printf "%s\n" "${DEFAULT_PORTS[@]}"
    fi
}

# Create ipsets (iptables mode)
create_ipsets() {
    echo -e "${GREEN}Creating ipsets...${NC}"
    
    # Check if ipset is available
    if ! command -v ipset &> /dev/null; then
        echo -e "${RED}Error: ipset is not installed${NC}"
        exit 1
    fi
    
    # Create Cloudflare IPv4 set
    ipset create $IPSET_CF_V4 hash:net family inet -exist
    
    # Create Cloudflare IPv6 set
    ipset create $IPSET_CF_V6 hash:net family inet6 -exist
    
    # Create debug IPv4 set
    ipset create $IPSET_DEBUG_V4 hash:net family inet -exist
    
    # Create debug IPv6 set
    ipset create $IPSET_DEBUG_V6 hash:net family inet6 -exist
}

# Create nftables sets
create_nft_sets() {
    echo -e "${GREEN}Creating nftables table and sets...${NC}"
    
    # Create table first
    nft add table inet $NFT_TABLE 2>/dev/null || true
    
    # Delete existing sets if they exist (to ensure clean state)
    nft delete set inet $NFT_TABLE $NFT_SET_CF_V4 2>/dev/null || true
    nft delete set inet $NFT_TABLE $NFT_SET_CF_V6 2>/dev/null || true
    nft delete set inet $NFT_TABLE $NFT_SET_DEBUG_V4 2>/dev/null || true
    nft delete set inet $NFT_TABLE $NFT_SET_DEBUG_V6 2>/dev/null || true
    nft delete set inet $NFT_TABLE $NFT_SET_PORTS 2>/dev/null || true
    
    # Create Cloudflare IPv4 set
    nft add set inet $NFT_TABLE $NFT_SET_CF_V4 '{ type ipv4_addr; flags interval; }'
    
    # Create Cloudflare IPv6 set
    nft add set inet $NFT_TABLE $NFT_SET_CF_V6 '{ type ipv6_addr; flags interval; }'
    
    # Create debug IPv4 set
    nft add set inet $NFT_TABLE $NFT_SET_DEBUG_V4 '{ type ipv4_addr; flags interval; }'
    
    # Create debug IPv6 set
    nft add set inet $NFT_TABLE $NFT_SET_DEBUG_V6 '{ type ipv6_addr; flags interval; }'
    
    # Create ports set
    nft add set inet $NFT_TABLE $NFT_SET_PORTS '{ type inet_service; }'
    
    echo -e "  ${GREEN}✓${NC} Created table: $NFT_TABLE"
    echo -e "  ${GREEN}✓${NC} Created sets: ports, cf_ipv4, cf_ipv6, debug_ipv4, debug_ipv6"
}

# Update Cloudflare IPs
update_cloudflare_ips() {
    echo -e "${GREEN}Updating Cloudflare IP addresses...${NC}"
    
    # Temporary files
    TMP_V4="/tmp/cf_ips_v4_$$.txt"
    TMP_V6="/tmp/cf_ips_v6_$$.txt"
    
    # Download latest Cloudflare IPs
    if curl -s --connect-timeout 10 --max-time 30 $CLOUDFLARE_IPV4_URL -o $TMP_V4 && \
       curl -s --connect-timeout 10 --max-time 30 $CLOUDFLARE_IPV6_URL -o $TMP_V6; then
        
        # Verify downloaded content
        if [[ -s $TMP_V4 ]] && [[ -s $TMP_V6 ]]; then
            # Save updated IPs locally
            cp $TMP_V4 "$CONFIG_DIR/cloudflare_ipv4.txt"
            cp $TMP_V6 "$CONFIG_DIR/cloudflare_ipv6.txt"
            
            # Update based on backend
            if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
                update_nft_cloudflare_ips $TMP_V4 $TMP_V6
            else
                update_ipset_cloudflare_ips $TMP_V4 $TMP_V6
            fi
            
            echo -e "${GREEN}Cloudflare IPs updated successfully${NC}"
        else
            echo -e "${RED}Error: Downloaded IP lists are empty${NC}"
            load_backup_ips
        fi
    else
        echo -e "${RED}Error: Failed to download Cloudflare IP lists${NC}"
        load_backup_ips
    fi
    
    # Clean up temporary files
    rm -f $TMP_V4 $TMP_V6
}

# Update ipset Cloudflare IPs
update_ipset_cloudflare_ips() {
    local v4_file=$1
    local v6_file=$2
    
    # Clear existing Cloudflare IPs
    ipset flush $IPSET_CF_V4
    ipset flush $IPSET_CF_V6
    
    # Add IPv4 addresses
    local v4_count=0
    while IFS= read -r ip; do
        if [[ -n "$ip" && ! "$ip" =~ ^# ]]; then
            ipset add $IPSET_CF_V4 "$ip" -exist
            ((v4_count++))
        fi
    done < "$v4_file"
    echo -e "  ${GREEN}Added $v4_count IPv4 ranges${NC}"
    
    # Add IPv6 addresses
    local v6_count=0
    while IFS= read -r ip; do
        if [[ -n "$ip" && ! "$ip" =~ ^# ]]; then
            ipset add $IPSET_CF_V6 "$ip" -exist
            ((v6_count++))
        fi
    done < "$v6_file"
    echo -e "  ${GREEN}Added $v6_count IPv6 ranges${NC}"
}

# Update nftables Cloudflare IPs
update_nft_cloudflare_ips() {
    local v4_file=$1
    local v6_file=$2
    
    # Build IPv4 elements
    local v4_elements=""
    local v4_count=0
    while IFS= read -r ip; do
        if [[ -n "$ip" && ! "$ip" =~ ^# ]]; then
            if [[ -n "$v4_elements" ]]; then
                v4_elements="$v4_elements, $ip"
            else
                v4_elements="$ip"
            fi
            ((v4_count++))
        fi
    done < "$v4_file"
    
    # Build IPv6 elements
    local v6_elements=""
    local v6_count=0
    while IFS= read -r ip; do
        if [[ -n "$ip" && ! "$ip" =~ ^# ]]; then
            if [[ -n "$v6_elements" ]]; then
                v6_elements="$v6_elements, $ip"
            else
                v6_elements="$ip"
            fi
            ((v6_count++))
        fi
    done < "$v6_file"
    
    # Update sets
    if [[ -n "$v4_elements" ]]; then
        nft flush set inet $NFT_TABLE $NFT_SET_CF_V4
        nft add element inet $NFT_TABLE $NFT_SET_CF_V4 "{ $v4_elements }"
        echo -e "  ${GREEN}Added $v4_count IPv4 ranges${NC}"
    fi
    
    if [[ -n "$v6_elements" ]]; then
        nft flush set inet $NFT_TABLE $NFT_SET_CF_V6
        nft add element inet $NFT_TABLE $NFT_SET_CF_V6 "{ $v6_elements }"
        echo -e "  ${GREEN}Added $v6_count IPv6 ranges${NC}"
    fi
}

# Load backup Cloudflare IPs
load_backup_ips() {
    echo -e "${YELLOW}Loading backup Cloudflare IPs...${NC}"
    
    # Try to load from local backup files first
    if [[ -f "$CONFIG_DIR/cloudflare_ipv4.txt" ]] && [[ -f "$CONFIG_DIR/cloudflare_ipv6.txt" ]]; then
        echo -e "${GREEN}Loading from local backup files...${NC}"
        
        if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
            update_nft_cloudflare_ips "$CONFIG_DIR/cloudflare_ipv4.txt" "$CONFIG_DIR/cloudflare_ipv6.txt"
        else
            update_ipset_cloudflare_ips "$CONFIG_DIR/cloudflare_ipv4.txt" "$CONFIG_DIR/cloudflare_ipv6.txt"
        fi
    else
        # Use hardcoded backup
        echo -e "${YELLOW}Using hardcoded backup IP list${NC}"
        
        # IPv4 addresses
        local CF_IPV4=(
            "173.245.48.0/20"
            "103.21.244.0/22"
            "103.22.200.0/22"
            "103.31.4.0/22"
            "141.101.64.0/18"
            "108.162.192.0/18"
            "190.93.240.0/20"
            "188.114.96.0/20"
            "197.234.240.0/22"
            "198.41.128.0/17"
            "162.158.0.0/15"
            "104.16.0.0/13"
            "104.24.0.0/14"
            "172.64.0.0/13"
            "131.0.72.0/22"
        )
        
        # IPv6 addresses
        local CF_IPV6=(
            "2400:cb00::/32"
            "2606:4700::/32"
            "2803:f800::/32"
            "2405:b500::/32"
            "2405:8100::/32"
            "2a06:98c0::/29"
            "2c0f:f248::/32"
        )
        
        if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
            # Clear and re-add for nftables
            nft flush set inet $NFT_TABLE $NFT_SET_CF_V4
            nft flush set inet $NFT_TABLE $NFT_SET_CF_V6
            
            local v4_elements
            local v6_elements
            v4_elements=$(IFS=,; echo "${CF_IPV4[*]}")
            v6_elements=$(IFS=,; echo "${CF_IPV6[*]}")
            
            nft add element inet $NFT_TABLE $NFT_SET_CF_V4 "{ $v4_elements }"
            nft add element inet $NFT_TABLE $NFT_SET_CF_V6 "{ $v6_elements }"
        else
            # Clear and re-add for ipset
            ipset flush $IPSET_CF_V4
            ipset flush $IPSET_CF_V6
            
            for ip in "${CF_IPV4[@]}"; do
                ipset add $IPSET_CF_V4 "$ip" -exist
            done
            
            for ip in "${CF_IPV6[@]}"; do
                ipset add $IPSET_CF_V6 "$ip" -exist
            done
        fi
    fi
}

# Setup iptables rules for all ports
setup_all_iptables_rules() {
    echo -e "${GREEN}Setting up iptables rules...${NC}"
    
    local ports
    mapfile -t ports < <(get_configured_ports)
    
    if [[ ${#ports[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Warning: No ports configured${NC}"
        return
    fi
    
    for port in "${ports[@]}"; do
        setup_iptables_port_rules "$port"
    done
    
    echo -e "${GREEN}All iptables rules configured${NC}"
}

# Setup iptables rules for a single port
setup_iptables_port_rules() {
    local port=$1
    local chain_name="${CHAIN_PREFIX}${port}"
    local proto="tcp"
    
    echo -e "${BLUE}  Configuring port $port (iptables)...${NC}"
    
    # Create custom chain if it doesn't exist
    iptables -N "$chain_name" 2>/dev/null || true
    ip6tables -N "$chain_name" 2>/dev/null || true
    
    # Flush custom chain
    iptables -F "$chain_name"
    ip6tables -F "$chain_name"
    
    # IPv4 rules
    iptables -A "$chain_name" -m set --match-set $IPSET_CF_V4 src -j ACCEPT
    iptables -A "$chain_name" -m set --match-set $IPSET_DEBUG_V4 src -j ACCEPT
    
    # Check if logging is enabled
    if grep -q "LOG_REJECTED=true" "$CONFIG_FILE" 2>/dev/null; then
        iptables -A "$chain_name" -m limit --limit 1/min -j LOG --log-prefix "CF-Blocked-$port: " --log-level 4
    fi
    iptables -A "$chain_name" -j DROP
    
    # IPv6 rules
    ip6tables -A "$chain_name" -m set --match-set $IPSET_CF_V6 src -j ACCEPT
    ip6tables -A "$chain_name" -m set --match-set $IPSET_DEBUG_V6 src -j ACCEPT
    
    if grep -q "LOG_REJECTED=true" "$CONFIG_FILE" 2>/dev/null; then
        ip6tables -A "$chain_name" -m limit --limit 1/min -j LOG --log-prefix "CF6-Blocked-$port: " --log-level 4
    fi
    ip6tables -A "$chain_name" -j DROP
    
    # Remove old INPUT rules if they exist
    iptables -D INPUT -p $proto --dport "$port" -j "$chain_name" 2>/dev/null || true
    ip6tables -D INPUT -p $proto --dport "$port" -j "$chain_name" 2>/dev/null || true
    
    # Add new INPUT rules
    iptables -I INPUT -p $proto --dport "$port" -j "$chain_name"
    ip6tables -I INPUT -p $proto --dport "$port" -j "$chain_name"
}

# Setup nftables rules
setup_nftables_rules() {
    echo -e "${GREEN}Setting up nftables rules...${NC}"
    
    # Get ports
    local ports
    mapfile -t ports < <(get_configured_ports)
    
    if [[ ${#ports[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Warning: No ports configured${NC}"
        return
    fi
    
    # Ensure table and sets exist
    if ! nft list table inet $NFT_TABLE &>/dev/null; then
        echo -e "${YELLOW}Table doesn't exist, creating...${NC}"
        create_nft_sets
    fi
    
    # Update ports set
    local port_elements
    port_elements=$(IFS=,; echo "${ports[*]}")
    nft flush set inet $NFT_TABLE $NFT_SET_PORTS 2>/dev/null || true
    nft add element inet $NFT_TABLE $NFT_SET_PORTS "{ $port_elements }"
    echo -e "  ${GREEN}✓${NC} Added ports to set: ${ports[*]}"
    
    # Create base chain if it doesn't exist
    nft add chain inet $NFT_TABLE input '{ type filter hook input priority 0; }' 2>/dev/null || true
    
    # Flush existing rules in our chain
    nft flush chain inet $NFT_TABLE input 2>/dev/null || true
    
    # Add rules
    local log_option=""
    if grep -q "LOG_REJECTED=true" "$CONFIG_FILE" 2>/dev/null; then
        log_option="log prefix \"CF-Blocked: \" limit rate 1/minute"
    fi
    
    # Create the ruleset with proper variable substitution
    cat > /tmp/nft_rules_$$.txt << NFTEOF
table inet $NFT_TABLE {
    chain input {
        type filter hook input priority 0;
        
        # Allow Cloudflare IPs to protected ports
        tcp dport @${NFT_SET_PORTS} ip saddr @${NFT_SET_CF_V4} accept
        tcp dport @${NFT_SET_PORTS} ip6 saddr @${NFT_SET_CF_V6} accept
        
        # Allow debug IPs to protected ports
        tcp dport @${NFT_SET_PORTS} ip saddr @${NFT_SET_DEBUG_V4} accept
        tcp dport @${NFT_SET_PORTS} ip6 saddr @${NFT_SET_DEBUG_V6} accept
        
        # Log and drop other connections to protected ports
        tcp dport @${NFT_SET_PORTS} ${log_option} drop
    }
}
NFTEOF
    
    # Apply the ruleset
    if nft -f /tmp/nft_rules_$$.txt 2>/dev/null; then
        echo -e "${GREEN}✓ nftables rules applied successfully${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to apply some rules, trying alternative method${NC}"
        
        # Alternative method: add rules directly
        nft add rule inet $NFT_TABLE input tcp dport @${NFT_SET_PORTS} ip saddr @${NFT_SET_CF_V4} accept
        nft add rule inet $NFT_TABLE input tcp dport @${NFT_SET_PORTS} ip6 saddr @${NFT_SET_CF_V6} accept
        nft add rule inet $NFT_TABLE input tcp dport @${NFT_SET_PORTS} ip saddr @${NFT_SET_DEBUG_V4} accept
        nft add rule inet $NFT_TABLE input tcp dport @${NFT_SET_PORTS} ip6 saddr @${NFT_SET_DEBUG_V6} accept
        
        if [[ -n "$log_option" ]]; then
            nft add rule inet $NFT_TABLE input tcp dport @${NFT_SET_PORTS} log prefix \"CF-Blocked: \" limit rate 1/minute drop
        else
            nft add rule inet $NFT_TABLE input tcp dport @${NFT_SET_PORTS} drop
        fi
    fi
    
    rm -f /tmp/nft_rules_$$.txt
    
    echo -e "${GREEN}nftables rules configured for ports: ${ports[*]}${NC}"
}

# Setup all firewall rules based on backend
setup_all_firewall_rules() {
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        setup_nftables_rules
    else
        setup_all_iptables_rules
    fi
}

# Add port
add_port() {
    local port=$1
    
    if [[ -z "$port" ]]; then
        echo -e "${RED}Error: Please provide a port number${NC}"
        echo "Usage: $0 add-port <port>"
        return 1
    fi
    
    # Validate port number
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        echo -e "${RED}Error: Invalid port number ($port)${NC}"
        return 1
    fi
    
    # Check if port already exists
    if grep -q "^$port$" "$PORTS_FILE" 2>/dev/null; then
        echo -e "${YELLOW}Port $port already exists${NC}"
        return 0
    fi
    
    # Add port to configuration file
    echo "$port" >> "$PORTS_FILE"
    
    # Apply rules immediately
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        # Add to nftables set
        nft add element inet $NFT_TABLE $NFT_SET_PORTS "{ $port }"
        setup_nftables_rules
    else
        setup_iptables_port_rules "$port"
    fi
    
    echo -e "${GREEN}Added port: $port${NC}"
}

# Remove port
remove_port() {
    local port=$1
    
    if [[ -z "$port" ]]; then
        echo -e "${RED}Error: Please provide a port number${NC}"
        echo "Usage: $0 remove-port <port>"
        return 1
    fi
    
    # Remove from configuration file
    sed -i "/^$port$/d" "$PORTS_FILE"
    
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        # Remove from nftables set
        nft delete element inet $NFT_TABLE $NFT_SET_PORTS "{ $port }" 2>/dev/null || true
        setup_nftables_rules
    else
        # Remove iptables rules
        local chain_name="${CHAIN_PREFIX}${port}"
        
        # Remove INPUT rules
        iptables -D INPUT -p tcp --dport "$port" -j "$chain_name" 2>/dev/null || true
        ip6tables -D INPUT -p tcp --dport "$port" -j "$chain_name" 2>/dev/null || true
        
        # Remove custom chain
        iptables -F "$chain_name" 2>/dev/null || true
        iptables -X "$chain_name" 2>/dev/null || true
        ip6tables -F "$chain_name" 2>/dev/null || true
        ip6tables -X "$chain_name" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}Removed port: $port${NC}"
}

# Add debug IP
add_debug_ip() {
    local ip=$1
    
    if [[ -z "$ip" ]]; then
        echo -e "${RED}Error: Please provide an IP address${NC}"
        echo "Usage: $0 add-ip <IP/CIDR>"
        return 1
    fi
    
    # Save to file
    echo "$ip" >> "$DEBUG_IPS_FILE"
    sort -u "$DEBUG_IPS_FILE" -o "$DEBUG_IPS_FILE"
    
    # Determine if IPv4 or IPv6
    if [[ "$ip" =~ : ]]; then
        # IPv6
        if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
            nft add element inet $NFT_TABLE $NFT_SET_DEBUG_V6 "{ $ip }"
        else
            ipset add $IPSET_DEBUG_V6 "$ip" -exist
        fi
        echo -e "${GREEN}Added debug IPv6: $ip${NC}"
    else
        # IPv4
        if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
            nft add element inet $NFT_TABLE $NFT_SET_DEBUG_V4 "{ $ip }"
        else
            ipset add $IPSET_DEBUG_V4 "$ip" -exist
        fi
        echo -e "${GREEN}Added debug IPv4: $ip${NC}"
    fi
}

# Remove debug IP
remove_debug_ip() {
    local ip=$1
    
    if [[ -z "$ip" ]]; then
        echo -e "${RED}Error: Please provide an IP address${NC}"
        echo "Usage: $0 remove-ip <IP/CIDR>"
        return 1
    fi
    
    # Remove from configuration file
    sed -i "\|^$ip$|d" "$DEBUG_IPS_FILE"
    
    # Determine if IPv4 or IPv6
    if [[ "$ip" =~ : ]]; then
        # IPv6
        if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
            nft delete element inet $NFT_TABLE $NFT_SET_DEBUG_V6 "{ $ip }" 2>/dev/null || true
        else
            ipset del $IPSET_DEBUG_V6 "$ip" 2>/dev/null || true
        fi
        echo -e "${GREEN}Removed debug IPv6: $ip${NC}"
    else
        # IPv4
        if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
            nft delete element inet $NFT_TABLE $NFT_SET_DEBUG_V4 "{ $ip }" 2>/dev/null || true
        else
            ipset del $IPSET_DEBUG_V4 "$ip" 2>/dev/null || true
        fi
        echo -e "${GREEN}Removed debug IPv4: $ip${NC}"
    fi
}

# List all IPs
list_ips() {
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        echo -e "${GREEN}=== Cloudflare IPv4 ===${NC}"
        local cf_v4
        cf_v4=$(nft list set inet $NFT_TABLE $NFT_SET_CF_V4 2>/dev/null | sed -n '/elements = {/,/}/p' | sed 's/elements = {//;s/}//;s/^[ \t]*//')
        if [[ -n "$cf_v4" && "$cf_v4" != *"elements = { }"* ]]; then
            echo "$cf_v4"
        else
            echo "  (empty)"
        fi
        
        echo -e "${GREEN}=== Cloudflare IPv6 ===${NC}"
        local cf_v6
        cf_v6=$(nft list set inet $NFT_TABLE $NFT_SET_CF_V6 2>/dev/null | sed -n '/elements = {/,/}/p' | sed 's/elements = {//;s/}//;s/^[ \t]*//')
        if [[ -n "$cf_v6" && "$cf_v6" != *"elements = { }"* ]]; then
            echo "$cf_v6"
        else
            echo "  (empty)"
        fi
        
        echo -e "${YELLOW}=== Debug IPv4 ===${NC}"
        local debug_v4
        debug_v4=$(nft list set inet $NFT_TABLE $NFT_SET_DEBUG_V4 2>/dev/null | sed -n '/elements = {/,/}/p' | sed 's/elements = {//;s/}//;s/^[ \t]*//')
        if [[ -n "$debug_v4" && "$debug_v4" != *"elements = { }"* ]]; then
            echo "$debug_v4"
        else
            echo "  (empty)"
        fi
        
        echo -e "${YELLOW}=== Debug IPv6 ===${NC}"
        local debug_v6
        debug_v6=$(nft list set inet $NFT_TABLE $NFT_SET_DEBUG_V6 2>/dev/null | sed -n '/elements = {/,/}/p' | sed 's/elements = {//;s/}//;s/^[ \t]*//')
        if [[ -n "$debug_v6" && "$debug_v6" != *"elements = { }"* ]]; then
            echo "$debug_v6"
        else
            echo "  (empty)"
        fi
    else
        echo -e "${GREEN}=== Cloudflare IPv4 ===${NC}"
        ipset list $IPSET_CF_V4 | grep -E '^[0-9]' | head -10 || echo "  (empty)"
        if [[ $(ipset list $IPSET_CF_V4 | grep -c '^[0-9]' || echo 0) -gt 10 ]]; then
            echo "  ..."
        fi
        
        echo -e "${GREEN}=== Cloudflare IPv6 ===${NC}"
        ipset list $IPSET_CF_V6 | grep -E '^[0-9a-f:]' | head -5 || echo "  (empty)"
        if [[ $(ipset list $IPSET_CF_V6 | grep -c '^[0-9a-f:]' || echo 0) -gt 5 ]]; then
            echo "  ..."
        fi
        
        echo -e "${YELLOW}=== Debug IPv4 ===${NC}"
        ipset list $IPSET_DEBUG_V4 | grep -E '^[0-9]' || echo "  (empty)"
        
        echo -e "${YELLOW}=== Debug IPv6 ===${NC}"
        ipset list $IPSET_DEBUG_V6 | grep -E '^[0-9a-f:]' || echo "  (empty)"
    fi
}

# List ports
list_ports() {
    echo -e "${GREEN}=== Protected Ports ===${NC}"
    local ports
    mapfile -t ports < <(get_configured_ports)
    
    if [[ ${#ports[@]} -eq 0 ]]; then
        echo "  (none)"
    else
        for port in "${ports[@]}"; do
            echo "  Port $port"
        done
    fi
    
    echo ""
    echo -e "${BLUE}Firewall Backend: $FIREWALL_BACKEND${NC}"
}

# Show status
show_status() {
    echo -e "${BLUE}=== Cloudflare Firewall Status ===${NC}"
    echo ""
    
    # Show firewall backend
    echo -e "${GREEN}Firewall Backend:${NC} $FIREWALL_BACKEND"
    echo ""
    
    # Show port status
    echo -e "${GREEN}Protected Ports:${NC}"
    local ports
    mapfile -t ports < <(get_configured_ports)
    for port in "${ports[@]}"; do
        echo "  Port $port: ${GREEN}active${NC}"
    done
    echo ""
    
    # Show IP statistics
    echo -e "${GREEN}IP Statistics:${NC}"
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        local cf_v4_count
        local cf_v6_count
        local debug_v4_count
        local debug_v6_count
        cf_v4_count=$(nft list set inet $NFT_TABLE $NFT_SET_CF_V4 2>/dev/null | grep -c "\. \. " || echo 0)
        cf_v6_count=$(nft list set inet $NFT_TABLE $NFT_SET_CF_V6 2>/dev/null | grep -c "\. \. " || echo 0)
        debug_v4_count=$(nft list set inet $NFT_TABLE $NFT_SET_DEBUG_V4 2>/dev/null | grep -c "\. \. " || echo 0)
        debug_v6_count=$(nft list set inet $NFT_TABLE $NFT_SET_DEBUG_V6 2>/dev/null | grep -c "\. \. " || echo 0)
    else
        local cf_v4_count
        local cf_v6_count
        local debug_v4_count
        local debug_v6_count
        cf_v4_count=$(ipset list $IPSET_CF_V4 2>/dev/null | grep -c '^[0-9]' || echo 0)
        cf_v6_count=$(ipset list $IPSET_CF_V6 2>/dev/null | grep -c '^[0-9a-f:]' || echo 0)
        debug_v4_count=$(ipset list $IPSET_DEBUG_V4 2>/dev/null | grep -c '^[0-9]' || echo 0)
        debug_v6_count=$(ipset list $IPSET_DEBUG_V6 2>/dev/null | grep -c '^[0-9a-f:]' || echo 0)
    fi
    
    echo "  Cloudflare IPv4: $cf_v4_count ranges"
    echo "  Cloudflare IPv6: $cf_v6_count ranges"
    echo "  Debug IPv4: $debug_v4_count addresses"
    echo "  Debug IPv6: $debug_v6_count addresses"
    echo ""
    
    # Show last update time
    if [[ -f "$CONFIG_DIR/cloudflare_ipv4.txt" ]]; then
        echo -e "${GREEN}Last Update:${NC}"
        echo "  $(stat -c %y "$CONFIG_DIR/cloudflare_ipv4.txt" | cut -d' ' -f1,2)"
    fi
}

# Clear debug IPs
clear_debug_ips() {
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        nft flush set inet $NFT_TABLE $NFT_SET_DEBUG_V4 2>/dev/null || true
        nft flush set inet $NFT_TABLE $NFT_SET_DEBUG_V6 2>/dev/null || true
    else
        ipset flush $IPSET_DEBUG_V4
        ipset flush $IPSET_DEBUG_V6
    fi
    true > "$DEBUG_IPS_FILE"
    echo -e "${GREEN}Cleared all debug IPs${NC}"
}

# Reload debug IPs
reload_debug_ips() {
    echo -e "${GREEN}Reloading debug IPs...${NC}"
    
    # Clear existing debug IPs
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        nft flush set inet $NFT_TABLE $NFT_SET_DEBUG_V4 2>/dev/null || true
        nft flush set inet $NFT_TABLE $NFT_SET_DEBUG_V6 2>/dev/null || true
    else
        ipset flush $IPSET_DEBUG_V4
        ipset flush $IPSET_DEBUG_V6
    fi
    
    # Reload from file
    if [[ -f "$DEBUG_IPS_FILE" ]]; then
        while IFS= read -r ip; do
            if [[ -n "$ip" && ! "$ip" =~ ^# ]]; then
                if [[ "$ip" =~ : ]]; then
                    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
                        nft add element inet $NFT_TABLE $NFT_SET_DEBUG_V6 "{ $ip }" 2>/dev/null || true
                    else
                        ipset add $IPSET_DEBUG_V6 "$ip" -exist
                    fi
                else
                    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
                        nft add element inet $NFT_TABLE $NFT_SET_DEBUG_V4 "{ $ip }" 2>/dev/null || true
                    else
                        ipset add $IPSET_DEBUG_V4 "$ip" -exist
                    fi
                fi
            fi
        done < "$DEBUG_IPS_FILE"
    fi
}

# Save rules
save_rules() {
    echo -e "${GREEN}Saving firewall rules...${NC}"
    
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        # Save nftables rules
        nft list table inet $NFT_TABLE > "$CONFIG_DIR/nftables.rules"
    else
        # Save ipset
        ipset save > "$CONFIG_DIR/ipset.rules"
        
        # Save iptables rules
        if command -v iptables-save &> /dev/null; then
            iptables-save > "$CONFIG_DIR/iptables.rules"
            ip6tables-save > "$CONFIG_DIR/ip6tables.rules"
        fi
    fi
    
    # Create systemd service
    create_systemd_service
    
    echo -e "${GREEN}Rules saved${NC}"
}

# Create systemd service
create_systemd_service() {
    cat > /etc/systemd/system/cloudflare-firewall.service << EOF
[Unit]
Description=Cloudflare Firewall Rules
After=network.target
Before=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$(realpath "$0") start
ExecStop=$(realpath "$0") stop
ExecReload=$(realpath "$0") reload

[Install]
WantedBy=multi-user.target
EOF

    # Copy script to system directory if not already there
    if [[ "$(realpath "$0")" != "/usr/local/bin/cf-firewall" ]]; then
        cp "$0" /usr/local/bin/cf-firewall
        chmod +x /usr/local/bin/cf-firewall
    fi
    
    # Reload and enable service
    systemctl daemon-reload
    systemctl enable cloudflare-firewall.service
}

# Start service
start_service() {
    echo -e "${GREEN}Starting Cloudflare Firewall...${NC}"
    
    init_config_dir
    detect_firewall_backend
    
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        create_nft_sets
    else
        create_ipsets
    fi
    
    reload_debug_ips
    update_cloudflare_ips
    setup_all_firewall_rules
    
    echo -e "${GREEN}Cloudflare Firewall started (backend: $FIREWALL_BACKEND)${NC}"
}

# Stop service
stop_service() {
    echo -e "${YELLOW}Stopping Cloudflare Firewall...${NC}"
    
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        # Remove nftables table
        nft delete table inet $NFT_TABLE 2>/dev/null || true
    else
        local ports
        mapfile -t ports < <(get_configured_ports)
        
        for port in "${ports[@]}"; do
            local chain_name="${CHAIN_PREFIX}${port}"
            
            # Remove INPUT rules
            iptables -D INPUT -p tcp --dport "$port" -j "$chain_name" 2>/dev/null || true
            ip6tables -D INPUT -p tcp --dport "$port" -j "$chain_name" 2>/dev/null || true
            
            # Remove custom chain
            iptables -F "$chain_name" 2>/dev/null || true
            iptables -X "$chain_name" 2>/dev/null || true
            ip6tables -F "$chain_name" 2>/dev/null || true
            ip6tables -X "$chain_name" 2>/dev/null || true
        done
    fi
    
    echo -e "${GREEN}Cloudflare Firewall stopped${NC}"
}

# Reload service
reload_service() {
    echo -e "${GREEN}Reloading Cloudflare Firewall...${NC}"
    
    detect_firewall_backend
    reload_debug_ips
    setup_all_firewall_rules
    
    echo -e "${GREEN}Cloudflare Firewall reloaded${NC}"
}

# Switch firewall backend
switch_backend() {
    local new_backend=$1
    
    if [[ -z "$new_backend" ]]; then
        echo -e "${RED}Error: Please specify backend (iptables or nftables)${NC}"
        echo "Usage: $0 switch-backend <iptables|nftables>"
        return 1
    fi
    
    if [[ "$new_backend" != "iptables" && "$new_backend" != "nftables" ]]; then
        echo -e "${RED}Error: Invalid backend. Use 'iptables' or 'nftables'${NC}"
        return 1
    fi
    
    # Check if backend is available
    if [[ "$new_backend" == "nftables" ]]; then
        if ! command -v nft &> /dev/null; then
            echo -e "${RED}Error: nftables is not installed${NC}"
            return 1
        fi
    else
        if ! command -v iptables &> /dev/null; then
            echo -e "${RED}Error: iptables is not installed${NC}"
            return 1
        fi
        if ! command -v ipset &> /dev/null; then
            echo -e "${RED}Error: ipset is not installed (required for iptables mode)${NC}"
            return 1
        fi
    fi
    
    echo -e "${YELLOW}Switching from $FIREWALL_BACKEND to $new_backend...${NC}"
    
    # Stop current backend
    stop_service
    
    # Update configuration
    echo "$new_backend" > "$FIREWALL_MODE_FILE"
    FIREWALL_BACKEND="$new_backend"
    
    # Start with new backend
    start_service
    
    echo -e "${GREEN}Successfully switched to $new_backend${NC}"
}

# Show help
show_help() {
    cat << EOF
${BLUE}Cloudflare Firewall Management Tool${NC}
Version: 2.0.0 - Now with nftables support!

Usage: $0 <command> [args]

${GREEN}Basic Commands:${NC}
  init              Initialize firewall (first use)
  start             Start firewall service
  stop              Stop firewall service
  reload            Reload configuration
  status            Show firewall status
  
${GREEN}Port Management:${NC}
  add-port <port>    Add protected port
  remove-port <port> Remove protected port
  list-ports        List all protected ports
  
${GREEN}IP Management:${NC}
  add-ip <IP/CIDR>    Add debug IP
  remove-ip <IP/CIDR> Remove debug IP
  list-ips            List all IPs
  clear-ips           Clear all debug IPs
  update              Update Cloudflare IP list
  
${GREEN}System Commands:${NC}
  save              Save rules and create system service
  switch-backend    Switch between iptables and nftables
  help              Show this help message

${YELLOW}Examples:${NC}
  # Initialize (first use)
  $0 init
  
  # Add new port
  $0 add-port 8080
  
  # Add debug IPs
  $0 add-ip 192.168.1.100
  $0 add-ip 10.0.0.0/24
  
  # Switch to nftables (if available)
  $0 switch-backend nftables
  
  # View status
  $0 status

${BLUE}Current Configuration:${NC}
  Config Directory: $CONFIG_DIR
  Firewall Backend: $(cat $FIREWALL_MODE_FILE 2>/dev/null || echo "auto-detect")

EOF
}

# Initialize (first use)
init_firewall() {
    echo -e "${BLUE}=== Initializing Cloudflare Firewall ===${NC}"
    
    init_config_dir
    detect_firewall_backend
    
    if [[ "$FIREWALL_BACKEND" == "nftables" ]]; then
        echo -e "${GREEN}Using nftables (modern firewall)${NC}"
        create_nft_sets
    else
        echo -e "${GREEN}Using iptables + ipset (classic firewall)${NC}"
        create_ipsets
    fi
    
    update_cloudflare_ips
    reload_debug_ips
    setup_all_firewall_rules
    save_rules
    
    echo ""
    echo -e "${GREEN}Initialization complete!${NC}"
    echo -e "${YELLOW}Firewall Backend: $FIREWALL_BACKEND${NC}"
    echo -e "${YELLOW}Default protected ports: ${DEFAULT_PORTS[*]}${NC}"
    echo ""
    echo -e "Use ${BLUE}$0 add-port <port>${NC} to add more ports"
    echo -e "Use ${BLUE}$0 add-ip <IP>${NC} to add debug IPs"
    echo -e "Use ${BLUE}$0 status${NC} to view status"
    
    if [[ "$FIREWALL_BACKEND" == "iptables" ]] && command -v nft &> /dev/null; then
        echo ""
        echo -e "${YELLOW}Note: nftables is available on your system.${NC}"
        echo -e "Consider switching with: ${BLUE}$0 switch-backend nftables${NC}"
    fi
}

# Main function
main() {
    check_root
    
    # Load existing backend if configured
    if [[ -f "$FIREWALL_MODE_FILE" ]]; then
        FIREWALL_BACKEND=$(cat "$FIREWALL_MODE_FILE")
    fi
    
    case "$1" in
        init)
            init_firewall
            ;;
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        reload)
            reload_service
            ;;
        status)
            show_status
            ;;
        add-port)
            add_port "$2"
            ;;
        remove-port)
            remove_port "$2"
            ;;
        list-ports)
            list_ports
            ;;
        add-ip)
            add_debug_ip "$2"
            ;;
        remove-ip)
            remove_debug_ip "$2"
            ;;
        list-ips)
            list_ips
            ;;
        clear-ips)
            clear_debug_ips
            ;;
        update)
            update_cloudflare_ips
            ;;
        save)
            save_rules
            ;;
        switch-backend)
            switch_backend "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [[ -z "$1" ]]; then
                show_help
            else
                echo -e "${RED}Error: Unknown command '$1'${NC}"
                echo ""
                show_help
            fi
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
