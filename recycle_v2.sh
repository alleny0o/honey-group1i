#!/bin/bash

# Function to print usage information
print_usage() {
    echo "Usage: $0 <container_name> <external_ip>"
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

# Get the MITM port
mitm_port=$(sudo cat "./ports/${external_ip}_port.txt")

# Function to get the attacker IP from the log file
get_attacker_ip() {
    local log_file="./MITM/logs/authentication_attempts/${container_name}.log"
    if [ -f "$log_file" ] && [ -s "$log_file" ]; then
        local attacker_ip=$(awk -F';' '{print $2}' "$log_file" | head -1)
        echo "$attacker_ip"
    else
        echo ""
    fi
}

# Function to remove existing container and rules
remove_existing() {
    echo "Removing existing container and rules for $container_name"

    # Get the current container IP (if it exists)
    local current_container_ip=$(sudo lxc-info -n $container_name -iH 2>/dev/null)

    # Get the attacker IP
    local attacker_ip=$(get_attacker_ip)

    # Remove iptables rules
    if [ -n "$attacker_ip" ]; then
        sudo iptables -w --table nat --delete PREROUTING --source "$attacker_ip" --destination "$external_ip" --jump DNAT --to-destination "$container_ip"
        sudo iptables -w --table nat --delete PREROUTING --source "$attacker_ip" --destination "$external_ip" --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port"
    fi

    if [ -n "$current_container_ip" ]; then
        sudo iptables -w -t nat -D PREROUTING -s 0.0.0.0/0 -d $external_ip -j DNAT --to-destination $current_container_ip 2>/dev/null
        sudo iptables -w -t nat -D POSTROUTING -s $current_container_ip -d 0.0.0.0/0 -j SNAT --to-source $external_ip 2>/dev/null
    fi
    sudo iptables -w -t nat -D PREROUTING -s 0.0.0.0/0 -d $external_ip -p tcp --dport 22 -j DNAT --to-destination "10.0.3.1:$mitm_port" 2>/dev/null
    sudo ip addr del $external_ip/$mask brd + dev eth3 2>/dev/null

    # Stop and delete the MITM process managed by PM2
    if sudo pm2 list | grep -q "$container_name"; then
        echo "Stopping MITM process for $container_name"
        sudo pm2 stop "$container_name"
        sudo pm2 delete "$container_name"
    fi

    # Stop and destroy the container
    sudo lxc-stop -n $container_name -k 2>/dev/null
    sudo lxc-destroy -n $container_name 2>/dev/null

    echo "Existing container, rules, and MITM removed."
}

# Function to create and set up container
create_container() {

    # Shuffle and pick a random banner
    banners=( "ethical" "legal" "technical" "none" )
    banners=( $(shuf -e "${banners[@]}") )

    # Get the banner and set new name for the container
    new_banner=${banners[0]}
    new_container_name="${date}_${new_banner}_${external_ip}"

    echo "Selected scenario for new container: $new_container_name"

    echo "Creating new container: $new_container_name"
    sudo lxc-create -t download -n $new_container_name -- -d ubuntu -r focal -a amd64
    sudo lxc-start -n $new_container_name
    sleep 10  # Wait for container to start

    # Get the new container IP
    container_ip=$(sudo lxc-info -n $new_container_name -iH)
    if [ -z "$container_ip" ]; then
        echo "Failed to obtain container IP. Exiting."
        exit 1
    fi
    echo "New container IP: $container_ip"
}

# Start MITM server
start_mitm() {
    echo "Starting MITM for $new_container_name"
    if sudo pm2 -l "./logs/${new_banner}/${new_container_name}" start MITM/mitm.js --name "$new_container_name" -- -n "$new_container_name" -i "$container_ip" -p $mitm_port --mitm-ip 10.0.3.1 --auto-access --auto-access-fixed 1 --debug --ssh-server-banner-file ./banners/${new_banner}.txt; then
        echo "MITM server started successfully"
    else
        echo "Failed to start MITM server"
        exit 1
    fi
}

# Function to set up networking
setup_networking() {
    # Ensure the network interface is up
    sudo ip link set eth3 up
    # Add the external IP to the network interface
    sudo ip addr add $external_ip/$mask brd + dev eth3

    # Set up NAT (Network Address Translation) rules
    # Redirect incoming traffic to the container
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --jump DNAT --to-destination $container_ip
    # Masquerade outgoing traffic from the container
    sudo iptables -w --table nat --insert POSTROUTING --source $container_ip --destination 0.0.0.0/0 --jump SNAT --to-source $external_ip
    # Redirect SSH traffic to the MITM server
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port" 

    # Enable IP forwarding
    sudo sysctl -w net.ipv4.ip_forward=1
}

# Function to set up firewall
setup_firewall() {
    echo "Setting up firewall for $new_container_name"
    sudo lxc-attach -n $new_container_name -- bash -c "apt update && apt install -y ufw"
    sudo lxc-attach -n $new_container_name -- bash -c "ufw allow 22/tcp && ufw --force enable"
}

# Function to set up honey files
setup_honey() {
    echo "Setting up honey files for $new_container_name"
    sudo lxc-attach -n $new_container_name -- bash -c "mkdir -p /opt/honey"
    sudo lxc-attach -n $new_container_name -- bash -c "echo 'Sensitive Data' > /opt/honey/secrets.txt"
    sudo lxc-attach -n $new_container_name -- bash -c "echo 'user:password' > /opt/honey/credentials.txt"
}

# Function to set up SSH
setup_ssh() {
    echo "Setting up SSH server $new_container_name"
    # Install SSH server if it's not already installed
    sudo lxc-attach -n $new_container_name -- bash -c "
        if ! dpkg -s openssh-server >/dev/null 2>&1; then
            apt-get update
            apt-get install -y openssh-server
        fi
    "
}

# Function to verify SSH banner and server status
verify_ssh_setup() {
    echo "Verifying SSH setup for $new_container_name"
    
    # Check if SSH server is installed and running
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
    "
}

# Main execution
remove_existing


create_container
setup_firewall
setup_ssh
verify_ssh_setup
start_mitm  # Start MITM before setting up networking
sleep 5  # Give MITM server time to start
setup_networking
setup_honey

sudo ./attacker_status.sh $container_name $container_ip $external_ip $mitm_port &

# sudo ./utils/tracker.sh "./logs/${new_banner}/${new_container_name}" $new_container_name $external_ip &

sudo echo "Container $container_name has been recycled successfully"

exit 0