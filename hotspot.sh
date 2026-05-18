#!/bin/bash

SSID="DIRECT-XYA1LKJWUI_198"
CON_NAME="the-hotspot"
BAND="bg"  # default: 2.4GHz (bg=2.4GHz, a=5GHz)
CHANNEL="6"
WIFI_IFACE=""
IFACE_OVERRIDE=""

# Helper function: Generate a mobile-friendly WPA password.
generate_password() {
    tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom | head -c 16
    echo
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_wifi_iface() {
    local PROFILE_IFACE
    PROFILE_IFACE=$(nmcli -g connection.interface-name connection show "$CON_NAME" 2>/dev/null || true)

    if [ -n "$PROFILE_IFACE" ] && nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: -v dev="$PROFILE_IFACE" '$1==dev && $2=="wifi" {found=1} END {exit !found}'; then
        echo "$PROFILE_IFACE"
        return
    fi

    nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi" {print $1; exit}'
}

require_wifi_iface() {
    WIFI_IFACE="${IFACE_OVERRIDE:-$(detect_wifi_iface)}"
    if [ -z "$WIFI_IFACE" ]; then
        echo "Error: No Wi-Fi interface detected! Please make sure your Wi-Fi adapter is present and managed by NetworkManager."
        exit 1
    fi
}

hotspot_is_active() {
    nmcli -t -f NAME connection show --active 2>/dev/null | grep -Fxq "$CON_NAME"
}

active_ap_iface() {
    local AP_IFACE
    AP_IFACE=$(nmcli -g GENERAL.IP-IFACE connection show "$CON_NAME" 2>/dev/null || true)
    if [ -z "$AP_IFACE" ]; then
        AP_IFACE=$(nmcli -g connection.interface-name connection show "$CON_NAME" 2>/dev/null || true)
    fi
    echo "${AP_IFACE:-$WIFI_IFACE}"
}

apply_hotspot_profile() {
    local WIFI_PASS="$1"

    sudo nmcli connection modify "$CON_NAME" \
        connection.interface-name "$WIFI_IFACE" \
        802-11-wireless.ssid "$SSID" \
        802-11-wireless.mode ap \
        802-11-wireless.band "$BAND" \
        802-11-wireless.channel "$CHANNEL" \
        802-11-wireless.powersave 2 \
        ipv4.method shared \
        ipv6.method ignore \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.proto rsn \
        wifi-sec.pairwise ccmp \
        wifi-sec.group ccmp \
        wifi-sec.pmf 1

    if [ -n "$WIFI_PASS" ]; then
        sudo nmcli connection modify "$CON_NAME" wifi-sec.psk "$WIFI_PASS"
    fi
}

disable_wifi_powersave() {
    if command_exists iw; then
        sudo iw dev "$WIFI_IFACE" set power_save off >/dev/null 2>&1 || true
    fi
}

# Function: Start or create the hotspot
start_hotspot() {
    require_wifi_iface

    # Check if the connection profile already exists
    if nmcli connection show "$CON_NAME" > /dev/null 2>&1; then
        echo "Starting existing hotspot profile '$CON_NAME'..."
        if [ -z "${CUSTOM_PASS:-}" ]; then
            echo "Keeping existing hotspot password unchanged."
        fi
        apply_hotspot_profile "${CUSTOM_PASS:-}"
        sudo nmcli connection up "$CON_NAME"
        disable_wifi_powersave
    else
        echo "Creating new hotspot profile '$CON_NAME'..."
        local WIFI_PASS=${CUSTOM_PASS:-$(generate_password)}
        
        sudo nmcli connection add type wifi ifname "$WIFI_IFACE" con-name "$CON_NAME" autoconnect no ssid "$SSID"
        apply_hotspot_profile "$WIFI_PASS"
        sudo nmcli connection up "$CON_NAME"
        disable_wifi_powersave
        
        echo "----------------------------------------"
        echo "Hotspot Created and Started!"
        echo "SSID: $SSID"
        echo "Password: $WIFI_PASS"
        echo "----------------------------------------"
    fi
}

# Function: Stop the hotspot
stop_hotspot() {
    echo "Stopping hotspot '$CON_NAME'..."
    sudo nmcli connection down "$CON_NAME" 2>/dev/null || echo "Hotspot is not currently active."
}

# Function: Restart the hotspot without resetting the USB/Wi-Fi driver
restart_hotspot() {
    stop_hotspot
    sleep 2
    start_hotspot
}

# Function: Get hotspot status and current credentials
status_hotspot() {
    echo "--- Hotspot Status ---"
    if hotspot_is_active; then
        echo "State:    RUNNING"
    elif nmcli connection show "$CON_NAME" > /dev/null 2>&1; then
        echo "State:    STOPPED (Profile exists)"
    else
        echo "State:    NOT CREATED (Run 'start' to create)"
        return
    fi
    
    # Extract current password (requires sudo to read secrets)
    local CUR_PASS=$(sudo nmcli -s -g 802-11-wireless-security.psk connection show "$CON_NAME")
    local CUR_BAND=$(nmcli -g 802-11-wireless.band connection show "$CON_NAME")
    local CUR_CHANNEL=$(nmcli -g 802-11-wireless.channel connection show "$CON_NAME")
    local AP_IFACE
    AP_IFACE=$(active_ap_iface)
    local BAND_LABEL
    case "$CUR_BAND" in
        a)  BAND_LABEL="5 GHz" ;;
        bg) BAND_LABEL="2.4 GHz" ;;
        *)  BAND_LABEL="${CUR_BAND:-unknown}" ;;
    esac

    echo "SSID:     $(nmcli -g 802-11-wireless.ssid connection show "$CON_NAME")"
    echo "Password: $CUR_PASS"
    echo "Band:     $BAND_LABEL"
    echo "Channel:  ${CUR_CHANNEL:-auto}"
    echo "Interface: $AP_IFACE"

    if command_exists iw && [ -n "$AP_IFACE" ]; then
        local IW_INFO
        IW_INFO=$(iw dev "$AP_IFACE" info 2>/dev/null || true)
        if [ -n "$IW_INFO" ]; then
            echo "Wi-Fi:    $(echo "$IW_INFO" | awk '/type / {type=$2} /channel / {sub(/^[ \t]+/, ""); channel=$0} END {printf "type=%s, %s", type, channel}')"
            echo "Stations: $(iw dev "$AP_IFACE" station dump 2>/dev/null | awk '/^Station / {count++} END {print count+0}')"
        fi
    fi
    echo "----------------------"

    # QR code for quick connect (WIFI:T:WPA;S:<ssid>;P:<pass>;H:true;;)
    if command -v qrencode &>/dev/null; then
        echo ""
        qrencode -t ANSI -s 1 "WIFI:T:WPA;S:${SSID};P:${CUR_PASS};;"
    fi
}

