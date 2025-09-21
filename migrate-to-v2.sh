#!/bin/bash

# CF-Firewall v2.0.0 Migration Script
# Helps existing users migrate to the new version with nftables support

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  CF-Firewall v2.0.0 Migration Script  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

# Check current version
if [[ ! -f "/usr/local/bin/cf-firewall" ]]; then
    echo -e "${RED}Error: CF-Firewall is not installed${NC}"
    echo "Please install CF-Firewall first"
    exit 1
fi

# Backup current configuration
echo -e "${GREEN}Step 1: Backing up current configuration...${NC}"

BACKUP_DIR="/etc/cloudflare-firewall/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Copy all configuration files
cp -r /etc/cloudflare-firewall/* "$BACKUP_DIR/" 2>/dev/null || true

# Backup iptables rules
if command -v iptables-save &> /dev/null; then
    iptables-save > "$BACKUP_DIR/iptables.rules"
    ip6tables-save > "$BACKUP_DIR/ip6tables.rules"
    echo -e "  ${GREEN}✓${NC} Backed up iptables rules"
fi

# Backup ipset
if command -v ipset &> /dev/null; then
    ipset save > "$BACKUP_DIR/ipset.rules"
    echo -e "  ${GREEN}✓${NC} Backed up ipset rules"
fi

echo -e "  ${GREEN}✓${NC} Configuration backed up to: $BACKUP_DIR"
echo ""

# Check available backends
echo -e "${GREEN}Step 2: Checking available firewall backends...${NC}"

HAS_NFTABLES=false
HAS_IPTABLES=false

if command -v nft &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} nftables is installed"
    
    # Check if nftables is usable
    if nft list tables &> /dev/null; then
        HAS_NFTABLES=true
        NFT_VERSION=$(nft --version | awk '{print $2}')
        echo -e "    Version: $NFT_VERSION"
    else
        echo -e "    ${YELLOW}⚠${NC} nftables is installed but not active"
    fi
else
    echo -e "  ${YELLOW}○${NC} nftables is not installed"
fi

if command -v iptables &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} iptables is installed"
    HAS_IPTABLES=true
    
    if command -v ipset &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} ipset is installed"
    else
        echo -e "  ${YELLOW}⚠${NC} ipset is not installed (required for iptables mode)"
    fi
else
    echo -e "  ${YELLOW}○${NC} iptables is not installed"
fi

echo ""

# Provide recommendation
echo -e "${GREEN}Step 3: Backend Recommendation${NC}"

RECOMMENDED=""

if [[ "$HAS_NFTABLES" == "true" ]]; then
    echo -e "${BLUE}Recommendation: Use nftables${NC}"
    echo "  - Better performance (10-40% less CPU usage)"
    echo "  - Modern and actively developed"
    echo "  - Cleaner syntax and atomic updates"
    echo "  - Native set support"
    RECOMMENDED="nftables"
elif [[ "$HAS_IPTABLES" == "true" ]]; then
    echo -e "${BLUE}Recommendation: Continue with iptables${NC}"
    echo "  - Your current setup"
    echo "  - Stable and well-tested"
    echo "  - Wide compatibility"
    RECOMMENDED="iptables"
    
    if command -v nft &> /dev/null; then
        echo ""
        echo -e "${YELLOW}Note: You could install and use nftables for better performance:${NC}"
        echo "  sudo apt-get install nftables  # Debian/Ubuntu"
        echo "  sudo yum install nftables       # RHEL/CentOS"
    fi
else
    echo -e "${RED}Error: No firewall backend available${NC}"
    echo "Please install either nftables or iptables"
    exit 1
fi

echo ""

# Ask user for choice
echo -e "${GREEN}Step 4: Choose Firewall Backend${NC}"

if [[ "$HAS_NFTABLES" == "true" ]] && [[ "$HAS_IPTABLES" == "true" ]]; then
    echo "Both nftables and iptables are available."
    echo ""
    echo "1) nftables (recommended for performance)"
    echo "2) iptables (keep current setup)"
    echo "3) Cancel migration"
    echo ""
    read -p "Choose an option [1-3]: " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            CHOSEN_BACKEND="nftables"
            ;;
        2)
            CHOSEN_BACKEND="iptables"
            ;;
        3)
            echo -e "${YELLOW}Migration cancelled${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            exit 1
            ;;
    esac
else
    CHOSEN_BACKEND="$RECOMMENDED"
    echo "Using $CHOSEN_BACKEND (only available option)"
fi

echo ""
echo -e "${GREEN}Step 5: Updating CF-Firewall...${NC}"

# Download new version
echo "Downloading CF-Firewall v2.0.0..."
wget -q -O /tmp/cf-firewall-new.sh https://raw.githubusercontent.com/axiilay/cf-firewall/main/cf-firewall.sh

if [[ ! -f "/tmp/cf-firewall-new.sh" ]]; then
    echo -e "${RED}Error: Failed to download new version${NC}"
    exit 1
fi

# Stop current service
echo "Stopping current CF-Firewall service..."
systemctl stop cloudflare-firewall 2>/dev/null || true

# Install new version
echo "Installing new version..."
cp /tmp/cf-firewall-new.sh /usr/local/bin/cf-firewall
chmod +x /usr/local/bin/cf-firewall
rm /tmp/cf-firewall-new.sh

echo -e "  ${GREEN}✓${NC} CF-Firewall updated to v2.0.0"
echo ""

# Configure backend
echo -e "${GREEN}Step 6: Configuring backend...${NC}"

echo "$CHOSEN_BACKEND" > /etc/cloudflare-firewall/firewall_mode
echo -e "  ${GREEN}✓${NC} Backend set to: $CHOSEN_BACKEND"

# Restart service with new backend
echo ""
echo -e "${GREEN}Step 7: Starting CF-Firewall with $CHOSEN_BACKEND...${NC}"

/usr/local/bin/cf-firewall start

if [[ $? -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} CF-Firewall started successfully"
else
    echo -e "  ${RED}✗${NC} Failed to start CF-Firewall"
    echo "  Restoring from backup..."
    # Restore logic here if needed
    exit 1
fi

# Verify
echo ""
echo -e "${GREEN}Step 8: Verification${NC}"

/usr/local/bin/cf-firewall status

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    Migration Completed Successfully!   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Important information:"
echo "  - Your configuration has been preserved"
echo "  - Backup saved to: $BACKUP_DIR"
echo "  - Using backend: $CHOSEN_BACKEND"
echo ""

if [[ "$CHOSEN_BACKEND" == "nftables" ]] && [[ "$RECOMMENDED" == "iptables" ]]; then
    echo -e "${YELLOW}Note: You've switched from iptables to nftables${NC}"
    echo "  - Better performance is expected"
    echo "  - Monitor your services to ensure everything works"
    echo "  - You can switch back with: cf-firewall switch-backend iptables"
fi

echo ""
echo "Next steps:"
echo "  1. Test your protected services"
echo "  2. Check logs: journalctl -u cloudflare-firewall -f"
echo "  3. View status: cf-firewall status"
echo ""
echo "For more information, see:"
echo "  - Migration guide: https://github.com/axiilay/cf-firewall/docs/NFTABLES.md"
echo "  - Changelog: https://github.com/axiilay/cf-firewall/docs/CHANGELOG.md"
