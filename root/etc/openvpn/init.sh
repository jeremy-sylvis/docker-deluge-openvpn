#!/bin/bash

##
# Get some initial setup out of the way.
##

TIMESTAMP_FORMAT='%a %b %d %T %Y'
log() {
  echo "$(date +"${TIMESTAMP_FORMAT}") [start-vpn] $*"
}

if [[ -n "$REVISION" ]]; then
  log "Starting container with revision: $REVISION"
fi

[[ "${DEBUG}" == "true" ]] && set -x

# If openvpn-pre-start.sh exists, run it
if [[ -x /scripts/openvpn-pre-start.sh ]]; then
  echo "Executing /scripts/openvpn-pre-start.sh"
  /scripts/openvpn-pre-start.sh "$@"
  echo "/scripts/openvpn-pre-start.sh returned $?"
fi

# Allow for overriding the DNS used directly in the /etc/resolv.conf
if compgen -e | grep -q "OVERRIDE_DNS"; then
  echo "One or more OVERRIDE_DNS addresses found. Will use them to overwrite /etc/resolv.conf"
  echo "" >/etc/resolv.conf
  for var in $(compgen -e | grep "OVERRIDE_DNS"); do
    echo "nameserver $(printenv "$var")" >>/etc/resolv.conf
  done
fi

# Test DNS resolution
if ! nslookup ${HEALTH_CHECK_HOST:-"google.com"} 1>/dev/null 2>&1; then
  echo "WARNING: initial DNS resolution test failed"
fi

log "Configuring OPENVPN"
# If create_tun_device is set, create /dev/net/tun
if [[ "${CREATE_TUN_DEVICE,,}" == "true" ]]; then
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200
  chmod 600 /dev/net/tun
fi

##
# Configure OpenVPN.
# This basically means to figure out the config file to use as well as username/password
##

# If no OPENVPN_PROVIDER is given, we default to "custom" provider.
VPN_PROVIDER="${OPENVPN_PROVIDER:-custom}"
export VPN_PROVIDER="${VPN_PROVIDER,,}" # to lowercase
export VPN_PROVIDER_HOME="/etc/openvpn/${VPN_PROVIDER}"
mkdir -p "$VPN_PROVIDER_HOME"

# Make sure that we have enough information to start OpenVPN
if [[ -z $OPENVPN_CONFIG_URL ]] && [[ "${OPENVPN_PROVIDER}" == "**None**" ]] || [[ -z "${OPENVPN_PROVIDER-}" ]]; then
  log "ERROR: Cannot determine where to find your OpenVPN config. Both OPENVPN_CONFIG_URL and OPENVPN_PROVIDER is unset."
  log "You have to either provide a URL to the config you want to use, or set a configured provider that will download one for you."
  log "Exiting..." && exit 1
fi
log "Using OpenVPN provider: ${VPN_PROVIDER^^}"

if [[ -n $OPENVPN_CONFIG_URL ]]; then
  log "Found URL to OpenVPN config, will download it."
  CHOSEN_OPENVPN_CONFIG=$VPN_PROVIDER_HOME/downloaded_config.ovpn
  curl -o "$CHOSEN_OPENVPN_CONFIG" -sSL "$OPENVPN_CONFIG_URL"
fi

if [[ -z ${CHOSEN_OPENVPN_CONFIG} ]]; then

  # Support pulling configs from external config sources
  VPN_CONFIG_SOURCE="${VPN_CONFIG_SOURCE:-auto}"
  VPN_CONFIG_SOURCE="${VPN_CONFIG_SOURCE,,}" # to lowercase

  echo "Running with VPN_CONFIG_SOURCE ${VPN_CONFIG_SOURCE}"

  if [[ "${VPN_CONFIG_SOURCE}" == "auto" ]]; then
    if [[ -x $VPN_PROVIDER_HOME/configure-openvpn.sh ]]; then
      echo "Provider ${VPN_PROVIDER^^} has a bundled setup script. Defaulting to internal config"
      VPN_CONFIG_SOURCE=internal
    else
      echo "No bundled config script found for ${VPN_PROVIDER^^}. Defaulting to external config"
      VPN_CONFIG_SOURCE=external
    fi
  fi

  if [[ "${VPN_CONFIG_SOURCE}" == "external" ]]; then
    # shellcheck source=openvpn/fetch-external-configs.sh
    ./etc/openvpn/fetch-external-configs.sh
  fi

  if [[ -x $VPN_PROVIDER_HOME/configure-openvpn.sh ]]; then
    echo "Executing setup script for $OPENVPN_PROVIDER"
    # Preserve $PWD in case it changes when sourcing the script
    pushd -n "$PWD" >/dev/null
    # shellcheck source=/dev/null
    . "$VPN_PROVIDER_HOME"/configure-openvpn.sh
    # Restore previous PWD
    popd >/dev/null
  fi
