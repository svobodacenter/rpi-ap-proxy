#!/bin/bash

# Exit on error
set -e

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

# Function to prompt for configuration values
get_config_values() {
    read -p "Enter WiFi SSID: " WIFI_SSID
    read -sp "Enter WiFi Password (minimum 8 characters): " WIFI_PASS
    echo
    
    read -p "Do you want to use SOCKS5 proxy or Xray config? (s/x): " USE_OWN_PROXY
    if [[ "$USE_OWN_PROXY" =~ ^[Ss]$ ]]; then
        read -p "Enter SOCKS5 proxy host: " PROXY_HOST
        read -p "Enter SOCKS5 proxy port: " PROXY_PORT
        read -p "Do you want to use authentication? (y/N): " USE_AUTH
        if [[ "$USE_AUTH" =~ ^[Yy]$ ]]; then
            read -p "Enter username: " PROXY_USER
            read -sp "Enter password: " PROXY_PASS
            echo
        fi
        USE_XRAY=false
    else
        PROXY_HOST="127.0.0.1"
        PROXY_PORT="1080"
        USE_XRAY=true
    fi

    read -p "Do you want to install DNSCrypt-proxy for encrypted DNS? (y/N): " USE_DNSCRYPT
    USE_DNSCRYPT=$(echo "$USE_DNSCRYPT" | grep -i "^y" > /dev/null && echo "true" || echo "false")
}

# Function to install required packages
install_packages() {
    echo "Installing required packages..."
    apt-get update
    apt-get install -y hostapd dnsmasq iptables-persistent redsocks
}

# Function to configure hostapd
configure_hostapd() {
    echo "Configuring hostapd..."
    cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=$WIFI_SSID
wpa_passphrase=$WIFI_PASS
hw_mode=g
channel=6
ieee80211n=1
wpa=2
EOF

    # Enable and start hostapd
    systemctl enable hostapd
    systemctl start hostapd
}

# Function to configure dnsmasq
configure_dnsmasq() {
    echo "Configuring dnsmasq..."
    # Backup original configuration
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
    
    cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.50.10,192.168.50.100,12h
EOF

    # If DNSCrypt is enabled, add the server line
    if [ "$USE_DNSCRYPT" = true ]; then
        echo "server=127.0.0.1#53535" >> /etc/dnsmasq.conf
    fi
}

# Function to configure static IP
configure_static_ip() {
    echo "Configuring static IP for wlan0..."
    cat > /etc/systemd/network/10-wlan0-static-ip.network <<EOF
[Match]
Name=wlan0

[Network]
Address=192.168.50.1/24
EOF

    cat > /etc/systemd/network/10-wlan0-static.link <<EOF
[Match]
OriginalName=wlan0

[Link]
RequiredForOnline=yes
EOF

    # Check if NetworkManager is running and configure it to ignore wlan0
    if systemctl is-active --quiet NetworkManager; then
        echo "NetworkManager is running. Configuring it to ignore wlan0..."
        mkdir -p /etc/NetworkManager/conf.d
        cat > /etc/NetworkManager/conf.d/80-ignore-wlan0.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
    fi

    systemctl enable systemd-networkd
    systemctl restart systemd-networkd
}

