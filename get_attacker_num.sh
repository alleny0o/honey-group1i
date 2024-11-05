#!/bin/bash

# Check if directory argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <directory_path>"
    exit 1
fi

main_dir="$1"

# Check if directory exists
if [ ! -d "$main_dir" ]; then
    echo "Error: Directory $main_dir does not exist"
    exit 1
fi

# Process each subdirectory
for subdir in "$main_dir"/{legal,ethical,none,technical}; do
    if [ -d "$subdir" ]; then
        count=$(find "$subdir" -type f | wc -l)
        echo "$(basename "$subdir"): $count files"
    fi
done