#!/bin/bash
set -euo pipefail

monitor_fun() {
    local I E_CODE=0
    while true; do
        if ! I="$(busctl --system wait org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties PropertiesChanged)"; then
            printf "Failed to start busctl listener.\n"
            return 1
        fi
        grep -q "ActiveProfile" <<<"$I" || continue
        if ! POWER_STATE="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile | grep -m1 -oE "power-saver|balanced|performance")"; then
            printf "Failed to capture power profile state.\n"
            return 1
        fi
        break
    done
    return 0
}

apply_park_fun() {
    printf "Readjusting parked CPU cores.\n"
    if [ "$POWER_STATE" = "power-saver" ]; then
        if ! printf '0-7\n' > $PARK_DIR/cpuset.cpus; then
            return 1
        fi
        if ! printf '0-7\n' > $PARK_DIR/cpuset.cpus.exclusive; then
            return 1
        fi
        if ! printf 'isolated\n' > $PARK_DIR/cpuset.cpus.partition; then
            return 1
        fi
        printf "Power-saver\n"
        ;;
    else
        if ! printf '0-17\n' > $PARK_DIR/cpuset.cpus; then
            return 1
        fi
        if ! printf '0-17\n' > $PARK_DIR/cpuset.cpus.exclusive; then
            return 1
        fi
        if ! printf 'member\n' > $PARK_DIR/cpuset.cpus.partition; then
            return 1
        fi
        printf "Performance\n"
    fi
    return 0
}

# ----- ENTRY POINT -----
PARK_DIR="/sys/fs/cgroup/parked-cores"
trap 'POWER_STATE="power-saver"; apply_park_fun' EXIT
if ! printf '+cpuset\n' > /sys/fs/cgroup/cgroup.subtree_control; then
    printf "Failed to add +cpuset to cgroup.subtree_control\n"
    exit 1
fi
if ! mkdir -p "$PARK_DIR"; then
    printf "Failed to create $PARK_DIR\n"
    exit 1
fi
if ! POWER_STATE="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile | grep -m1 -oE "power-saver|balanced|performance")"; then
    printf "Failed to capture power profile state when starting script.\n"
    exit 1
fi
while true; do
    if ! apply_park_fun; then
        printf "Failed to adjust parked CPU cores.\n"
        exit 1
    fi
    if ! monitor_fun; then
        exit 1
    fi
done
