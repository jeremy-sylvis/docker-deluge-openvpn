#!/bin/bash

# Execute anything which should occur after the tunnel is up *and* the routes are established e.g. traffic can successfully traverse the tunnel.

. /etc/deluge/environment-variables.sh

if [[ -x /config/openvpn-route-up.sh ]]; then
    echo "Executing OpenVPN route-up script at /config/openvpn-route-up.sh..."
    /config/openvpn-route-up.sh
    echo "Complete; returned $?."
fi