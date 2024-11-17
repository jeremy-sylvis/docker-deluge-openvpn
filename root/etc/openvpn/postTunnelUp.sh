#!/bin/bash

# This is intended to execute _after_ OpenVPN's "--up" script which executes as the final stage of opening a tunnel.
# This can execute anything which needs to wait until the tunnel is fully established and operational.

. /etc/deluge/environment-variables.sh

TIMESTAMP_FORMAT='%a %b %d %T %Y'
log() {
  echo "$(date +"${TIMESTAMP_FORMAT}") [postTunnelUp.sh] $*"
}

log "Beginning OpenVPN post-Tunnel Up process..."

# If using ProtonVPN, block until we've detected a gateway and can establish port forwarding
# most of this will have to move to `tunnelUp.sh`
# ${VARIABLE,,} is .ToLower()
if [ "${OPENVPN_PROVIDER,,}" = "protonvpn" ] && [ "${OPENVPN_PROTONVPN_NATPMPC,,}" == "true" ]; then
  # override the IP for testing
  log "Overwriting gateway IP..."
  GATEWAY_IP="10.2.0.1"

  # Setup NATPMPC using the Remote IP
  log "Querying gateway for natpmpc compatibility..."
  NATPMPC_GATEWAY_CHECK_RESULT=$()

  # We need to be able to handle the "readnatpmpresponseorretry returned -100 (TRY AGAIN)" messages in a loop and to block until success.
  QUERY_SUCCESS="false"
  while [ "$QUERY_SUCCESS" != "true" ]
  do
    stdbuf -oL natpmpc -g "$GATEWAY_IP" | {
      # Once initialization is detected, there's no point to continuing to run `grep`
      while IFS= read -r line
      do
        # Pass-through captured output
        echo "$line"

        echo "$line" | grep --quiet -P '^.*(readnatpmpresponseorretry returned).*\(SUCCESS\).*$'
        MATCH=$?
        if [[ $MATCH -eq 0 ]]; then
          QUERY_SUCCESS="true"
        fi
      done
    }
  done

  # If the gateway wasn't compatible, just exit.
  if [ "$?" != "0" ]; then
    log "Gateway is not compatible with natpmpc. Ensure the selected ProtonVPN server profile supports p2p and the '+nr' option and 'b+n' option is not specified in your username."
    exit 1
  fi

  # Perform a test forward so we can parse the port
  NATPMPC_FORWARDED_PORT=''
  stdbuf -oL natpmpc -g "$GATEWAY_IP" -a 0 0 "udp" 60 | {
    while IFS= read -r line
    do
      # Pass-through captured output
      echo "$line"

      TEMP_NATPMPC_FORWARDED_PORT=$(echo "$line" | python3 -c $'
import re
import sys
for i in sys.stdin.readlines():
  i=i.rstrip()
  g=re.match(r\'Mapped public port ([0-9]{1,5}).*\',i)
  if g is not None:
    print(g.group(1))
')
      if [ ! -z "$TEMP_NATPMPC_FORWARDED_PORT" ]; then
        log "Detected forwarded port '$TEMP_NATPMPC_FORWARDED_PORT'."
        NATPMPC_FORWARDED_PORT="$TEMP_NATPMPC_FORWARDED_PORT"
      fi
      
    done
  } 

  # IF the forward failed, just exit.
  if [ "$?" != "0" ]; then
    log "Failed to forward UDP port using natpmpc."
    exit 2
  fi

  if [ -z "$NATPMPC_FORWARDED_PORT" ]; then
    log "Failed to parse forwarded UDP port."
    exit 3
  fi

  # Update Deluge config with this new port
  log "Updating Deluge config to listen on forwarded UDP port '$NATPMPC_FORWARDED_PORT'..."
  sed -i -E "s/.*listen_ports.*/    \"listen_ports\": \[ $NATPMPC_FORWARDED_PORT \],\n/" "/etc/config/core.conf"
  
  # Begin a background loop to keep the port active
  log "Beginning background refresh loop for forwarded port..."
  while true ; do date ; natpmpc -g "$GATEWAY_IP" -a "$NATPMPC_FORWARDED_PORT" 0 "udp" 60 && natpmpc -g "$GATEWAY_IP" -a "$NATPMPC_FORWARDED_PORT" 0 "tcp" 60 || { echo -e "ERROR with natpmpc command \a" ; break ; } ; sleep 45 ; done &
fi

log "Launching Deluge..."
/etc/deluge/start.sh "$@" & disown -h /etc/deluge/start.sh

log "Completed OpenVPN post-Tunnel Up process."