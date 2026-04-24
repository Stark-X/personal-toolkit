#!/bin/bash

# Configuration
WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi" {print $1; exit}')

if [ -z "$WIFI_IFACE" ]; then
    echo "Error: No Wi-Fi interface detected! Please make sure your Wi-Fi is turned on."
    exit 1
fi
WIFI_IFACE="${WIFI_IFACE}"
SSID="DIRECT-XYA1LKJWUI_198"
CON_NAME="the-hotspot"
BAND="bg"  # default: 2.4GHz (bg=2.4GHz, a=5GHz)

# Helper function: Generate the strict password
generate_password() {
    local DIGITS=$(tr -dc '0-9' < /dev/urandom | head -c 6)
    local ALPHA=$(tr -dc 'a-zA-Z' < /dev/urandom | head -c 2)
    local SYMBOLS=$(tr -dc '!@#$%^&*' < /dev/urandom | head -c 2)
    
    # Combine, shuffle, and output
    echo "${DIGITS}${ALPHA}${SYMBOLS}" | fold -w1 | shuf | tr -d '\n'
}

# Function: Start or create the hotspot
start_hotspot() {
    # Check if the connection profile already exists
    if nmcli connection show "$CON_NAME" > /dev/null 2>&1; then
        echo "Starting existing hotspot profile '$CON_NAME'..."
        sudo nmcli connection up "$CON_NAME"
    else
        echo "Creating new hotspot profile '$CON_NAME'..."
        local WIFI_PASS=${CUSTOM_PASS:-$(generate_password)}
        
        sudo nmcli connection add type wifi ifname "$WIFI_IFACE" con-name "$CON_NAME" autoconnect no ssid "$SSID"
        sudo nmcli connection modify "$CON_NAME" 802-11-wireless.mode ap 802-11-wireless.band "$BAND" ipv4.method shared
        sudo nmcli connection modify "$CON_NAME" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PASS" \
            wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp
        
        sudo nmcli connection up "$CON_NAME"
        
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

# Function: Get hotspot status and current credentials
status_hotspot() {
    echo "--- Hotspot Status ---"
    if nmcli connection show --active | grep -q "\b$CON_NAME\b"; then
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
    local BAND_LABEL
    case "$CUR_BAND" in
        a)  BAND_LABEL="5 GHz" ;;
        bg) BAND_LABEL="2.4 GHz" ;;
        *)  BAND_LABEL="${CUR_BAND:-unknown}" ;;
    esac

    echo "SSID:     $SSID"
    echo "Password: $CUR_PASS"
    echo "Band:     $BAND_LABEL"
    echo "Interface: $WIFI_IFACE"
    echo "----------------------"

    # QR code for quick connect (WIFI:T:WPA;S:<ssid>;P:<pass>;H:true;;)
    if command -v qrencode &>/dev/null; then
        echo ""
        qrencode -t ANSI -s 1 "WIFI:T:WPA;S:${SSID};P:${CUR_PASS};;"
    fi
}

# Function: Show connected devices
devices_hotspot() {
    if ! nmcli connection show --active | grep -q "\b$CON_NAME\b"; then
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
    if nmcli connection show --active | grep -q "\b$CON_NAME\b"; then
        echo "Restarting hotspot to apply new password..."
        sudo nmcli connection up "$CON_NAME"
    else
        echo "Hotspot is currently stopped. New password will apply on next start."
    fi
}

# ---------------------------------------------------------
# Argument Parsing
# ---------------------------------------------------------

# Parse optional --band / -b flag before the subcommand
while [[ "$1" == --band || "$1" == -b || "$1" == --ssid || "$1" == -s || "$1" == --password || "$1" == -p ]]; do
    case "$1" in
        --band|-b)
            case "$2" in
                2.4|2|bg) BAND="bg"; shift 2 ;;
                5|a)      BAND="a";  shift 2 ;;
                *) echo "Error: --band expects '2.4' or '5'"; exit 1 ;;
            esac ;;
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
    status)
        status_hotspot
        ;;
    regen)
        regen_password
        ;;
    devices)
        devices_hotspot
        ;;
    *)
        echo "Usage: $0 [-b|--band 2.4|5] [-s|--ssid <name>] [-p|--password <pass>] {start|stop|status|regen|devices}"
        echo ""
        echo "  -b, --band 2.4|5      Select frequency band (default: 2.4GHz)"
        echo "  -s, --ssid <name>     Set SSID (default: shadow-s)"
        echo "  -p, --password <pass> Set password (default: random)"
        echo ""
        echo "  start   - Creates the hotspot if it doesn't exist, and turns it on."
        echo "  stop    - Turns the hotspot off."
        echo "  status  - Shows if it's running and displays the current password."
        echo "  regen   - Generates a new password, updates the profile, and restarts the hotspot."
        echo "  devices - Shows devices currently connected to the hotspot."
        exit 1
        ;;
esac
