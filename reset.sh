#!/bin/bash

# reset iptable rules
sudo iptables-restore /home/student/utils/iptables_reset.txt

# stop PM2 process and stop/destroy all containers (and other stuff if needed)
sudo /home/student/utils/delete.sh

exit 0