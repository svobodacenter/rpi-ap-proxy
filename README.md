# Raspberry Pi Access Point Proxy

This project transforms a Raspberry Pi into a WiFi access point with proxy capabilities, allowing connected devices to route their traffic through a SOCKS5 proxy or Xray configuration. It includes optional DNSCrypt-proxy support for encrypted DNS queries.

## Features

- WiFi Access Point setup using hostapd
- DHCP server configuration using dnsmasq
- SOCKS5 proxy support with optional authentication
- Xray configuration support
- Optional DNSCrypt-proxy integration for encrypted DNS
- Network traffic redirection using redsocks

## Prerequisites

- Raspberry Pi
- Debian-based Linux distribution (Raspberry Pi OS recommended)
- Root access
- Internet connection for package installation

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/rpi-ap-proxy.git
   cd rpi-ap-proxy
   ```

2. Make the installation scripts executable:
   ```bash
   chmod +x install.sh install-dnscrypt-rpi.sh
   ```

3. Run the installation script as root:
   ```bash
   sudo ./install.sh
   ```

4. Follow the interactive prompts to configure:
   - WiFi SSID and password
   - Proxy type (SOCKS5 or Xray)
   - Proxy server details (if using SOCKS5)
   - DNSCrypt-proxy installation option


## Troubleshooting

If you encounter issues:

1. Check the redsocks logs:
```bash
sudo journalctl -u redsocks
```
If there is no connections log, it means that it is not redirecting traffic. Try restarting it:
```bash
sudo systemctl restart redsocks
```

2. Verify iptables rules:
```bash
sudo iptables -t nat -L
```
It should have `Chain REDSOCKS` with `target` `DNAT` and `destination` `anywhere` to:192.168.50.1:12345.

3. Ensure the Wi-Fi interface is up and has an IP address:
```bash
sudo ip addr show wlan0
```
It should have `state UP` and an `inet 192.168.50.1/24 scope global wlan0` entry.

```bash
sudo systemctl restart hostapd
```


4. Check xray logs:
```bash
sudo journalctl -u xray
```
Set `log_level` to `debug` in the `config.json` file to get more detailed logs.

5. Check DHCP leases:
```bash
cat /var/lib/misc/dnsmasq.leases
```

## Contributing

Feel free to submit issues!

## License

This project is licensed under the MIT License - see the LICENSE file for details. 