#!/bin/bash

# Cleanup temp files
find /var/tmp/ -exec rm -rf {} \;

# Begin OpenVPN initialization
. /etc/openvpn/init.sh
