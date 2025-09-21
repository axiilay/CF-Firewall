# Contributing to CF-Firewall

First off, thank you for considering contributing to CF-Firewall! It's people like you that make CF-Firewall such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title**
* **Describe the exact steps which reproduce the problem**
* **Provide specific examples to demonstrate the steps**
* **Describe the behavior you observed after following the steps**
* **Explain which behavior you expected to see instead and why**
* **Include your system information** (OS, iptables version, ipset version)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

* **Use a clear and descriptive title**
* **Provide a step-by-step description of the suggested enhancement**
* **Provide specific examples to demonstrate the steps**
* **Describe the current behavior and explain which behavior you expected to see instead**
* **Explain why this enhancement would be useful**

### Pull Requests

1. Fork the repo and create your branch from `main`
2. If you've added code that should be tested, add tests
3. Ensure your code follows the existing style
4. Make sure your code lints
5. Issue that pull request!

## Development Setup

1. Fork and clone the repository
2. Create a test environment (VM or container recommended)
3. Install dependencies:
   ```bash
   # Ubuntu/Debian
   sudo apt-get install iptables ipset curl
   
   # CentOS/RHEL
   sudo yum install iptables ipset curl
   ```

## Testing

### Manual Testing

Test your changes thoroughly:

```bash
# Initialize
sudo ./cf-firewall.sh init

# Test port management
sudo ./cf-firewall.sh add-port 8080
sudo ./cf-firewall.sh list-ports
sudo ./cf-firewall.sh remove-port 8080

# Test IP management
sudo ./cf-firewall.sh add-ip 192.168.1.100
sudo ./cf-firewall.sh list-ips
sudo ./cf-firewall.sh remove-ip 192.168.1.100

# Test service management
sudo ./cf-firewall.sh stop
sudo ./cf-firewall.sh start
sudo ./cf-firewall.sh status
```

### Testing Checklist

- [ ] Script runs without errors on fresh system
- [ ] All commands work as documented
- [ ] IPv4 rules work correctly
- [ ] IPv6 rules work correctly (if supported)
- [ ] Persistence works after reboot
- [ ] No existing firewall rules are disrupted

## Style Guide

### Shell Script Style

* Use 4 spaces for indentation (no tabs)
* Use `snake_case` for function and variable names
* Use UPPERCASE for constants
* Always quote variables: `"$var"` not `$var`
* Use `[[ ]]` for conditionals, not `[ ]`
* Add comments for complex logic
* Keep functions focused and small

### Commit Messages

* Use the present tense ("Add feature" not "Added feature")
* Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
* Limit the first line to 72 characters or less
* Reference issues and pull requests liberally after the first line

### Documentation

* Update README.md if you change functionality
* Add comments to explain complex code
* Update help text if you add/change commands

## Questions?

Feel free to open an issue with your question or contact the maintainers directly.

Thank you for contributing! 🎉
