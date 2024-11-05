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

# Set specific output directory
output_dir="/home/student/durations"
mkdir -p "$output_dir"

# Create/clear the long durations file
long_durations_file="$output_dir/long_durations.txt"
> "$long_durations_file"

# Process each subdirectory using a single awk script
for subdir in "$main_dir"/{legal,ethical,none,technical}; do
    if [ -d "$subdir" ]; then
        subdir_name=$(basename "$subdir")
        echo "Processing $subdir_name"

        find "$subdir" -type f -exec awk -v output_file="$output_dir/${subdir_name}.txt" -v long_file="$long_durations_file" -v subdir_name="$subdir_name" '
            /Attacker authenticated and is inside container/ {
                split($2, auth_time, ".")
                last_auth_timestamp = auth_time[1]
            }

            /Attacker closed connection/ {
                if (last_auth_timestamp != "") {
                    split($2, close_time, ".")
                    close_timestamp = close_time[1]

                    split(last_auth_timestamp, auth_parts, ":")
                    split(close_timestamp, close_parts, ":")

                    auth_seconds = auth_parts[1] * 3600 + auth_parts[2] * 60 + auth_parts[3]
                    close_seconds = close_parts[1] * 3600 + close_parts[2] * 60 + close_parts[3]

                    duration_seconds = close_seconds - auth_seconds

                    # Only process if duration is positive
                    if (duration_seconds > 0) {
                        minutes = int(duration_seconds / 60)
                        seconds = duration_seconds % 60
                        printf "%02d:%02d\n", minutes, seconds >> output_file

                        # If duration is over a minute, log the filename
                        if (minutes >= 1) {
                            printf "%s - %s: %02d:%02d\n", subdir_name, FILENAME, minutes, seconds >> long_file
                        }
                    }

                    # Reset the last_auth_timestamp after using it
                    last_auth_timestamp = ""
                }
            }
        ' {} \;

        echo "Output written to $output_dir/${subdir_name}.txt"
    fi
done

# Check if we found any long durations
if [ -s "$long_durations_file" ]; then
    echo -e "\nFiles with durations over 1 minute have been written to $long_durations_file"
else
    echo -e "\nNo files found with duration over 1 minute"
    rm "$long_durations_file"
fi