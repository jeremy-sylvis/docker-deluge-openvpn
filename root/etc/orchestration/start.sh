#!/bin/bash

# Cleanup temp files
tempFiles=@(
    "/tmp/gateway_initialized"
    "/tmp/openvpn_exited"
    "/tmp/natpmpc_query_success"
    "/tmp/natpmpc_forwarded_port"
)
for $path in ${tempFiles[@]}; do
    if [ -f "$path" ]; then
        rm "$path"
    fi
done

# Begin OpenVPN initialization
./etc/openvpn/init.sh
