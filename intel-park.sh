#!/bin/bash

monitor_fun() {
    if ! STATE="$(busctl --system wait org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties PropertiesChanged | grep -m1 -oE "power-saver|balanced|performance")"; then
        printf "Failed to capture the power profile.\n"; return 1
    else
        printf "Power profile has changed.\n"; return 0
    fi
}

apply_park_fun() {
    printf "Readjusting parked CPU cores.\n"
    case $STATE in
        performance)
            if ! printf 'member\n' > $PARK_DIR/cpuset.cpus.partition; then
                return 1
            fi
            if ! printf '0-17\n' > $PARK_DIR/cpuset.cpus; then
                return 1
            fi
            if ! printf '0-17\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                return 1
            fi
            ;;
        balanced)
            if ! printf '0,1,2,5,8,9,10,11\n' > $PARK_DIR/cpuset.cpus; then
                return 1
            fi
            if ! printf '0,1,2,5,8,9,10,11\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                return 1
            fi
            if ! printf 'isolated\n' > $PARK_DIR/cpuset.cpus.partition; then
                return 1
            fi
            ;;
        power-saver)
            if ! printf '0-13\n' > $PARK_DIR/cpuset.cpus; then
                return 1
            fi
            if ! printf '0-13\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                return 1
            fi
            if ! printf 'isolated\n' > $PARK_DIR/cpuset.cpus.partition; then
                return 1
            fi
            ;;
    esac
    return 0
}

# ----- ENTRY POINT -----
PARK_DIR="/sys/fs/cgroup/parked-cores/"
if ! STATE="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile | grep -m1 -oE "power-saver|balanced|performance")"; then
    printf "Failed to capture power profile state when starting script.\n"; exit 1
fi
if ! mkdir -p "$PARK_DIR"; then
    printf "Failed to create $PARK_DIR\n"; exit 1
fi
while true; do
    if ! apply_park_fun; then
        exit 1
    fi
    if ! monitor_fun; then
        exit 1
    fi
done
