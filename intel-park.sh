#!/bin/bash
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
        printf 'P cores have been parked for '$POWER_STATE' mode.\n'
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
        printf 'Allowing all cores for '$POWER_STATE' mode.\n'
    fi
    return 0
}

# ----- ENTRY POINT -----
CPU_GEN="$(awk '/^model\t/{print $3;exit}' /proc/cpuinfo)"

case $CPU_GEN in
    151|154|183|186|191|170|172)
        printf 'Supported CPU found.\n'
        ;;
    *)
        printf 'Your CPU is not supported.\n'
        exit 2
        ;;
esac

P_CORES="$(< /sys/devices/cpu_core/cpus)"
A_CORES="$(< /sys/devices/system/cpu/present)"
BUSCTL_OUT=""
POWER_STATE=""
trap 'POWER_STATE="performance"; apply_park_fun' EXIT

if ! printf '+cpuset\n' > /sys/fs/cgroup/cgroup.subtree_control; then
    printf "Failed to add +cpuset to cgroup.subtree_control\n"
    exit 1
fi
if ! mkdir -p '/sys/fs/cgroup/parked-cores'; then
    printf "Failed to create '/sys/fs/cgroup/parked-cores'\n"
    exit 1
fi
if ! POWER_STATE="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile | grep -m1 -oE "power-saver|balanced|performance")"; then
    printf 'Failed to capture power profile state when starting script.\n'
    exit 1
fi
if ! apply_park_fun; then
     printf 'Failed to adjust parked CPU cores.\n'
     exit 1
fi

while true; do
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
