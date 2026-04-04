#!/bin/bash
# https://support.vyprvpn.com/hc/en-us/articles/360038096131-Where-can-I-find-the-OpenVPN-files-

if [[ -z "$VPN_PROVIDER_HOME" ]]; then
   echo "ERROR: Need to have VPN_PROVIDER_HOME set to call this script" && exit 1
fi

# Download & extract ovpn files from provider
URL="https://support.vyprvpn.com/hc/article_attachments/44585865394189"
PACKAGE="VyprVPN_OpenVPN_2026-03-06_256-bit.zip"
OUTPUT="/tmp/VyprVPN.zip"

download_extract () {
  echo "Downloading OpenVPN configs into temporary file ${OUTPUT}"
  curl -sSL "${URL}/${PACKAGE}" -o "${OUTPUT}"

  # Delete all files for VyprVPN provider, except scripts
  find "${VPN_PROVIDER_HOME}" -type f ! -iname "*.sh" -delete

  temp_dir=$(mktemp -d) && export temp_dir
  echo "Temporarily extracting OpenVPN configs into directory ${temp_dir}"
  unzip -qq "${OUTPUT}" -d "${temp_dir}"
}

rename_configs () {
  cp "${temp_dir}"/VyprVPN_OpenVPN_2026-03-06/* "${VPN_PROVIDER_HOME}/"
  
  echo "Modify configs for this container"
  find "${VPN_PROVIDER_HOME}" -type f -iname "*.ovpn" -exec /etc/openvpn/modify-openvpn-config.sh {} \;
  # Select a random server as default.ovpn
  ln -sf "$(find "${VPN_PROVIDER_HOME}" -iname "*.ovpn" | shuf -n 1)" "${VPN_PROVIDER_HOME}/default.ovpn"
}

# Only download configs if /etc/openvpn/vyprvpn is empty
if find "${VPN_PROVIDER_HOME}" -type f ! -iname 'configure-openvpn.sh' | grep -q 'ovpn'; then
  echo "ovpn files detected, not downloading configs"
else
  download_extract
  rename_configs
  echo "Removing ${temp_dir} & ${OUTPUT}"
  rm -rf "${temp_dir}"
  rm -f "${OUTPUT}"
fi
