#!/bin/sh
# Cycle the RGB LED through every color, 1 s each, until Ctrl-C.
# Turns the LED off on exit.   Usage:  sudo ./rgb_cycle.sh
# Set RGB to point at the rgb binary if it isn't next to this script.
 
RGB="${RGB:-$(dirname "$0")/rgb.py}"
 
cleanup() {
    "$RGB" off
    echo
    exit 0
}
trap cleanup INT TERM
 
while true; do
    for c in red yellow green cyan blue magenta white; do
        echo "$c"
        "$RGB" "$c"
        sleep 1
    done
done
 