# Function to configure redsocks
configure_redsocks() {
    echo "Configuring redsocks..."
    config="
base {
    log_debug = off;
    log_info = on;
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 192.168.50.1;
    local_port = 12345;
    ip = $PROXY_HOST;
    port = $PROXY_PORT;
    type = socks5;
"

    if [[ "$USE_AUTH" =~ ^[Yy]$ ]]; then
        config+="    login = \"$PROXY_USER\";"
        config+="    password = \"$PROXY_PASS\";"
    fi

    config+="}"

    echo "$config" > /etc/redsocks.conf
    # Configure redsocks to wait for network
    sed -i 's/After=network.target/After=network-online.target systemd-networkd-wait-online.service/' /lib/systemd/system/redsocks.service
    systemctl daemon-reload
}

# Function to configure iptables
configure_iptables() {
    echo "Configuring iptables rules..."
    # Create new chain for REDSOCKS
    iptables -t nat -N REDSOCKS
    iptables -t nat -A PREROUTING -i wlan0 -p tcp -j REDSOCKS
    iptables -t nat -A REDSOCKS -p tcp -j DNAT --to-destination 192.168.50.1:12345
    
    # Save iptables rules
    netfilter-persistent save
}

# Function to install and configure xray
install_xray() {
    echo "Installing xray..."
    useradd -M -r -s /usr/sbin/nologin xray || true
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u xray

    echo "Configuring xray..."
    cat > /usr/local/etc/xray/config.json <<EOF
{
    "inbounds": [
        {
            "tag": "socks-in",
            "listen": "127.0.0.1",
            "port": $PROXY_PORT,
            "protocol": "socks",
            "settings": {
                "auth": "noauth",
                "udp": true
            }
        }
    ],
    "outbounds": [
        // add your outbounds here
        {
            "protocol": "freedom",
            "tag": "direct"
        }
    ]
}
EOF

    systemctl enable xray
    systemctl restart xray
}

# Function to install and configure DNSCrypt
install_dnscrypt() {
    echo "Installing DNSCrypt-proxy..."
    
    # Check if install-dnscrypt-rpi.sh exists
    if [ ! -f "install-dnscrypt-rpi.sh" ]; then
        wget https://raw.githubusercontent.com/svobodacenter/rpi-ap-proxy/master/install-dnscrypt-rpi.sh
    fi
    
    chmod +x install-dnscrypt-rpi.sh
    ./install-dnscrypt-rpi.sh

    # Configure resolv.conf
    cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
EOF

    # If NetworkManager is running, configure it to not manage DNS
    if systemctl is-active --quiet NetworkManager; then
        mkdir -p /etc/NetworkManager/conf.d
        cat > /etc/NetworkManager/conf.d/90-dns-none.conf <<EOF
[main]
dns=none
EOF
    fi
    
    echo "DNSCrypt-proxy installation complete."
}

# Function to verify setup
verify_setup() {
    echo "Verifying setup..."
    echo "1. Checking services status..."
    systemctl status hostapd --no-pager
    systemctl status dnsmasq --no-pager
    systemctl status redsocks --no-pager
    if [ "$USE_XRAY" = true ]; then
        systemctl status xray --no-pager
    fi
    if [ "$USE_DNSCRYPT" = true ]; then
        systemctl status dnscrypt-proxy --no-pager
    fi

    echo "2. Checking network interface..."
    ip addr show wlan0

    echo "3. Checking iptables rules..."
    iptables -t nat -L REDSOCKS

    if [ "$USE_DNSCRYPT" = true ]; then
        echo "4. Testing DNSCrypt-proxy..."
        dig +short @127.0.0.1 cloudflare.com
    fi

    echo "Setup verification complete."
}

# Main script execution
main() {
    check_root
    get_config_values
    install_packages
    configure_hostapd
    configure_dnsmasq
    configure_static_ip
    configure_redsocks
    configure_iptables
    
    if [ "$USE_XRAY" = true ]; then
        install_xray
    fi
    
    if [ "$USE_DNSCRYPT" = true ]; then
        install_dnscrypt
    fi
    
    # Restart services
    systemctl restart hostapd
    systemctl restart dnsmasq
    systemctl restart redsocks
    if [ "$USE_XRAY" = true ]; then
        systemctl restart xray
    fi
    if [ "$USE_DNSCRYPT" = true ]; then
        systemctl restart dnscrypt-proxy
    fi
    
    verify_setup
    
    echo "Setup complete! Your Raspberry Pi is now configured as a WiFi access point with SOCKS5 proxy."
    if [ "$USE_XRAY" = true ]; then
        echo "1. Add your outbounds to the xray config file: /usr/local/etc/xray/config.json (or put your own config there with the socks inbound)"
        echo "2. Restart xray: systemctl restart xray"
    else
        echo "Using external SOCKS5 proxy: $SOCKS5_PROXY"
    fi
    if [ "$USE_DNSCRYPT" = true ]; then
        echo "DNSCrypt-proxy is configured and running on 127.0.0.1:53535"
        echo "DNS queries are being encrypted and authenticated"
    fi
    echo "SSID: $WIFI_SSID"
    echo "IP Address: 192.168.50.1"
    echo "DHCP Range: 192.168.50.10 - 192.168.50.100"
}

# Run main function
main 