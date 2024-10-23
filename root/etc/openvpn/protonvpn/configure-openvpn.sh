#! /bin/bash

set -e

# Configs for ProtonVPN aren't publicly available; only one is provided for now

baseURL="https://www.privateinternetaccess.com/openvpn"
PIA_OPENVPN_CONFIG_BUNDLE=${PIA_OPENVPN_CONFIG_BUNDLE:-"openvpn"}

if [ -z "$VPN_PROVIDER_HOME" ]; then
    echo "ERROR: Need to have VPN_PROVIDER_HOME set to call this script" && exit 1
fi

# Delete all files for PIA provider, except scripts
find "$VPN_PROVIDER_HOME" -type f ! -name "*.sh" -delete

# Copy in static configs
cp -v /etc/openvpn/protonvpn/*.ovpn $VPN_PROVIDER_HOME/

echo "Modify configs for this container"
find "${VPN_PROVIDER_HOME}" -type f -iname "*.ovpn" -exec /etc/openvpn/modify-openvpn-config.sh {} \;