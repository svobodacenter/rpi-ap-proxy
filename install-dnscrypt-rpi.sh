#!/bin/bash

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

if [ "$(uname -m)" = "aarch64" ]; then
    ARCH="arm64"
elif [ "$(uname -m)" = "x86_64" ]; then
    ARCH="x86_64"
else
    ARCH="arm"
fi

DNS_BLACKLIST_URL="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.plus-onlydomains.txt"
DNSCRYPT_PROXY_CONF="/etc/dnscrypt-proxy/dnscrypt-proxy.toml"

install_dnscrypt_proxy() {
    echo "[~] Installing dnscrypt-proxy..."

    dnscrypt_proxy_version=$(curl -s https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest|grep tag_name|cut -d '"' -f 4)
    wget https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/"$dnscrypt_proxy_version"/dnscrypt-proxy-linux_"$ARCH"-"$dnscrypt_proxy_version".tar.gz -O /tmp/dnscrypt-proxy.tar.gz
    tar -xzvf /tmp/dnscrypt-proxy.tar.gz -C /tmp
    mv /tmp/linux-$ARCH/dnscrypt-proxy /usr/sbin/dnscrypt-proxy
    rm /tmp/linux-$ARCH -r

    useradd -r -s /usr/sbin/nologin _dnscrypt-proxy
    groupadd _dnscrypt-proxy -U _dnscrypt-proxy
    mkdir -p /etc/dnscrypt-proxy/
    cp dnscrypt-proxy.toml $DNSCRYPT_PROXY_CONF

    cat <<EOF > /etc/systemd/system/dnscrypt-proxy.service
[Unit]
Description=DNSCrypt-proxy client
Documentation=https://github.com/DNSCrypt/dnscrypt-proxy/wiki
Wants=network-online.target nss-lookup.target
Before=nss-lookup.target

[Service]
User=_dnscrypt-proxy
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
CacheDirectory=dnscrypt-proxy
ExecStart=/usr/sbin/dnscrypt-proxy --config $DNSCRYPT_PROXY_CONF
RuntimeDirectory=dnscrypt-proxy
StateDirectory=dnscrypt-proxy

DynamicUser=yes
LockPersonality=yes
LogsDirectory=dnscrypt-proxy
MemoryDenyWriteExecute=true
NonBlocking=true
NoNewPrivileges=true
PrivateDevices=true
ProtectControlGroups=yes
ProtectHome=yes
ProtectHostname=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectSystem=strict
RestrictAddressFamilies=AF_INET AF_INET6
RestrictNamespaces=true
RestrictRealtime=true
SystemCallArchitectures=native
SystemCallFilter=@system-service

[Install]
WantedBy=multi-user.target
EOF

    chmod -R 755 /etc/dnscrypt-proxy/

    systemctl daemon-reload
    systemctl enable dnscrypt-proxy  
    systemctl start dnscrypt-proxy  

    echo "[+] dnscrypt-proxy installed"
}

install_blacklist() {
    echo "[~] Installing blacklist..."
    wget $DNS_BLACKLIST_URL -O /etc/dnscrypt-proxy/blacklist.txt
    echo -e '[blocked_names]\nblocked_names_file = '\''blacklist.txt'\''' | tee -a $DNSCRYPT_PROXY_CONF &>/dev/null
    systemctl restart dnscrypt-proxy

    echo "[+] Blacklist installed"
}

install_config() {
    echo "[~] Installing config..."
    wget https://raw.githubusercontent.com/svobodacenter/rpi-ap-proxy/master/dnscrypt-proxy.toml -O $DNSCRYPT_PROXY_CONF
    echo "[+] Config installed"
}

install_dnscrypt_proxy
install_blacklist
install_config