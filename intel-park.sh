#!/bin/bash
# Created by SharkPlush on GitHub
# https://github.com/SharkPlush
# Copyright 2026 SharkPlush
# Licensed under PolyForm Noncommercial License 1.0.0
# Full license: https://github.com/SharkPlush/Tunedppd-Intel-Core-Parking/blob/main/LICENSE
# Report any issues to github.com/SharkPlush/Tunedppd-Intel-Core-Parking/issues

# I left comments for anyone who is curious how this works.
# If you want to control how the balanced power mode works read the comments.

set -euo pipefail

apply_park_fun() {
    if [ "$POWER_STATE" = "power-saver" ]; then
        if ! printf '%s' "$P_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
            return 1
        fi
        if ! printf '%s' "$P_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus.exclusive; then
            return 1
        fi
        if ! printf 'isolated' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
            return 1
        fi
    else
        if ! printf 'member' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
            return 1
        fi
        if ! printf '%s' "$A_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
            return 1
        fi
        if ! printf '%s' "$A_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus.exclusive; then
            return 1
        fi
    fi
    return 0
}

# --- ENTRY POINT ---
touch "/tmp/intel-park.lock"

# Check for supported CPU
CPU_GEN="$(awk '/^model\t/{print $3;exit}' /proc/cpuinfo)"
case $CPU_GEN in
    151|154|183|186|191|170|172)
        printf 'Supported CPU found.\n'
        ;;
    *)
        printf 'Your CPU is not supported.\n'
        rm "/tmp/intel-park.lock"
        exit 2
        ;;
esac

# We don't ever park E and LPE cores so we don't need to find them individually.
# Parking E cores causes power inefficency and parking LPE cores is just not a good idea.
P_CORES="$(< /sys/devices/cpu_core/cpus)"
A_CORES="$(< /sys/devices/system/cpu/present)"

BUSCTL_OUT=""
POWER_STATE=""

# Allows us to actually enable core parking.
if ! printf '+cpuset\n' > /sys/fs/cgroup/cgroup.subtree_control; then
    printf "Failed to add +cpuset to cgroup.subtree_control\n Is your kernel 6.7 or newer?\n"
    rm "/tmp/intel-park.lock"
    exit 1
fi
if ! mkdir -p '/sys/fs/cgroup/parked-cores'; then
    printf "Failed to create '/sys/fs/cgroup/parked-cores'\n"
    rm "/tmp/intel-park.lock"
    exit 1
fi

# If the script exits allow all the cores.
trap 'rm "/tmp/intel-park.lock"; POWER_STATE="performance"; apply_park_fun' EXIT

# Before the main loop we should know the current power state the device is in and apply for that.
if ! POWER_STATE="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile | grep -m1 -oE "power-saver|balanced|performance")"; then
    printf 'Failed to capture power profile state when starting script.\n'
    exit 1
fi
if ! apply_park_fun; then
     printf 'Failed to adjust parked CPU cores.\n'
     exit 1
fi

while true; do
    # busctl listens for a power state changed.
    # Becauuse this is a listener and not polling extra battery won't be wasted.
    if ! BUSCTL_OUT="$(busctl --system wait org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties PropertiesChanged)"; then
        printf "Failed to start busctl listener.\n"
        exit 1
    fi
    grep -q "ActiveProfile" <<<"$BUSCTL_OUT" || continue

    if ! POWER_STATE="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile | grep -m1 -oE "power-saver|balanced|performance")"; then
        printf "Failed to capture power profile state.\n"
        exit 1
    fi

    if ! apply_park_fun; then
         printf "Failed to adjust parked CPU cores.\n"
         exit 1
    fi
done
