#!/bin/bash

if [ $# -ne 3 ]
then
	echo "Usage: ./tracker.sh [container log file] [container name] [external_ip]"
fi 

file=$1
container=$2
external_ip=$3

while sudo inotifywait -e modify $file; do
	if cat $1 | grep "Attacker closed connection" -q; then
		echo "*******************************************************************"
		echo "			TRIGGERING RECYCLE SCRIPT"
		echo "*******************************************************************"
		echo "`date "+%F-%H-%M-%S"`: Triggering recycle script on container $container"
		sudo /home/student/recycle.sh $container $external_ip
		exit 0
	fi
done