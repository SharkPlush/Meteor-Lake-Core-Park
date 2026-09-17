#!/bin/bash
set -euo pipefail

monitor_fun() {
    local I REMAIN E_CODE=0
    while true; do
        case $POWER_MODE in
            1)
                REMAIN="$(( ROTATION_TIMER - SECONDS ))"
                if [ "$REMAIN" -le 0 ]; then
                    return 0
                fi
                I="$(timeout "$REMAIN" busctl --system wait org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties PropertiesChanged)" || E_CODE=$?
                ;;
            *)
                I="$(busctl --system wait org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties PropertiesChanged)" || E_CODE=$?
                ;;
        esac
        if [ "$E_CODE" = "124" ]; then
            return 0
        fi
        if [ "$E_CODE" -ne "0" ]; then
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
    case $POWER_STATE in
        balanced)
            case $BALANCED_ROTATE in
                0)
                    if ! printf '0,1,2,5,8,9,10,11\n' > $PARK_DIR/cpuset.cpus; then
                        return 1
                    fi
                    if ! printf '0,1,2,5,8,9,10,11\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                        return 1
                    fi
                    if ! printf 'isolated\n' > $PARK_DIR/cpuset.cpus.partition; then
                        return 1
                    fi
                    printf "Balanced rotation 1\n"
                    BALANCED_ROTATE="1"
                    ;;
                1)
                    if ! printf '3,4,6,7,12,13,14,15\n' > $PARK_DIR/cpuset.cpus; then
                        return 1
                    fi
                    if ! printf '3,4,6,7,12,13,14,15\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                        return 1
                    fi
                    if ! printf 'isolated\n' > $PARK_DIR/cpuset.cpus.partition; then
                        return 1
                    fi
                    printf "Balanced rotation 2\n"
                    BALANCED_ROTATE="0"
                    ;;
            esac
            POWER_MODE="1"; ROTATION_TIMER=$(( SECONDS + 1800 ))
            ;;
        power-saver)
            case $POWER_SAVER_ROTATE in
                0)
                    if ! printf '8,9,16,17\n' > $PARK_DIR/cpuset.cpus; then
                        return 1
                    fi
                    if ! printf '8,9,16,17\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                        return 1
                    fi
                    if ! printf 'isolated\n' > $PARK_DIR/cpuset.cpus.partition; then
                        return 1
                    fi
                    printf "Power-saver rotation 1\n"
                    POWER_SAVER_ROTATE="1"
                    ;;
                1)
                    if ! printf '10,11,16,17\n' > $PARK_DIR/cpuset.cpus; then
                        return 1
                    fi
                    if ! printf '10,11,16,17\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                        return 1
                    fi
                    if ! printf 'isolated\n' > $PARK_DIR/cpuset.cpus.partition; then
                        return 1
                    fi
                    printf "Power-saver rotation 2\n"
                    POWER_SAVER_ROTATE="2"
                    ;;
                2)
                    if ! printf '12,13,16,17\n' > $PARK_DIR/cpuset.cpus; then
                        return 1
                    fi
                    if ! printf '12,13,16,17\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                        return 1
                    fi
                    if ! printf 'isolated\n' > $PARK_DIR/cpuset.cpus.partition; then
                        return 1
                    fi
                    printf "Power-saver rotation 3\n"
                    POWER_SAVER_ROTATE="3"
                    ;;
                3)
                    if ! printf '14,15,16,17\n' > $PARK_DIR/cpuset.cpus; then
                        return 1
                    fi
                    if ! printf '14,15,16,17\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                        return 1
                    fi
                    if ! printf 'isolated\n' > $PARK_DIR/cpuset.cpus.partition; then
                        return 1
                    fi
                    printf "Power-saver rotation 4\n"
                    POWER_SAVER_ROTATE="0"
                    ;;
            esac
            POWER_MODE="1"; ROTATION_TIMER=$(( SECONDS + 1800 ))
            ;;
        *)
            if ! printf '0-17\n' > $PARK_DIR/cpuset.cpus; then
                return 1
            fi
            if ! printf '0-17\n' > $PARK_DIR/cpuset.cpus.exclusive; then
                return 1
            fi
            if ! printf 'member\n' > $PARK_DIR/cpuset.cpus.partition; then
                return 1
            fi
            POWER_MODE="0"
            ;;
    esac
    return 0
}

# ----- ENTRY POINT -----
POWER_MODE=""
BALANCED_ROTATE=$(( RANDOM % 2 ))
POWER_SAVER_ROTATE=$(( RANDOM % 4 ))
PARK_DIR="/sys/fs/cgroup/parked-cores"
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
