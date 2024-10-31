#!/bin/bash

# Check required arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <container_name> <external_ip>" >> /home/student/ignore_logs/timer.log
    exit 1
fi

# Assign arguments to variables
container_name=$1
external_ip=$2

# Set up lock file to ensure only one instance runs per container
lock_file="/home/student/pids/lock_timer_${container_name}"
if ! mkdir "$lock_file" 2>/dev/null; then
    echo "Timer already running for $container_name" >> /home/student/ignore_logs/timer.log
    exit 1
fi

# Cleanup on script exit
trap 'rm -rf "$lock_file"' EXIT

# Main loop - check both time and connection status
elapsed=0
while [ $elapsed -lt 300 ]; do  # 300 seconds = 5 minutes
    # Check if container still exists
    if ! sudo lxc-info -n "$container_name" >/dev/null 2>&1; then
        exit 0
    fi

    # Check if attacker has logged out by checking container's specific logout file
    if [ -s "/home/student/MITM/logs/logouts/${container_name}.log" ]; then
        echo "Attacker logged out for container $container_name, recycling" >> /home/student/ignore_logs/timer.log
        sudo /home/student/recycle_v2.sh "$container_name" "$external_ip" & disown
        exit 0
    fi

    sleep 1
    ((elapsed++))
done

# If we reach here, time elapsed without disconnect
echo "Timer completed for container $container_name, recycling" >> /home/student/ignore_logs/timer.log
sudo /home/student/recycle_v2.sh "$container_name" "$external_ip" & disown
exit 0