# Function: Show connected devices
devices_hotspot() {
    if ! hotspot_is_active; then
        echo "Hotspot is not currently active."
        return
    fi
    local AP_IFACE
    AP_IFACE=$(nmcli -g GENERAL.IP-IFACE connection show "$CON_NAME")
    local LEASE_FILE="/var/lib/NetworkManager/dnsmasq-${AP_IFACE}.leases"

    echo "--- Connected Devices ---"
    printf "%-16s  %-19s  %s\n" "IP" "MAC" "Name"
    printf "%-16s  %-19s  %s\n" "---" "---" "----"
    sudo awk '{name=($4=="*"?"unknown":$4); printf "%-16s  %-19s  %s\n", $3, $2, name}' "$LEASE_FILE" 2>/dev/null \
        || echo "(could not read lease file)"
    echo "-------------------------"
}

# Function: Regenerate password and update the profile
regen_password() {
    if ! nmcli connection show "$CON_NAME" > /dev/null 2>&1; then
        echo "Error: Hotspot profile '$CON_NAME' does not exist yet. Run 'start' first."
        exit 1
    fi
    
    local NEW_PASS=${CUSTOM_PASS:-$(generate_password)}
    echo "Generating new password..."
    
    # Update the password in NetworkManager
    sudo nmcli connection modify "$CON_NAME" wifi-sec.psk "$NEW_PASS"
    echo "New Password set to: $NEW_PASS"
    
    # If the hotspot is currently running, restart it to apply the new password
    if hotspot_is_active; then
        echo "Restarting hotspot to apply new password..."
        restart_hotspot
    else
        echo "Hotspot is currently stopped. New password will apply on next start."
    fi
}

# Function: Print diagnostics beyond NetworkManager's high-level active state.
doctor_hotspot() {
    require_wifi_iface
    local AP_IFACE
    AP_IFACE=$(active_ap_iface)

    status_hotspot

    echo ""
    echo "--- NetworkManager Device ---"
    nmcli -f GENERAL.DEVICE,GENERAL.DRIVER,GENERAL.STATE,GENERAL.REASON,GENERAL.IP4-CONNECTIVITY,IP4.ADDRESS device show "$AP_IFACE" 2>/dev/null || true

    if command_exists iw; then
        echo ""
        echo "--- iw dev ---"
        iw dev "$AP_IFACE" info 2>/dev/null || true

        echo ""
        echo "--- Associated Stations ---"
        iw dev "$AP_IFACE" station dump 2>/dev/null || true
    fi

    echo ""
    echo "--- DHCP Leases ---"
    local LEASE_FILE="/var/lib/NetworkManager/dnsmasq-${AP_IFACE}.leases"
    sudo awk '{name=($4=="*"?"unknown":$4); printf "%-16s  %-19s  %s\n", $3, $2, name}' "$LEASE_FILE" 2>/dev/null \
        || echo "(no readable leases at $LEASE_FILE)"

    if command_exists journalctl; then
        echo ""
        echo "--- Recent NetworkManager Hotspot Logs ---"
        journalctl -u NetworkManager --since -2h --no-pager 2>/dev/null \
            | grep -E "$CON_NAME|$AP_IFACE|dnsmasq|DHCP|Hotspot" \
            | tail -n 80 || true

        echo ""
        echo "--- Recent Kernel Wi-Fi Driver Logs ---"
        journalctl -k --since -2h --no-pager 2>/dev/null \
            | grep -E "rtw|$AP_IFACE|beacon|firmware|flush queue|tx report" \
            | tail -n 80 || true
    fi
}

