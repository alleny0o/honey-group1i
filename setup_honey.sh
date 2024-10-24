#!/bin/bash

print_usage() {
    echo "Usage: $0 <container_name>"
}

if [ $# -ne 1 ]; then
    print_usage
    exit 1
fi

container_name=$1

# Copy the existing student_files directory into the container
sudo cp -r /home/student/student_files "/var/lib/lxc/${container_name}/rootfs/root/"
    
# Set proper permissions inside the container
sudo lxc-attach -n "$container_name" -- bash -c '
    # Make root directory accessible
    chmod 755 /root
        
    # Ensure files are readable
    chmod 644 /root/student_files/*
        
    # Add access tracking
    touch /var/log/student_files_access.log
    chmod 600 /var/log/student_files_access.log
'

exit 0