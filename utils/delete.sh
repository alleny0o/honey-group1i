# kill the tracker.sh and inotifywait processes
for i in $(sudo ps -e | grep tracker.sh | awk '{print $1}'); do sudo kill $i; done
for i in $(sudo ps -e | grep inotifywait | awk '{print $1}'); do sudo kill $i; done

# kill the timer.sh process
for i in $(sudo ps -e | grep timer.sh | awk '{print $1}'); do sudo kill $i; done

# kill the attacker_status.sh process
for i in $(sudo ps -e | grep attacker_status.sh | awk '{print $1}'); do sudo kill $i; done

# stop all pm2 processes
sudo pm2 stop all
# remove all pm2 processes
sudo pm2 delete all

# kill containers
for i in $(sudo lxc-ls); do sudo lxc-stop -n $i; done
for i in $(sudo lxc-ls); do sudo lxc-destroy -n $i -f; done

