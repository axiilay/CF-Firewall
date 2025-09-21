# Changelog

All notable changes to CF-Firewall will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2024-01-15

### Added
- **nftables support**: Full support for modern nftables backend
- **Auto-detection**: Automatically detects best firewall backend
- **Backend switching**: Switch between iptables and nftables on the fly
- Performance improvements with nftables (10-40% CPU reduction)
- Unified IPv4/IPv6 handling in nftables mode
- Atomic rule updates in nftables mode

### Changed
- Refactored core to support multiple firewall backends
- Improved error handling and logging
- Updated documentation with backend recommendations

### Fixed
- Better compatibility with modern Linux distributions
- Improved systemd service reliability

## [1.1.0] - 2024-01-10

### Added
- Multi-port support for protecting multiple services
- Debug IP management for development environments
- Automatic Cloudflare IP updates
- IPv6 support
- Systemd service integration
- Status monitoring and statistics
- Connection rejection logging

## [1.0.0] - 2024-01-01

### Added
- Initial release
- Basic firewall functionality for Cloudflare IPs
- Support for ports 80, 443, 8443 by default
- ipset integration for efficient IP matching
- Persistent rules across reboots
- Command-line interface
- Installation script
- Comprehensive documentation

### Security
- Implements strict DROP policy for non-Cloudflare IPs
- Supports both IPv4 and IPv6 filtering
- Rate-limited logging to prevent log flooding

[Unreleased]: https://github.com/axiilay/cf-firewall/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/axiilay/cf-firewall/releases/tag/v1.0.0
