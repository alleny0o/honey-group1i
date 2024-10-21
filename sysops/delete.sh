# stop all pm2 processes
sudo pm2 stop all
# remove all pm2 processes
sudo pm2 delete all

# kill containers
for i in $(sudo lxc-ls); do sudo lxc-stop -n $i; done
for i in $(sudo lxc-ls); do sudo lxc-destroy -n $i -f; done