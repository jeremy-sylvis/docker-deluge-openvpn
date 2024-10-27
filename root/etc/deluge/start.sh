#!/bin/bash

TIMESTAMP_FORMAT='%a %b %d %T %Y'
log() {
  echo "$(date +"${TIMESTAMP_FORMAT}") [deluge-start] $*"
}

# Source our persisted env variables from container startup
. /etc/deluge/environment-variables.sh

# This script will be called with tun/tap device name as parameter 1, and local IP as parameter 4
# See https://openvpn.net/index.php/open-source/documentation/manuals/65-openvpn-20x-manpage.html (--up cmd)

log "Up script executed with $*"

if [[ "$4" = "" ]]; then
  log "ERROR, unable to obtain tunnel address"
  log "killing $PPID"
  kill -9 $PPID
  exit 1
fi

# If deluge-pre-start.sh exists, run it
if [[ -x /config/deluge-pre-start.sh ]]; then
  log "Executing /config/deluge-pre-start.sh"
  /config/deluge-pre-start.sh "$@"
  log "/config/deluge-pre-start.sh returned $?"
fi

if [[ ! -e "/dev/random" ]]; then
  # Avoid "Fatal: no entropy gathering module detected" error
  log "INFO: /dev/random not found - symlink to /dev/urandom"
  ln -s /dev/urandom /dev/random
fi

. /etc/deluge/userSetup.sh

# if config file doesnt exist (wont exist until user changes a setting) then copy default config file
if [[ ! -f /config/core.conf ]]; then
  log "[info] Deluge config file doesn't exist, copying default..."
  cp /etc/config/core.conf /config
else
  log "[info] Deluge config file already exists, skipping copy"
fi

# if config file doesnt exist then copy stock config file
if [[ ! -f /config/web.conf ]]; then
  log "[info] Deluge webui config file doesn't exist, copying default..."
  cp /etc/config/web.conf /config
else
  log "[info] Deluge webui config file already exists, skipping copy"
fi

log "Using ip of interface $1: $4"
export DELUGE_BIND_ADDRESS_IPV4=$4

if [ -e /config/core.conf ]; then
  log "Updating Deluge conf file"
  #Interface
  sed -i -e "s/\"listen_interface\": \".*\"/\"listen_interface\": \"$DELUGE_BIND_ADDRESS_IPV4\"/" /config/core.conf
  #Deamon port
  sed -i -e "s/\"daemon_port\": \".*\"/\"daemon_port\": \"$DELUGE_DEAMON_PORT\"/" /config/core.conf
  #location
  sed -i -e "s/\"download_location\": \".*\"/\"download_location\": \"${DELUGE_INCOMPLETE_DIR//\//\\/}\"/" /config/core.conf
  sed -i -e "s/\"autoadd_location\": \".*\"/\"autoadd_location\": \"${DELUGE_WATCH_DIR//\//\\/}\"/" /config/core.conf
  sed -i -e "s/\"move_completed_path\": \".*\"/\"move_completed_path\": \"${DELUGE_DOWNLOAD_DIR//\//\\/}\"/" /config/core.conf
  sed -i -e "s/\"torrentfiles_location\": \".*\"/\"torrentfiles_location\": \"${DELUGE_TORRENT_DIR//\//\\/}\"/" /config/core.conf
fi

if [ -e /config/web.conf ]; then
  log "Updating Deluge web conf file"
  #Deamon port
  sed -i -e "s/\"default_daemon\": \".*\"/\"default_daemon\": \"127.0.0.1:$DELUGE_DEAMON_PORT\"/" /config/web.conf
  #Web port
  sed -i -e "s/\"port\": \".*\"/\"port\": \"$DELUGE_WEB_PORT\"/" /config/web.conf
fi

if [[ "true" = "$DROP_DEFAULT_ROUTE" ]]; then
  log "DROPPING DEFAULT ROUTE"
  ip r del default || exit 1
fi

# check if ufw is disabled (re-enable it)
if [[ "${ENABLE_UFW,,}" == "true" ]]; then
  ufw status | grep -qw active
  if [[ "$?" != "0" ]]; then
    log "Re-enabling ufw"
    ufw enable
    ufw status
  fi
fi

if [[ "true" = "$LOG_TO_STDOUT" ]]; then
  LOGFILE=/dev/stdout
else
  LOGFILE=/config/deluged.log
fi

log "Starting Deluge"
exec su --preserve-environment ${RUN_AS} -s /bin/bash -c "/app/deluge-venv/bin/deluged -d -c /config -L info -l $LOGFILE" &

# wait for deluge daemon process to start (listen for port)
while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"') == "" ]]; do
  sleep 0.1
done

log "Starting Deluge webui..."
exec su --preserve-environment ${RUN_AS} -s /bin/bash -c "/app/deluge-venv/bin/deluge-web -c /config -L info -l $LOGFILE" &

# Configure port forwarding if applicable
if [[ -x /etc/openvpn/${OPENVPN_PROVIDER,,}/update-port.sh && -z $DISABLE_PORT_UPDATER ]]; then
  log "Provider ${OPENVPN_PROVIDER^^} has a script for automatic port forwarding. Will run it now."
  log "If you want to disable this, set environment variable DISABLE_PORT_UPDATER=yes"
  log /etc/openvpn/${OPENVPN_PROVIDER,,}/update-port.sh &
fi

# If deluge-post-start.sh exists, run it
if [[ -x /config/deluge-post-start.sh ]]; then
  log "Executing /config/deluge-post-start.sh"
  /config/deluge-post-start.sh "$@"
  log "/config/deluge-post-start.sh returned $?"
fi

log "Deluge startup script complete."
