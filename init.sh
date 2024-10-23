#!/bin/bash

# reset everything
sudo ./reset.sh

# initialize default DIT Firewall Rules
sudo ./utils/firewall_rules.sh

# our ips
ips=( "128.8.238.16" "128.8.238.41" "128.8.238.59" "128.8.238.191" )

# shuffle our ips (for randomization purposes)
ips=( $(shuf -e "${ips[@]}") )

# banner types
banners=( "ethical" "legal" "none" "technical" )

# create baseline template container
sudo DOWNLOAD_KEYSERVER="keyserver.ubuntu.com" lxc-create -n template -t download -- -d ubuntu -r focal -a amd64
sudo lxc-start -n template

# TODO: set up honey files in template container

# set up firewall
sudo lxc-attach -n template -- bash -c "apt update && apt install -y ufw"
sudo lxc-attach -n template -- bash -c "ufw allow 22/tcp && ufw --force enable"

# install, set up, and verify SSH in  template container
sudo lxc-attach -n template -- bash -c "
    if ! dpkg -s openssh-server >/dev/null 2>&1; then
        apt-get update
        apt-get install -y openssh-server
    fi
"
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

# initialize honey containers by looping
LENGTH=4
for ((i = 0 ; i < $LENGTH ; i++));
do

    # extract variables for container
    external_ip=${ips[$i]}
    banner=${banners[$i]}
    container_name="${banner}_${external_ip}"
    date=$(date "+%F-%H-%M-%S")
    mask=24

    sudo lxc-copy -n template -N $container_name
    sudo lxc-start -n $container_name
    sleep 10

    container_ip=$(sudo lxc-info -n $container_name -iH)

    mitm_port=$(sudo cat ./ports/${external_ip}_port.txt)

    # set up MITM server
    if sudo pm2 -l "./logs/${banner}/${date}_${container_name}" start MITM/mitm.js --name "$container_name" -- -n "$container_name" -i "$container_ip" -p $mitm_port --mitm-ip 10.0.3.1 --auto-access --auto-access-fixed 1 --debug --ssh-server-banner-file ./banners/${banner}.txt; then
        echo "MITM server started successfully"
    else
        echo "Failed to start MITM server"
        exit 1
    fi

    sleep 5

    # set up network interface
    sudo ip link set eth3 up
    sudo ip addr add $external_ip/$mask brd + dev eth3

    # set up NAT rules
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --jump DNAT --to-destination $container_ip
    sudo iptables -w --table nat --insert POSTROUTING --source $container_ip --destination 0.0.0.0/0 --jump SNAT --to-source $external_ip
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port" 
    sudo sysctl -w net.ipv4.ip_forward=1

    sudo ./utils/tracker.sh "./logs/${banner}/${date}_${container_name}" $container_name $external_ip &

done

sudo lxc-destroy -n template

exit 0