fi

if [[ -z ${CHOSEN_OPENVPN_CONFIG} ]]; then
  # We still don't have a config. The user might have set a config in OPENVPN_CONFIG.
  if [[ -n "${OPENVPN_CONFIG-}" ]]; then
    readarray -t OPENVPN_CONFIG_ARRAY <<<"${OPENVPN_CONFIG//,/$'\n'}"

    ## Trim leading and trailing spaces from all entries. Inefficient as all heck, but works like a champ.
    for i in "${!OPENVPN_CONFIG_ARRAY[@]}"; do
      OPENVPN_CONFIG_ARRAY[${i}]="${OPENVPN_CONFIG_ARRAY[${i}]#"${OPENVPN_CONFIG_ARRAY[${i}]%%[![:space:]]*}"}"
      OPENVPN_CONFIG_ARRAY[${i}]="${OPENVPN_CONFIG_ARRAY[${i}]%"${OPENVPN_CONFIG_ARRAY[${i}]##*[![:space:]]}"}"
    done

    # If there were multiple configs (comma separated), select one of them
    if ((${#OPENVPN_CONFIG_ARRAY[@]} > 1)); then
      OPENVPN_CONFIG_RANDOM=$((RANDOM % ${#OPENVPN_CONFIG_ARRAY[@]}))
      log "${#OPENVPN_CONFIG_ARRAY[@]} servers found in OPENVPN_CONFIG, ${OPENVPN_CONFIG_ARRAY[${OPENVPN_CONFIG_RANDOM}]} chosen randomly"
      OPENVPN_CONFIG="${OPENVPN_CONFIG_ARRAY[${OPENVPN_CONFIG_RANDOM}]}"
    fi

    # Check that the chosen config exists.
    if [[ -f "${VPN_PROVIDER_HOME}/${OPENVPN_CONFIG}.ovpn" ]]; then
      log "Starting OpenVPN using config ${OPENVPN_CONFIG}.ovpn"
      CHOSEN_OPENVPN_CONFIG="${VPN_PROVIDER_HOME}/${OPENVPN_CONFIG}.ovpn"
    else
      log "Supplied config ${OPENVPN_CONFIG}.ovpn could not be found."
      log "Your options for this provider are:"
      ls "${VPN_PROVIDER_HOME}" | grep .ovpn
      log "NB: Remember to not specify .ovpn as part of the config name."
      exit 1 # No longer fall back to default. The user chose a specific config - we should use it or fail.
    fi
  else
    log "No VPN configuration provided. Using default."
    CHOSEN_OPENVPN_CONFIG="${VPN_PROVIDER_HOME}/default.ovpn"
  fi
fi

MODIFY_CHOSEN_CONFIG="${MODIFY_CHOSEN_CONFIG:-true}"
# The config file we're supposed to use is chosen, modify it to fit this container setup
if [[ "${MODIFY_CHOSEN_CONFIG,,}" == "true" ]]; then
  # shellcheck source=openvpn/modify-openvpn-config.sh
  /etc/openvpn/modify-openvpn-config.sh "$CHOSEN_OPENVPN_CONFIG"
fi

# If openvpn-post-config.sh exists, run it
if [[ -x /scripts/openvpn-post-config.sh ]]; then
  echo "Executing /scripts/openvpn-post-config.sh"
  /scripts/openvpn-post-config.sh "$CHOSEN_OPENVPN_CONFIG"
  echo "/scripts/openvpn-post-config.sh returned $?"
fi

# add OpenVPN user/pass
if [[ "${OPENVPN_USERNAME}" == "**None**" ]] || [[ "${OPENVPN_PASSWORD}" == "**None**" ]]; then
  if [[ ! -f /config/openvpn-credentials.txt ]]; then
    log "OpenVPN credentials not set. Exiting."
    exit 1
  fi
  log "Found existing OPENVPN credentials at /config/openvpn-credentials.txt"
else
  log "Setting OpenVPN credentials..."
  mkdir -p /config
  echo "${OPENVPN_USERNAME}" >/config/openvpn-credentials.txt
  echo "${OPENVPN_PASSWORD}" >>/config/openvpn-credentials.txt
  chmod 600 /config/openvpn-credentials.txt
fi

# Persist transmission settings for use by transmission-daemon
python3 /etc/openvpn/persistEnvironment.py /etc/deluge/environment-variables.sh

# Setting up kill switch
/etc/ufw/enable.sh tun0 ${CHOSEN_OPENVPN_CONFIG}

DELUGE_CONTROL_OPTS="--script-security 2 --up-delay --up /etc/openvpn/tunnelUp.sh --down /etc/openvpn/tunnelDown.sh"
# shellcheck disable=SC2086
log "Starting openvpn"

# Capture/relay output from `openvpn` in order to watch for completed initialization, at which point we can execute a post-initialize script.
stdbuf -oL openvpn ${DELUGE_CONTROL_OPTS} ${OPENVPN_OPTS} --config "${CHOSEN_OPENVPN_CONFIG}" | {
  # Once initialization is detected, there's no point to continuing to run `grep`
  WAS_INITIALIZATION_COMPLETED=false
  WAS_REMOTE_IP_DETECTED=false

  while IFS= read -r line
  do
    # Pass-through captured output
    echo "$line"

    if [ "$WAS_INITIALIZATION_COMPLETED" != true ]; then
      # Scan for "Initialization Sequence Completed" from OpenVPN outputs
      echo "$line" | grep --quiet -P '^.*(Initialization Sequence Completed).*$'
      MATCH=$?
      if [[ $MATCH -eq 0 ]]; then
        # Set our latch
        WAS_INITIALIZATION_COMPLETED=true

        if [[ -x /config/openvpn-post-init.sh ]]; then
          echo "OpenVPN initialization complete and a post-init script was detected, executing it..."
          /config/openvpn-post-init.sh
        else
          echo "OpenVPN initialization complete but no post-init script detected; skipping it..."
        fi
      fi
    fi

    # ${VARIABLE,,} is .ToLower()
    if [ "${OPENVPN_PROVIDER,,}" = "protonvpn" ] && [ "$WAS_REMOTE_IP_DETECTED" != true ]; then
      # In order to handle ProtonVPN port forwarding+NAT, we need to use NATPMPC. For this,
      # we need the Remote IP. We can use that to establish the forwarded port.
      # With that, we'll need to force-update Deluge configuration to listen on that forwarded port.

      # Scan for "Peer Connection Initiated with [AF_INET][iphere]" to fetch the remote IP
      # Apparently this sucks at handling capture groups - use an inline python handler
      REMOTE_IP=$(echo "$line" | python3 -c $'
        import re
        import sys
        g=re.match(r\'^.*Peer Connection Initiated with \[AF_INET\](.*)$\',sys.stdin)
        if g is not None:
          print g.group(1)
        ')

      if [ -n "$REMOTE_IP" ]; then
        echo "Detected REMOTE_IP: $REMOTE_IP"

        # Setup NATPMPC using the Remote IP
        echo "Querying gateway for natpmpc compatibility..."
        NATPMPC_GATEWAY_CHECK_RESULT=$(natpmpc -g $REMOTE_IP)

        # If the gateway wasn't compatible, just exit.
        if [ "$?" != "0" ]; then
          echo "Gateway is not compatible with natpmpc. Error:"
          echo $NATPMPC_GATEWAY_CHECK_RESULT
          exit 1
        fi

        NATPMPC_UDP_FORWARD_RESULT=$(natpmpc -g $REMOTE_IP -a 1 0 udp 60)

        # IF the forward failed, just exit.
        if [ "$?" != "0"]; then
          echo "Failed to forward UDP port using natpmpc. Error:"
          echo "$NATPMPC_UDP_FORWARD_RESULT"
          exit 2
        fi

        # Parse the result for the port being forwarded
        NATPMPC_FORWARDED_PORT=$(echo $NATPMPC_UDP_FORWARD_RESULT | python3 -c $'
          import re
          import sys
          for i in sys.stdin:
            i=i.strip()
            g=re.match(r\'Mapped public port ([0-9]{1,5}).*\',i)
            if g is not None:
              print g.group(1)
          ')

        if [ -z "$NATPMPC_FORWARDED_PORT" ]; then
          echo "Failed to parse forwarded port. Output:"
          echo $NATPMPC_UDP_FORWARD_RESULT
          exit 3
        fi

        # Update Deluge config with this new port
        # TBD
        
        # Begin a background loop to keep the port active
        # TBD

        WAS_REMOTE_IP_DETECTED=true
      fi
    fi
  done
}
