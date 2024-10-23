#!/bin/bash

print_usage() {
    echo "Usage: $0 <container_name> <container_ip> <external_ip> <mitm_port>"
}

if [ $# -ne 4 ]; then
    print_usage
    exit 1
fi

container_name=$1
container_ip=$2
external_ip=$3
mitm_port=$4
attacker_ip=""
previous_state=""

file="./MITM/logs/authentication_attempts/${container_name}.log"

# Redirect all standard output and error to a log file
exec 1>>"./logs/attacker_status_${container_name}.log" 2>&1

while true; do
    sleep 1
    current_state="none"
    
    if [ -f "$file" ]; then
        if [ -s "$file" ]; then
            current_state="has_content"
            if [ "$previous_state" != "has_content" ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log file detected with content for $container_name"
            fi
            
            new_attacker_ip=$(awk -F';' '{print $2}' "$file" | head -1)
            if [ -n "$new_attacker_ip" ] && [ "$new_attacker_ip" != "$attacker_ip" ]; then
                attacker_ip="$new_attacker_ip"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] New attacker IP detected: $attacker_ip"

                # Allowing traffic only from the attacker IP
                sudo iptables -w --table nat --insert PREROUTING --source $attacker_ip --destination $external_ip --jump DNAT --to-destination $container_ip

                # Allowing only the attacker to SSH on the MITM port
                sudo iptables -w --table nat --insert PREROUTING --source $attacker_ip --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port"

                # Removing the rule that allows all connections (if it exists)
                sudo iptables -w --table nat --delete PREROUTING --destination $external_ip --jump DNAT --to-destination $container_ip 2>/dev/null
                sudo iptables -w --table nat --delete PREROUTING --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port" 2>/dev/null

                # Starting the recycling timer
                sudo ./timer.sh $container_name $external_ip
            fi
        else
            current_state="empty"
            if [ "$previous_state" != "empty" ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Empty log file for $container_name"
            fi
        fi
    else
        current_state="no_file"
        if [ "$previous_state" != "no_file" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for log file for $container_name"
        fi
    fi
    
    previous_state="$current_state"
done