rebind_wifi_driver() {
    local DEVICE_PATH
    local DRIVER_PATH
    local DEVICE_ID

    DEVICE_PATH=$(readlink -f "/sys/class/net/$WIFI_IFACE/device" 2>/dev/null || true)
    DRIVER_PATH=$(readlink -f "$DEVICE_PATH/driver" 2>/dev/null || true)
    DEVICE_ID=$(basename "$DEVICE_PATH")

    if [ -z "$DEVICE_PATH" ] || [ -z "$DRIVER_PATH" ] || [ ! -e "$DRIVER_PATH/unbind" ] || [ ! -e "$DRIVER_PATH/bind" ]; then
        echo "Driver rebind is not available for $WIFI_IFACE; falling back to interface reset."
        return
    fi

    echo "Rebinding Wi-Fi driver for $WIFI_IFACE ($DEVICE_ID)..."
    echo "$DEVICE_ID" | sudo tee "$DRIVER_PATH/unbind" >/dev/null
    sleep 3
    echo "$DEVICE_ID" | sudo tee "$DRIVER_PATH/bind" >/dev/null || true
    sleep 3
}

# Function: Recover Realtek/USB adapters that still show an SSID but stop accepting clients.
repair_hotspot() {
    require_wifi_iface

    echo "Repairing hotspot '$CON_NAME' on $WIFI_IFACE..."
    sudo nmcli connection down "$CON_NAME" >/dev/null 2>&1 || true
    sudo nmcli device disconnect "$WIFI_IFACE" >/dev/null 2>&1 || true

    if command_exists iw; then
        sudo iw dev "$WIFI_IFACE" set power_save off >/dev/null 2>&1 || true
    fi
    if command_exists ip; then
        sudo ip link set "$WIFI_IFACE" down >/dev/null 2>&1 || true
        sleep 2
        sudo ip link set "$WIFI_IFACE" up >/dev/null 2>&1 || true
    fi

    rebind_wifi_driver
    WIFI_IFACE="${IFACE_OVERRIDE:-$(detect_wifi_iface)}"
    if [ -z "$WIFI_IFACE" ]; then
        echo "Error: Wi-Fi interface did not return after reset. Replug the USB adapter or reboot, then run '$0 start'."
        exit 1
    fi

    start_hotspot
}

# ---------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------

# Parse optional --band / -b flag before the subcommand
while [[ "$1" == --band || "$1" == -b || "$1" == --channel || "$1" == -c || "$1" == --iface || "$1" == -i || "$1" == --ssid || "$1" == -s || "$1" == --password || "$1" == -p ]]; do
    case "$1" in
        --band|-b)
            case "$2" in
                2.4|2|bg) BAND="bg"; shift 2 ;;
                5|a)      BAND="a";  shift 2 ;;
                *) echo "Error: --band expects '2.4' or '5'"; exit 1 ;;
            esac ;;
        --channel|-c)  CHANNEL="$2";        shift 2 ;;
        --iface|-i)    IFACE_OVERRIDE="$2"; shift 2 ;;
        --ssid|-s)     SSID="$2";          shift 2 ;;
        --password|-p) CUSTOM_PASS="$2";   shift 2 ;;
    esac
done

case "$1" in
    start)
        start_hotspot
        ;;
    stop)
        stop_hotspot
        ;;
    restart)
        restart_hotspot
        ;;
    status)
        status_hotspot
        ;;
    doctor)
        doctor_hotspot
        ;;
    repair)
        repair_hotspot
        ;;
    regen)
        regen_password
        ;;
    devices)
        devices_hotspot
        ;;
    *)
        echo "Usage: $0 [-b|--band 2.4|5] [-c|--channel <n>] [-i|--iface <dev>] [-s|--ssid <name>] [-p|--password <pass>] {start|stop|restart|status|doctor|repair|regen|devices}"
        echo ""
        echo "  -b, --band 2.4|5      Select frequency band (default: 2.4GHz)"
        echo "  -c, --channel <n>     Select Wi-Fi channel (default: 6)"
        echo "  -i, --iface <dev>     Select Wi-Fi interface"
        echo "  -s, --ssid <name>     Set SSID (default: shadow-s)"
        echo "  -p, --password <pass> Set password (default: random alphanumeric)"
        echo ""
        echo "  start   - Creates the hotspot if it doesn't exist, and turns it on."
        echo "  stop    - Turns the hotspot off."
        echo "  restart - Restarts the NetworkManager hotspot profile."
        echo "  status  - Shows if it's running and displays the current password."
        echo "  doctor  - Shows low-level AP, station, DHCP, and driver diagnostics."
        echo "  repair  - Resets the Wi-Fi interface/driver, then starts the hotspot without changing the password."
        echo "  regen   - Generates a new password, updates the profile, and restarts the hotspot."
        echo "  devices - Shows devices currently connected to the hotspot."
        echo ""
        echo "Existing profile passwords are preserved unless you run 'regen' or pass --password."
        exit 1
        ;;
esac
