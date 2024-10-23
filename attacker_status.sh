#!/bin/bash

print_usage() {
    echo "Usage: $0 <container_name> <container_ip> <external_ip> <mitm_port>"
}

if [ $# -ne 3 ]; then
    print_usage
    exit 1
fi

container_name=$1
container_ip=$2
external_ip=$3
mitm_port=$4
attacker_ip=""

file="./MITM/logs/authentication_attempts/${container_name}.log"

while true;
do
    sleep 1
    if [ -f "$file" ]; then
        if [ -s "$file" ]; then
            echo "Log file $file exists and is not empty."
            attacker_ip=$(awk -F';' '{print $2}' "$file" | head -1)
            if [ -n "$attacker_ip" ]; then
                echo "Detected attacker IP: $attacker_ip"

                # Allowing traffic only from the attacker IP
                sudo iptables -w --table nat --insert PREROUTING --source $attacker_ip --destination $external_ip --jump DNAT --to-destination $container_ip
                # Allowing only the attacker to SSH on the MITM port
                sudo iptables -w --table nat --insert PREROUTING --source $attacker_ip --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port"

                # Removing the rule that allows all connections (if it exists)
                sudo iptables -w --table nat --delete PREROUTING --destination $external_ip --jump DNAT --to-destination $container_ip 2>/dev/null
                sudo iptables -w --table nat --delete PREROUTING --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port" 2>/dev/null

                # Starting the recycling timer
                sudo ./timer.sh $container_name $external_ip
            else
                echo "Could not detect attacker IP from the log file."
            fi    
        else
            echo "Log file $file is empty."
        fi
    else
        echo "Log file $file does not exist."
    fi
done
