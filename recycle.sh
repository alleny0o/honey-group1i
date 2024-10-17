#!/bin/bash

# Function to print usage information
print_usage() {
    echo "Usage: $0 <container_name> <container_ip> <external_ip> <port>"
}

# Check if correct number of arguments are provided
if [ $# -ne 4 ]; then
    print_usage
    exit 1
fi

# Assign arguments to variables
container_name=$1
container_ip=$2
external_ip=$3
port=$4

# Function to remove existing container and rules
remove_existing() {
    echo "Removing existing container and rules for $container_name"
    
    # Remove iptables rules
    sudo iptables -t nat -D PREROUTING -d $external_ip -p tcp --dport $port -j DNAT --to-destination 127.0.0.1:8080 2>/dev/null
    sudo iptables -t nat -D PREROUTING -d 127.0.0.1 -p tcp --dport 8080 -j DNAT --to-destination $container_ip:22 2>/dev/null
    sudo iptables -t nat -D PREROUTING -d $external_ip -j DNAT --to-destination $container_ip 2>/dev/null
    sudo iptables -t nat -D POSTROUTING -s $container_ip -j SNAT --to-source $external_ip 2>/dev/null
    
    # Stop and destroy the container
    sudo lxc-stop -n $container_name -k 2>/dev/null
    sudo lxc-destroy -n $container_name 2>/dev/null


    mitm_pid=$(sudo cat /var/run/mitm_$container_name.pid)
    echo "Killing MITM process with PID $mitm_pid"
    sudo kill -9 $mitm_pid 2>/dev/null
    sudo rm /var/run/mitm_$container_name.pid

    echo "Existing container and rules and MITM removed."
}


# Function to create and set up container
create_container() {
    echo "Creating new container: $container_name"
    sudo lxc-create -t download -n $container_name -- -d ubuntu -r focal -a amd64
    sudo lxc-start -n $container_name
    sleep 10  # Wait for container to start
}

# Function to start MITM
start_mitm() {

    echo "Starting MITM for $container_name"
    sudo bash -c "node MITM/mitm.js -n '$container_name' -i '$container_ip' -p 8080 --auto-access --auto-access-fixed 1 --debug --ssh-server-banner-file ./banners/${container_name}.txt & echo \$! > /var/run/mitm_$container_name.pid"
    mitm_pid=$(sudo cat /var/run/mitm_$container_name.pid)
    echo "MITM server started with PID $mitm_pid for $container_name"
    sleep 5 
}

# Function to set up networking
setup_networking() {
    echo "Setting up networking for $container_name"
    sudo lxc-attach -n $container_name -- bash -c "ip addr add $container_ip/24 dev eth0"
    
    # MITM rules for SSH (assuming MITM listens on port 8080)
    sudo iptables -t nat -I PREROUTING 1 -d $external_ip -p tcp --dport $port -j DNAT --to-destination 127.0.0.1:8080
    sudo iptables -t nat -A PREROUTING -d 127.0.0.1 -p tcp --dport 8080 -j DNAT --to-destination $container_ip:22
    
    # General rules for other traffic
    sudo iptables -t nat -A PREROUTING -d $external_ip -j DNAT --to-destination $container_ip
    sudo iptables -t nat -A POSTROUTING -s $container_ip -j SNAT --to-source $external_ip
    sudo sysctl -w net.ipv4.ip_forward=1
    sudo sysctl -w net.ipv4.conf.all.route_localnet=1
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
setup_networking
setup_honey

sudo echo "Container $container_name has been recycled successfully with scenario: $scenario"

# Log the recycling operation
sudo echo "$(date '+%Y-%m-%d %H:%M:%S'): Recycled container $container_name with scenario $scenario" >> /var/log/honeypot_recycling.log