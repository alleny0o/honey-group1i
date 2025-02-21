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
date=$(date "+%F-%H-%M-%S")

# Function to get the MITM port for each container
get_mitm_port() {
    case "$container_name" in
        "ethical") echo "8080" ;;
        "legal") echo "8082" ;;
        "technical") echo "8084" ;;
        "none") echo "8086" ;;
        *) echo "8080" ;; # Default to 8080 if container name doesn't match
    esac
}

# Get the MITM port
mitm_port=$(get_mitm_port)

# Function to remove existing container and rules
remove_existing() {
    echo "Removing existing container and rules for $container_name"

    # Get the current container IP (if it exists)
    local current_container_ip=$(sudo lxc-info -n $container_name -iH 2>/dev/null)

    # Remove iptables rules
    if [ -n "$current_container_ip" ]; then
        sudo iptables -w -t nat -D PREROUTING -s 0.0.0.0/0 -d $external_ip -j DNAT --to-destination $current_container_ip 2>/dev/null
        sudo iptables -w -t nat -D POSTROUTING -s $current_container_ip -d 0.0.0.0/0 -j SNAT --to-source $external_ip 2>/dev/null
    fi
    sudo iptables -w -t nat -D PREROUTING -s 0.0.0.0/0 -d $external_ip -p tcp --dport 22 -j DNAT --to-destination "10.0.3.1:$mitm_port" 2>/dev/null
    sudo ip addr del $external_ip/24 dev eth3 2>/dev/null

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
    echo "Creating new container: $container_name"
    sudo lxc-create -t download -n $container_name -- -d ubuntu -r focal -a amd64
    sudo lxc-start -n $container_name
    sleep 10  # Wait for container to start

    # Get the new container IP
    container_ip=$(sudo lxc-info -n $container_name -iH)
    if [ -z "$container_ip" ]; then
        echo "Failed to obtain container IP. Exiting."
        exit 1
    fi
    echo "New container IP: $container_ip"
}

# Start MITM server
start_mitm() {
    echo "Starting MITM for $container_name"
    if sudo pm2 -l "./logs/$container_name/$date" start MITM/mitm.js --name "$container_name" -- -n "$container_name" -i "$container_ip" -p $mitm_port --mitm-ip 10.0.3.1 --auto-access --auto-access-fixed 1 --debug --ssh-server-banner-file ./banners/${container_name}.txt; then
        echo "MITM server started successfully"
    else
        echo "Failed to start MITM server"
        exit 1
    fi
}

# Function to set up networking
setup_networking() {
    sudo ./utils/firewall_rules.sh
    # Ensure the network interface is up
    sudo ip link set eth3 up
    # Add the external IP to the network interface
    sudo ip addr add $external_ip/24 brd + dev eth3

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
    echo "Setting up firewall for $container_name"
    sudo lxc-attach -n $container_name -- bash -c "apt update && apt install -y ufw"
    sudo lxc-attach -n $container_name -- bash -c "ufw allow 22/tcp && ufw --force enable"
}

# Function to set up honey files
setup_honey() {
    echo "Setting up honey files for $container_name"
    sudo lxc-attach -n $container_name -- bash -c "mkdir -p /opt/honey"
    sudo lxc-attach -n $container_name -- bash -c "echo 'Sensitive Data' > /opt/honey/secrets.txt"
    sudo lxc-attach -n $container_name -- bash -c "echo 'user:password' > /opt/honey/credentials.txt"
}

# Function to set up SSH
setup_ssh() {
    echo "Setting up SSH server $container_name"
    # Install SSH server if it's not already installed
    sudo lxc-attach -n $container_name -- bash -c "
        if ! dpkg -s openssh-server >/dev/null 2>&1; then
            apt-get update
            apt-get install -y openssh-server
        fi
    "
}

# Function to verify SSH banner and server status
verify_ssh_setup() {
    echo "Verifying SSH setup for $container_name"
    
    # Check if SSH server is installed and running
    sudo lxc-attach -n $container_name -- bash -c "
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
echo "Selected scenario for new container: $container_name"

create_container
setup_firewall
setup_ssh
verify_ssh_setup
start_mitm  # Start MITM before setting up networking
sleep 5  # Give MITM server time to start
setup_networking
setup_honey

sudo ./utils/tracker.sh ./logs/$container_name/$date $container_name $external_ip &

sudo echo "Container $container_name has been recycled successfully"