#!/bin/bash

# reset iptable rules
sudo iptables-restore /sysops/iptable_rules.txt

# stop PM2 process and kills all containers (and other stuff if needed)
sudo /sysops/delete.sh

# initialize default DIT Firewall Rules
sudo /sysops/firewall.sh

# our ips
ips=( "128.8.238.16" "128.8.238.41" "128.8.238.59" "128.8.238.191" )

# shuffle our ips (for randomization purposes)
ips=( $(shuf -e "${ips[@]}") )

# banner types
scenarios=( "ethical" "legal" "none" "technical" )

# enables IP forwarding & allows processes to communicate with local network
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.route_localnet=1

# create baseline template container
sudo DOWNLOAD_KEYSERVER="keyserver.ubuntu.com" lxc-create -n template -t download -- -d ubuntu -r focal -a amd64
sudo lxc-start -n template

# install and set up SSH in the template container
sudo lxc-attach -n template -- bash -c "
    if ! dpkg -s openssh-server >/dev/null 2>&1; then
        apt-get update
        apt-get install -y openssh-server
    fi
    systemctl enable ssh --now
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
    systemctl restart ssh
"

# verify SSH setup in the template container
sudo lxc-attach -n template -- bash -c "
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

# stop the template container
sudo lxc-stop -n template

# create honey containers
LEN=4
for ((i = 0 ; i < $LEN ; i++)):
do
    scenario=${scenarios[$i]}
    n="honey_${scenario}"

    sudo lxc-copy -n template -N $n
    sleep 10

    sudo lxc-stop -n $n
done
