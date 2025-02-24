#!/command/with-contenv bash
#!/bin/bash

# Cleanup temp files
if [ -d "/tmp" ]; then
    echo "Deleting contents of /tmp..."
    find /tmp -type d -prune -exec rm -rf {} \;
else
    echo "/tmp doesn't exist; preparing directory..."
    mkdir -p /tmp
fi

# Begin OpenVPN initialization
. /etc/openvpn/init.sh
