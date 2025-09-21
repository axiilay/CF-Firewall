#!/bin/bash

# CF-Firewall Installation Script
# https://github.com/axiilay/cf-firewall

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
INSTALL_PATH="/usr/local/bin/cf-firewall"
GITHUB_RAW_URL="https://raw.githubusercontent.com/axiilay/cf-firewall/main/cf-firewall.sh"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

echo -e "${BLUE}CF-Firewall Installation Script${NC}"
echo "================================"
echo ""

# Check dependencies
echo -e "${GREEN}Checking dependencies...${NC}"

# Check for iptables
if ! command -v iptables &> /dev/null; then
    echo -e "${RED}Error: iptables is not installed${NC}"
    echo "Please install iptables first:"
    echo "  Ubuntu/Debian: apt-get install iptables"
    echo "  CentOS/RHEL: yum install iptables"
    exit 1
fi

# Check for ip6tables
if ! command -v ip6tables &> /dev/null; then
    echo -e "${YELLOW}Warning: ip6tables is not installed${NC}"
    echo "IPv6 support will be disabled"
fi

# Check firewall backend
echo -e "${GREEN}Detecting firewall backend...${NC}"

FIREWALL_BACKEND=""

# Check for nftables
if command -v nft &> /dev/null; then
    echo -e "${GREEN}✓ nftables is installed${NC}"
    if systemctl is-active --quiet nftables || nft list tables &> /dev/null; then
        FIREWALL_BACKEND="nftables"
        echo -e "${GREEN}  Using nftables (recommended)${NC}"
    fi
fi

# Check for iptables/ipset if nftables not active
if [[ -z "$FIREWALL_BACKEND" ]]; then
    if ! command -v iptables &> /dev/null; then
        echo -e "${RED}Error: Neither nftables nor iptables is installed${NC}"
        echo "Please install a firewall backend:"
        echo "  For modern systems: apt-get install nftables"
        echo "  For legacy systems: apt-get install iptables ipset"
        exit 1
    fi
    
    # Check for ipset (required for iptables mode)
    if ! command -v ipset &> /dev/null; then
        echo -e "${YELLOW}ipset is not installed (required for iptables mode)${NC}"
        echo "Installing ipset..."
        
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y ipset
        elif command -v yum &> /dev/null; then
            yum install -y ipset
        elif command -v dnf &> /dev/null; then
            dnf install -y ipset
        else
            echo -e "${RED}Could not install ipset automatically${NC}"
            echo "Please install ipset manually or use nftables"
            exit 1
        fi
    fi
    
    FIREWALL_BACKEND="iptables"
    echo -e "${GREEN}✓ Using iptables + ipset${NC}"
fi

echo -e "${GREEN}Firewall backend: $FIREWALL_BACKEND${NC}"

# Check for curl
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}curl is not installed, installing...${NC}"
    
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y curl
    elif command -v yum &> /dev/null; then
        yum install -y curl
    elif command -v dnf &> /dev/null; then
        dnf install -y curl
    fi
fi

# Check for systemd
if ! command -v systemctl &> /dev/null; then
    echo -e "${YELLOW}Warning: systemd is not available${NC}"
    echo "Service auto-start will not be configured"
fi

echo -e "${GREEN}All dependencies satisfied${NC}"
echo ""

# Download cf-firewall script
echo -e "${GREEN}Downloading cf-firewall...${NC}"

if [[ -f "cf-firewall.sh" ]]; then
    echo "Using local cf-firewall.sh file"
    cp cf-firewall.sh "$INSTALL_PATH"
else
    echo "Downloading from GitHub..."
    curl -sSL "$GITHUB_RAW_URL" -o "$INSTALL_PATH"
fi

# Make executable
chmod +x "$INSTALL_PATH"

echo -e "${GREEN}cf-firewall installed to $INSTALL_PATH${NC}"
echo ""

# Initialize firewall
read -p "Do you want to initialize the firewall now? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Initializing firewall...${NC}"
    $INSTALL_PATH init
    echo ""
    echo -e "${GREEN}Installation complete!${NC}"
    echo ""
    echo "Quick Start Guide:"
    echo "=================="
    echo ""
    echo "1. Add additional ports (optional):"
    echo "   cf-firewall add-port 8080"
    echo ""
    echo "2. Add debug IPs for development (optional):"
    echo "   cf-firewall add-ip 192.168.1.100"
    echo ""
    echo "3. View firewall status:"
    echo "   cf-firewall status"
    echo ""
    echo "4. Update Cloudflare IPs:"
    echo "   cf-firewall update"
    echo ""
    echo "For more commands, run: cf-firewall help"
else
    echo -e "${YELLOW}Firewall not initialized${NC}"
    echo "Run 'cf-firewall init' when you're ready to start"
fi

echo ""
echo -e "${BLUE}Thank you for using CF-Firewall!${NC}"
echo "GitHub: https://github.com/axiilay/cf-firewall"
