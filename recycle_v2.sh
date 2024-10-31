#!/bin/bash

# Function to print usage information
print_usage() {
    echo "Usage: $0 <container_name> <external_ip>" >> /home/student/ignore_logs/init.log
}

# Check if correct number of arguments are provided
if [ $# -ne 2 ]; then
    print_usage
    exit 1
fi

# Assign arguments to variables
container_name=$1
external_ip=$2
mask=24
date=$(date "+%F-%H-%M-%S")

# Make sure these are global
container_ip=""
new_container_name=""
new_banner=""

# Get the MITM port
mitm_port=$(sudo cat "/home/student/ports/${external_ip}_port.txt")

# Function to get the attacker IP from the log file
get_attacker_ip() {
    local log_file="/home/student/MITM/logs/authentication_attempts/${container_name}.log"
    if [ -f "$log_file" ] && [ -s "$log_file" ]; then
        local attacker_ip=$(awk -F';' '{print $2}' "$log_file" | head -1)
        echo "$attacker_ip"
    else
        echo ""
    fi
}

# Function to remove existing container and rules
remove_existing() {
    echo "Removing existing container and rules for $container_name" >> /home/student/ignore_logs/init.log

    # Get the current container IP (if it exists)
    local current_container_ip=$(sudo lxc-info -n $container_name -iH 2>/dev/null)

    # Get the attacker IP
    local attacker_ip=$(get_attacker_ip)

    # Remove iptables rules
    if [ -n "$attacker_ip" ]; then
        sudo iptables -w --table nat --delete PREROUTING --source "$attacker_ip" --destination "$external_ip" --jump DNAT --to-destination "$current_container_ip" >/dev/null 2>&1
        sudo iptables -w --table nat --delete PREROUTING --source "$attacker_ip" --destination "$external_ip" --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port" >/dev/null 2>&1
    fi

    if [ -n "$current_container_ip" ]; then
        sudo iptables -w -t nat -D PREROUTING -s 0.0.0.0/0 -d $external_ip -j DNAT --to-destination $current_container_ip >/dev/null 2>&1
        sudo iptables -w -t nat -D POSTROUTING -s $current_container_ip -d 0.0.0.0/0 -j SNAT --to-source $external_ip >/dev/null 2>&1
    fi
    sudo iptables -w -t nat -D PREROUTING -s 0.0.0.0/0 -d $external_ip -p tcp --dport 22 -j DNAT --to-destination "10.0.3.1:$mitm_port" >/dev/null 2>&1
    sudo ip addr del $external_ip/$mask brd + dev eth3 >/dev/null 2>&1

    # Stop and delete the MITM process managed by PM2
    if sudo pm2 list | grep -q "$container_name"; then
        echo "Stopping MITM process for $container_name" >> /home/student/ignore_logs/init.log
        sudo pm2 stop "$container_name" >/dev/null 2>&1
        sudo pm2 delete "$container_name" >/dev/null 2>&1
    fi

    # Stop and destroy the container
    sudo lxc-stop -n $container_name -k >/dev/null 2>&1
    sudo lxc-destroy -n $container_name >/dev/null 2>&1

    echo "Existing container, rules, and MITM removed." >> /home/student/ignore_logs/init.log
}

# Function to create and set up container
create_container() {
    # Shuffle and pick a random banner
    banners=( "ethical" "legal" "technical" "none" )
    banners=( $(shuf -e "${banners[@]}") )

    # Get the banner and set new name for the container
    new_banner=${banners[0]}
    new_container_name="${date}_${new_banner}_${external_ip}"

    echo "Selected scenario for new container: $new_container_name" >> /home/student/ignore_logs/init.log

    echo "Creating new container: $new_container_name" >> /home/student/ignore_logs/init.log
    sudo lxc-create -t download -n $new_container_name -- -d ubuntu -r focal -a amd64 >/dev/null 2>&1
    sudo lxc-start -n $new_container_name >/dev/null 2>&1
    
    # Wait for container to start
    if ! sudo /home/student/check_container.sh $new_container_name >/dev/null 2>&1; then
        echo "Failed to start container" >> /home/student/ignore_logs/init.log
        exit 1
    fi

    # Add Honey to Container
    sudo /home/student/setup_honey.sh $new_container_name >/dev/null 2>&1

    # Get the new container IP
    container_ip=$(sudo lxc-info -n $new_container_name -iH)
    if [ -z "$container_ip" ]; then
        echo "Failed to obtain container IP. Exiting." >> /home/student/ignore_logs/init.log
        exit 1
    fi
    echo "New container IP: $container_ip" >> /home/student/ignore_logs/init.log
}

# Start MITM server
start_mitm() {
    echo "Starting MITM for $new_container_name" >> /home/student/ignore_logs/init.log
    if sudo pm2 -l "/home/student/logs/${new_banner}/${new_container_name}" start MITM/mitm.js --name "$new_container_name" -- -n "$new_container_name" -i "$container_ip" -p $mitm_port --mitm-ip 10.0.3.1 --auto-access --auto-access-fixed 1 --debug --ssh-server-banner-file /home/student/banners/${new_banner}.txt >/dev/null 2>&1; then
        echo "MITM server started successfully" >> /home/student/ignore_logs/init.log
    else
        echo "Failed to start MITM server" >> /home/student/ignore_logs/init.log
        exit 1
    fi
}

# Function to set up networking
setup_networking() {
    # Ensure the network interface is up
    sudo ip link set eth3 up >/dev/null 2>&1
    # Add the external IP to the network interface
    sudo ip addr add $external_ip/$mask brd + dev eth3 >/dev/null 2>&1

    # Set up NAT (Network Address Translation) rules
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --jump DNAT --to-destination $container_ip >/dev/null 2>&1
    sudo iptables -w --table nat --insert POSTROUTING --source $container_ip --destination 0.0.0.0/0 --jump SNAT --to-source $external_ip >/dev/null 2>&1
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port" >/dev/null 2>&1

    # Enable IP forwarding
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
}

# Function to set up firewall
setup_firewall() {
    echo "Setting up firewall for $new_container_name" >> /home/student/ignore_logs/init.log
    sudo lxc-attach -n $new_container_name -- bash -c "apt update >/dev/null 2>&1 && apt install -y ufw >/dev/null 2>&1"
    sudo lxc-attach -n $new_container_name -- bash -c "ufw allow 22/tcp && ufw --force enable" >/dev/null 2>&1
}

# Function to set up honey files
setup_honey() {
    echo "Setting up honey files for $new_container_name" >> /home/student/ignore_logs/init.log
    sudo lxc-attach -n $new_container_name -- bash -c "mkdir -p /opt/honey" >/dev/null 2>&1
    sudo lxc-attach -n $new_container_name -- bash -c "echo 'Sensitive Data' > /opt/honey/secrets.txt" >/dev/null 2>&1
    sudo lxc-attach -n $new_container_name -- bash -c "echo 'user:password' > /opt/honey/credentials.txt" >/dev/null 2>&1
}

# Function to set up SSH
setup_ssh() {
    echo "Setting up SSH server $new_container_name" >> /home/student/ignore_logs/init.log
    sudo lxc-attach -n $new_container_name -- bash -c "
        if ! dpkg -s openssh-server >/dev/null 2>&1; then
            apt-get update >/dev/null 2>&1
            apt-get install -y openssh-server >/dev/null 2>&1
        fi
    " >/dev/null 2>&1
}

# Function to verify SSH banner and server status
verify_ssh_setup() {
    echo "Verifying SSH setup for $new_container_name" >> /home/student/ignore_logs/init.log
    sudo lxc-attach -n $new_container_name -- bash -c "
        if dpkg -s openssh-server >/dev/null 2>&1; then
            echo 'SSH server is installed'
            if systemctl is-active --quiet ssh; then
                echo 'SSH service is running'
            else
                echo 'SSH service is not running'
                systemctl status ssh
            fi
        else
            echo 'SSH server is not installed'
        fi
    " >/dev/null 2>&1
}

# Main execution
remove_existing

create_container
setup_firewall
setup_ssh
verify_ssh_setup

start_mitm  # Start MITM before setting up networking
# Give MITM server time to start
if sudo /home/student/check_mitm.sh $new_container_name $mitm_port >/dev/null 2>&1; then
    echo "MITM server started successfully" >> /home/student/ignore_logs/init.log
else
    echo "Failed to start MITM server" >> /home/student/ignore_logs/init.log
    exit 1
fi

setup_networking
setup_honey

sudo /home/student/attacker_status.sh $new_container_name $container_ip $external_ip $mitm_port & disown

echo "Container $container_name has been recycled successfully" >> /home/student/ignore_logs/init.log

exit 0