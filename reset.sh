#!/bin/bash

# reset iptable rules
sudo iptables-restore ./utils/iptables_reset.txt

# stop PM2 process and stop/destroy all containers (and other stuff if needed)
sudo ./utils/delete.sh