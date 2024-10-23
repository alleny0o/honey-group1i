#!/bin/bash

print_usage() {
    echo "Usage: $0 <container_name> <external_ip>"
}

if [ $# -ne 2 ]; then
    print_usage
    exit 1
fi

countdown() {
    secs=$1
    while [ $secs -gt 0 ]; do
        echo -ne "Countdown: $secs\033[0K\r"
        sleep 1
        : $((secs--))
    done
}

while true; do
    echo "Starting the recycling process for $container_name."
    countdown 120

    echo "Recycling the container $container_name"
    sudo ./recycle_v2.sh $container_name $external_ip