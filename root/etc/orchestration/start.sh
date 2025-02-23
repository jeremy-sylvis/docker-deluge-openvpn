#!/bin/bash

# Cleanup temp files
find /tmp/ -exec rm -rf {} \;

# Begin OpenVPN initialization
. /etc/openvpn/init.sh
