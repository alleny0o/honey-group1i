#!/bin/bash

# kill processes
for i in $(sudo ps -e | grep attacker_status.sh | awk '{print $1}'); do sudo kill $i; done
for i in $(sudo ps -e | grep timer.sh | awk '{print $1}'); do sudo kill $i; done

#sudo forever stopall
sudo pm2 stop all
sudo pm2 delete all

# kill containers
for i in $(sudo lxc-ls); do sudo lxc-stop $i; done
for i in $(sudo lxc-ls); do sudo lxc-destroy $i -f; done