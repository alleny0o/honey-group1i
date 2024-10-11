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

    # Stop and delete PM2 process if it exists
    sudo pm2 stop $container_name 2>/dev/null
    sudo pm2 delete $container_name 2>/dev/null
    
    # Remove iptables rules
    sudo iptables -t nat -D PREROUTING -d $external_ip -p tcp --dport $port -j DNAT --to-destination 127.0.0.1:8080 2>/dev/null
    sudo iptables -t nat -D PREROUTING -d 127.0.0.1 -p tcp --dport 8080 -j DNAT --to-destination $container_ip:22 2>/dev/null
    sudo iptables -t nat -D PREROUTING -d $external_ip -j DNAT --to-destination $container_ip 2>/dev/null
    sudo iptables -t nat -D POSTROUTING -s $container_ip -j SNAT --to-source $external_ip 2>/dev/null
    
    # Stop and destroy the container
    sudo lxc-stop -n $container_name -k 2>/dev/null
    sudo lxc-destroy -n $container_name 2>/dev/null
    
    echo "Existing container and rules removed."
}

# Function to randomly select a scenario
select_random_scenario() {
    scenarios=("legal" "ethical" "technical" "none")
    selected_scenario=${scenarios[$RANDOM % ${#scenarios[@]}]}
    echo $selected_scenario
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
    echo "Starting MITM with PM2"
    sudo pm2 start /home/student/MITM/mitm.js --name "$container_name" -- -n "$container_name" -i "$container_ip" -p 8080 --auto-access --auto-access-fixed 1 --debug --ssh-server-banner-file "/tmp/${container_name}_banner.txt"
    sleep 5  # Give MITM some time to start up
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

# Function to set up SSH banner
setup_ssh_and_banner() {
    local scenario=$1
    local banner_text=""
    case $scenario in
        legal)
            banner_text="WARNING: Unauthorized access is prohibited and will be prosecuted to the fullest extent of the law."
            ;;
        ethical)
            banner_text="NOTICE: This system is for authorized users only. If you are not authorized, please disconnect immediately."
            ;;
        technical)
            banner_text="SYSTEM INFO: Ubuntu 20.04 LTS - Kernel $(uname -r) - All connections are monitored and recorded."
            ;;
        none)
            banner_text=""
            ;;
    esac

    echo "Setting up SSH server and banner for $container_name"
    
    # Install SSH server if it's not already installed
    sudo lxc-attach -n $container_name -- bash -c "
        if ! dpkg -s openssh-server >/dev/null 2>&1; then
            apt-get update
            apt-get install -y openssh-server
        fi
    "

    if [ -n "$banner_text" ]; then
        echo "$banner_text" | sudo tee /tmp/${container_name}_banner.txt
        sudo lxc-attach -n $container_name -- bash -c "
            echo 'Banner /etc/ssh/sshd-banner' >> /etc/ssh/sshd_config
            systemctl enable ssh
            systemctl restart ssh
        "
    fi
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
    
    # Check if the banner file exists
    sudo lxc-attach -n $container_name -- bash -c "
        if [ -f /etc/ssh/sshd-banner ]; then
            echo 'Banner file exists'
            echo 'Banner contents:'
            cat /etc/ssh/sshd-banner
        else
            echo 'Banner file not found'
        fi
    "
    
    # Check if the Banner directive is in sshd_config
    echo "Checking sshd_config for Banner directive:"
    sudo lxc-attach -n $container_name -- bash -c "grep Banner /etc/ssh/sshd_config"
}

# Main execution
remove_existing
scenario=$(select_random_scenario)
echo "Selected scenario for new container: $scenario"

create_container
start_mitm  # Start MITM before setting up networking
setup_networking
setup_firewall
setup_honey
setup_ssh_and_banner "$scenario"
verify_ssh_setup

echo "Container $container_name has been recycled successfully with scenario: $scenario"

# Log the recycling operation
echo "$(date '+%Y-%m-%d %H:%M:%S'): Recycled container $container_name with scenario $scenario" >> /var/log/honeypot_recycling.log