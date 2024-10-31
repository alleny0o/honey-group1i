#!/bin/bash

# Check required arguments
if [ $# -ne 4 ]; then
   echo "[$(date '+%Y-%m-%d %H:%M:%S')] Invalid arguments for container monitoring" >> /home/student/ignore_logs/attacker_status.log
   exit 1
fi

# Assign arguments to variables
container_name=$1
container_ip=$2
external_ip=$3
mitm_port=$4

# Set up lock file to ensure only one instance runs per container
lock_file="/home/student/pids/lock_attacker_status_${container_name}"
if ! mkdir "$lock_file" 2>/dev/null; then
   echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attacker status process already running for $container_name" >> /home/student/ignore_logs/attacker_status.log
   exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Started monitoring container: $container_name" >> /home/student/ignore_logs/attacker_status.log

# Cleanup on script exit
trap 'rm -rf "$lock_file"' EXIT

# Monitor authentication log for new attacker
log_file="/home/student/MITM/logs/authentication_attempts/${container_name}.log"
mkdir -p "$(dirname "$log_file")"

while true; do
   # Exit if container no longer exists
   if ! sudo lxc-info -n "$container_name" >/dev/null 2>&1; then
       echo "[$(date '+%Y-%m-%d %H:%M:%S')] Container $container_name no longer exists, stopping monitor" >> /home/student/ignore_logs/attacker_status.log
       exit 0
   fi

   # Check for attacker IP in log file
   if [ -f "$log_file" ] && [ -s "$log_file" ]; then
       attacker_ip=$(awk -F';' '{print $2}' "$log_file" | head -1)
       
       if [ -n "$attacker_ip" ]; then
           echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attacker detected for $container_name: $attacker_ip" >> /home/student/ignore_logs/attacker_status.log
           
           # Set up attacker-specific rules
           sudo iptables -w --table nat --insert PREROUTING --source "$attacker_ip" --destination "$external_ip" --jump DNAT --to-destination "$container_ip"
           sudo iptables -w --table nat --insert PREROUTING --source "$attacker_ip" --destination "$external_ip" --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port"
           
           # Remove general access rules
           sudo iptables -w --table nat --delete PREROUTING --destination "$external_ip" --jump DNAT --to-destination "$container_ip" 2>/dev/null
           sudo iptables -w --table nat --delete PREROUTING --destination "$external_ip" --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port" 2>/dev/null

           echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updated firewall rules for $container_name, starting timer" >> /home/student/ignore_logs/attacker_status.log

           # Start timer and exit
           sudo /home/student/timer.sh "$container_name" "$external_ip" & disown
           exit 0
       fi
   fi
   
   sleep 1
done
