#!/bin/bash
if [ $# -ne 1 ]; then
    echo "Usage: $0 <container_name>" >> /home/student/ignore_logs/container_check.log
    exit 1
fi

container_name=$1
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if sudo lxc-info -n "$container_name" | grep -q "RUNNING" && \
       [ -n "$(sudo lxc-info -n "$container_name" -iH)" ]; then
        exit 0
    fi
    attempt=$((attempt + 1))
    sleep 1
done

echo "Container $container_name failed to start properly after $max_attempts seconds" >> /home/student/ignore_logs/container_check.log
exit 1