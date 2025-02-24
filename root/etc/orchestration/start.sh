#!/command/with-contenv bash
#!/bin/bash

# Cleanup temp files
if [ -d "/var/tmp" ]; then
    echo "Deleting contents of /var/tmp..."
    find /var/tmp/ -exec rm -rf {} \;
else
    echo "/var/tmp doesn't exist; preparing directory..."
    mkdir -p /var/tmp
fi

# Begin OpenVPN initialization
. /etc/openvpn/init.sh
