#!/bin/bash

# Set up log directory
mkdir -p /home/student/ignore_logs

# reset iptable rules
sudo iptables-restore /home/student/utils/iptables_reset.txt

# stop PM2 process and stop/destroy all containers (and other stuff if needed)
sudo /home/student/utils/delete.sh

# initialize default DIT Firewall Rules
sudo modprobe br_netfilter
sudo sysctl -p /etc/sysctl.conf
sudo /home/student/utils/firewall_rules.sh

# our ips
ips=( "128.8.238.16" "128.8.238.41" "128.8.238.59" "128.8.238.191" )

# shuffle our ips (for randomization purposes)
ips=( $(shuf -e "${ips[@]}") )

# banner types
banners=( "ethical" "legal" "none" "technical" )

# create baseline template container
sudo DOWNLOAD_KEYSERVER="keyserver.ubuntu.com" lxc-create -n template -t download -- -d ubuntu -r focal -a amd64
sudo lxc-start -n template

# MUST WAIT FOR CONTAINER TO START
if ! sudo /home/student/check_container.sh template; then
    echo "Failed to start container" >> /home/student/ignore_logs/init.log
    exit 1
fi

# TODO - Add Honey to Container
sudo /home/student/setup_honey.sh template

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
    date=$(date "+%F-%H-%M-%S")
    container_name="${date}_${banner}_${external_ip}"
    mask=24

    # create new container
    sudo lxc-copy -n template -N $container_name
    sudo lxc-start -n $container_name
    
    # MUST WAIT FOR CONTAINER TO START
    if ! sudo /home/student/check_container.sh $container_name; then
        echo "Failed to start container" >> /home/student/ignore_logs/init.log
        exit 1
    fi

    container_ip=$(sudo lxc-info -n $container_name -iH)

    mitm_port=$(sudo cat /home/student/ports/${external_ip}_port.txt)

    # set up MITM server
    if sudo pm2 -l "/home/student/logs/${banner}/${container_name}" start /home/student/MITM/mitm.js --name "$container_name" -- -n "$container_name" -i "$container_ip" -p $mitm_port --mitm-ip 10.0.3.1 --auto-access --auto-access-fixed 1 --debug --ssh-server-banner-file /home/student/banners/${banner}.txt; then
        echo "MITM server started successfully" >> /home/student/ignore_logs/init.log
    else
        echo "Failed to start MITM server" >> /home/student/ignore_logs/init.log
        exit 1
    fi

    # Wait for MITM server to start
    if sudo /home/student/check_mitm.sh $container_name $mitm_port; then
        echo "MITM server started successfully" >> /home/student/ignore_logs/init.log
    else
        echo "Failed to start MITM server" >> /home/student/ignore_logs/init.log
        exit 1
    fi

    # set up network interface
    sudo ip link set eth3 up
    sudo ip addr add $external_ip/$mask brd + dev eth3

    # set up NAT rules
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --jump DNAT --to-destination $container_ip
    sudo iptables -w --table nat --insert POSTROUTING --source $container_ip --destination 0.0.0.0/0 --jump SNAT --to-source $external_ip
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port" 
    sudo sysctl -w net.ipv4.ip_forward=1

    sudo /home/student/attacker_status.sh $container_name $container_ip $external_ip $mitm_port & disown

    # sudo /home/student/utils/tracker.sh "/home/student/logs/${banner}/${container_name}" $container_name $external_ip &

done

sudo lxc-destroy -n template

exit 0