#!/bin/bash
# Check required arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <container_name> <mitm_port>" >> /home/student/ignore_logs/mitm_check.log
    exit 1
fi

container_name=$1
mitm_port=$2
max_attempts=30  # Maximum number of attempts (30 seconds)
attempt=0

while [ $attempt -lt $max_attempts ]; do
    # Check if PM2 process is running and listening on port
    if sudo pm2 list | grep -q "$container_name"; then
        if sudo netstat -tln | grep -q ":$mitm_port "; then
            exit 0
        fi
    fi
    
    attempt=$((attempt + 1))
    sleep 1
done

echo "MITM for $container_name failed to start properly after $max_attempts seconds" >> /home/student/ignore_logs/mitm_check.log
exit 1