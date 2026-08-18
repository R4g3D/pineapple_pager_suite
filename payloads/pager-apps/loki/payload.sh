#!/bin/sh
# Title: Loki
# Description: Autonomous LAN reconnaissance and service enumeration
# Author: brAinphreAk
# Version: 1.0.1
# Requires: python3, python3-codecs, python3-ctypes, python3-email,
#           python3-logging, python3-openssl, python3-urllib
# Category: Pager Apps
# Library: libpagerctl.so (pagerctl)

# Payload metadata for pager theme engine
_PAYLOAD_TITLE="Loki"
_PAYLOAD_AUTHOR_NAME="brAinphreAk"
_PAYLOAD_VERSION="1.0.1"
_PAYLOAD_DESCRIPTION="Autonomous LAN reconnaissance and service enumeration"

# Payload directory (standard Pager installation path)
PAYLOAD_DIR="/root/payloads/user/pager-apps/loki"
DATA_DIR="$PAYLOAD_DIR/data"

cd "$PAYLOAD_DIR" || {
    LOG "red" "ERROR: $PAYLOAD_DIR not found"
    exit 1
}

#
# Find and setup pagerctl dependencies (libpagerctl.so + pagerctl.py)
# lib/ is the canonical location — check it first, then payload root, then external PAGERCTL
#
PAGERCTL_FOUND=false
for dir in "$PAYLOAD_DIR/lib" "$PAYLOAD_DIR" "/mmc/root/payloads/user/utilities/PAGERCTL"; do
    if [ -f "$dir/libpagerctl.so" ] && [ -f "$dir/pagerctl.py" ]; then
        PAGERCTL_DIR="$dir"
        PAGERCTL_FOUND=true
        break
    fi
done

if [ "$PAGERCTL_FOUND" = false ]; then
    LOG ""
    LOG "red" "=== MISSING DEPENDENCY ==="
    LOG ""
    LOG "red" "libpagerctl.so and pagerctl.py not found!"
    LOG ""
    LOG "Searched:"
    for dir in "$PAYLOAD_DIR/lib" "$PAYLOAD_DIR" "/mmc/root/payloads/user/utilities/PAGERCTL"; do
        LOG "  $dir"
    done
    LOG ""
    LOG "Install PAGERCTL payload or copy files to:"
    LOG "  $PAYLOAD_DIR/lib/"
    LOG ""
    LOG "Press any button to exit..."
    WAIT_FOR_INPUT >/dev/null 2>&1
    exit 1
fi

# Copy to lib/ if found outside of it (payload root or external PAGERCTL)
if [ "$PAGERCTL_DIR" != "$PAYLOAD_DIR/lib" ]; then
    mkdir -p "$PAYLOAD_DIR/lib" 2>/dev/null
    cp "$PAGERCTL_DIR/libpagerctl.so" "$PAYLOAD_DIR/lib/" 2>/dev/null
    cp "$PAGERCTL_DIR/pagerctl.py" "$PAYLOAD_DIR/lib/" 2>/dev/null
    LOG "green" "Copied pagerctl from $PAGERCTL_DIR to lib/"
fi

#
# Setup local paths for bundled binaries and libraries
# Uses libpagerctl.so for display/input handling
# MMC paths needed when python3 installed with opkg -d mmc
#
export PATH="/mmc/usr/bin:$PAYLOAD_DIR/bin:$PATH"
export PYTHONPATH="$PAYLOAD_DIR/lib:$PAYLOAD_DIR:$PYTHONPATH"
export LD_LIBRARY_PATH="/mmc/usr/lib:$PAYLOAD_DIR/lib:$LD_LIBRARY_PATH"
export CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1
LOOT_DIR="/root/loot/Loki"
DEPENDENCY_LOG_DIR="$LOOT_DIR/logs"
DEPENDENCY_LOG="$DEPENDENCY_LOG_DIR/dependency-install.log"
PYTHON_PREFLIGHT_LOG="$DEPENDENCY_LOG_DIR/python-preflight.log"
OPKG_RETRIES=3
# NMAPDIR: prefer bundled nmap data, fall back to mmc, then system
if [ -d "$PAYLOAD_DIR/share/nmap/scripts" ]; then
    export NMAPDIR="$PAYLOAD_DIR/share/nmap"
elif [ -d "/mmc/usr/share/nmap/scripts" ]; then
    export NMAPDIR="/mmc/usr/share/nmap"
else
    export NMAPDIR="/usr/share/nmap"
fi

#
# Check and install Python runtime dependencies.
#
# OpenWrt splits Python's standard library across several packages. A
# python3 executable can therefore be present even though Loki cannot import
# all of the modules used by its menu, web UI, connectors, and bundled Python
# packages.
#
MISSING_PYTHON_PACKAGES=""
MISSING_PYTHON_FEATURES=""

add_missing_python_package() {
    package="$1"
    feature="$2"

    case " $MISSING_PYTHON_PACKAGES " in
        *" $package "*) return ;;
    esac

    MISSING_PYTHON_PACKAGES="$MISSING_PYTHON_PACKAGES $package"
    MISSING_PYTHON_FEATURES="${MISSING_PYTHON_FEATURES}${feature}
"
}

check_python_dependencies() {
    MISSING_PYTHON_PACKAGES=""
    MISSING_PYTHON_FEATURES=""

    if ! command -v python3 >/dev/null 2>&1; then
        add_missing_python_package "python3" "Python 3 runtime and standard library"
        add_missing_python_package "python3-codecs" "codecs module"
        add_missing_python_package "python3-ctypes" "ctypes module"
        add_missing_python_package "python3-email" "email module"
        add_missing_python_package "python3-logging" "logging module"
        add_missing_python_package "python3-openssl" "ssl module"
        add_missing_python_package "python3-urllib" "urllib module"
        return
    fi

    python3 -c "import concurrent.futures, csv, ftplib, gzip, http.server, ipaddress, socketserver, telnetlib, uuid, zipfile" 2>/dev/null || \
        add_missing_python_package "python3" "Python standard library"
    python3 -c "import codecs" 2>/dev/null || \
        add_missing_python_package "python3-codecs" "codecs module"
    python3 -c "import ctypes" 2>/dev/null || \
        add_missing_python_package "python3-ctypes" "ctypes module"
    python3 -c "import email.utils" 2>/dev/null || \
        add_missing_python_package "python3-email" "email module"
    python3 -c "import logging" 2>/dev/null || \
        add_missing_python_package "python3-logging" "logging module"
    python3 -c "import ssl" 2>/dev/null || \
        add_missing_python_package "python3-openssl" "ssl module"
    python3 -c "import urllib.parse, urllib.request" 2>/dev/null || \
        add_missing_python_package "python3-urllib" "urllib module"
}

log_command_output() {
    [ -z "$1" ] && return
    printf '%s\n' "$1" >> "$DEPENDENCY_LOG"
    printf '%s\n' "$1" | while IFS= read -r line; do
        LOG "  $line"
    done
}

run_opkg_with_retries() {
    opkg_description="$1"
    shift
    opkg_attempt=1
    opkg_status=1

    while [ "$opkg_attempt" -le "$OPKG_RETRIES" ]; do
        printf '\n[%s] %s (attempt %s/%s)\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$opkg_description" \
            "$opkg_attempt" "$OPKG_RETRIES" >> "$DEPENDENCY_LOG"

        opkg_output=$("$@" 2>&1)
        opkg_status=$?
        log_command_output "$opkg_output"

        if [ "$opkg_status" -eq 0 ]; then
            return 0
        fi

        if [ "$opkg_attempt" -lt "$OPKG_RETRIES" ]; then
            next_attempt=$((opkg_attempt + 1))
            LOG "yellow" "$opkg_description failed; retrying ($next_attempt/$OPKG_RETRIES)..."
            sleep 2
        fi
        opkg_attempt=$((opkg_attempt + 1))
    done

    return "$opkg_status"
}

cached_package_metadata_available() {
    for cached_package in $MISSING_PYTHON_PACKAGES; do
        if [ -z "$(opkg list "$cached_package" 2>/dev/null)" ]; then
            return 1
        fi
    done
    return 0
}

install_missing_python_packages() {
    LOG "Installing missing Python packages to MMC..."
    # Package names are generated only by add_missing_python_package above.
    # Intentional word splitting passes them as individual opkg arguments.
    if run_opkg_with_retries "MMC package installation" \
        opkg -d mmc install $MISSING_PYTHON_PACKAGES; then
        return 0
    fi

    LOG "yellow" "MMC installation failed; trying system storage..."
    run_opkg_with_retries "System package installation" \
        opkg install $MISSING_PYTHON_PACKAGES
}

install_python_packages() {
    used_cached_metadata=false

    if ! command -v opkg >/dev/null 2>&1; then
        LOG "red" "ERROR: opkg is unavailable; cannot install Python packages"
        return 1
    fi

    mkdir -p "$DEPENDENCY_LOG_DIR" 2>/dev/null || {
        LOG "red" "ERROR: Cannot create $DEPENDENCY_LOG_DIR"
        return 1
    }
    printf '\n=== Loki dependency check: %s ===\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >> "$DEPENDENCY_LOG"

    LOG ""
    LOG "yellow" "Missing Python requirements:"
    printf '%s' "$MISSING_PYTHON_FEATURES" | while IFS= read -r feature; do
        [ -n "$feature" ] && LOG "  - $feature"
    done

    if cached_package_metadata_available; then
        used_cached_metadata=true
        LOG "Using cached package metadata."
        printf '[%s] Required packages found in cached metadata\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" >> "$DEPENDENCY_LOG"
    else
        LOG "Refreshing package lists..."
        if ! run_opkg_with_retries "Package-list refresh" opkg update; then
            if cached_package_metadata_available; then
                LOG "yellow" "Refresh failed; continuing with cached package metadata."
            else
                LOG "red" "Package metadata refresh failed after $OPKG_RETRIES attempts."
                LOG "red" "Details: $DEPENDENCY_LOG"
                return 1
            fi
        fi
    fi

    LOG ""
    if install_missing_python_packages; then
        hash -r
        return 0
    fi

    if [ "$used_cached_metadata" = true ]; then
        LOG "yellow" "Cached installation failed; refreshing package lists..."
        if run_opkg_with_retries "Package-list refresh" opkg update && \
            install_missing_python_packages; then
            hash -r
            return 0
        fi
    fi

    hash -r
    LOG "red" "Package installation failed after retries."
    LOG "red" "Details: $DEPENDENCY_LOG"
    return 1
}

check_python_dependencies
if [ -n "$MISSING_PYTHON_PACKAGES" ]; then
    if ! install_python_packages; then
        LOG "red" "Failed to install Loki Python requirements."
        LOG "red" "Review the dependency log, connectivity, and available storage."
        LOG "red" "$DEPENDENCY_LOG"
        LOG ""
        LOG "Press any button to exit..."
        WAIT_FOR_INPUT >/dev/null 2>&1
        exit 1
    fi

    check_python_dependencies
    if [ -n "$MISSING_PYTHON_PACKAGES" ]; then
        LOG "red" "Python dependency verification failed. Still missing:"
        printf '%s' "$MISSING_PYTHON_FEATURES" | while IFS= read -r feature; do
            [ -n "$feature" ] && LOG "red" "  - $feature"
        done
        LOG ""
        LOG "Press any button to exit..."
        WAIT_FOR_INPUT >/dev/null 2>&1
        exit 1
    fi

    LOG "green" "Python requirements installed successfully."
    sleep 1
fi

# Import Loki's system modules, bundled dependencies, UI, and action modules
# before stopping the normal Pager interface. This exposes incomplete Python
# installations or incompatible bundled native modules during first-run setup.
PYTHON_PREFLIGHT='import codecs, concurrent.futures, csv, ctypes, email.utils, ftplib, gzip, http.server, ipaddress, json, logging, socketserver, ssl, telnetlib, threading, urllib.parse, urllib.request, uuid, zipfile; from pagerctl import Pager; import bcrypt, cryptography, getmac, nmap, paramiko, pymysql; from smb.SMBConnection import SMBConnection; import loki_menu, orchestrator, webapp; import actions.ftp_connector, actions.nmap_vuln_scanner, actions.rdp_connector, actions.scanning, actions.smb_connector, actions.sql_connector, actions.ssh_connector, actions.steal_data_sql, actions.steal_files_ftp, actions.steal_files_smb, actions.steal_files_ssh, actions.steal_files_telnet, actions.telnet_connector'
mkdir -p "$DEPENDENCY_LOG_DIR" 2>/dev/null
if ! python3 -c "$PYTHON_PREFLIGHT" >"$PYTHON_PREFLIGHT_LOG" 2>&1; then
    LOG "red" "Loki Python import preflight failed:"
    while IFS= read -r line; do LOG "red" "  $line"; done < "$PYTHON_PREFLIGHT_LOG"
    LOG "red" "Details: $PYTHON_PREFLIGHT_LOG"
    LOG ""
    LOG "Press any button to exit..."
    WAIT_FOR_INPUT >/dev/null 2>&1
    exit 1
fi
rm -f "$PYTHON_PREFLIGHT_LOG"

#
# Check Loki dependencies
# Python packages are bundled in lib/, nmap-full is bundled in bin/ + share/
#
check_dependencies() {
    LOG ""
    LOG "Checking dependencies..."

    # Verify bundled nmap works
    if ! nmap --version >/dev/null 2>&1; then
        LOG ""
        LOG "red" "ERROR: nmap binary not working!"
        LOG ""
        LOG "Press any button to exit..."
        WAIT_FOR_INPUT >/dev/null 2>&1
        exit 1
    fi

    LOG "green" "All dependencies found!"
}

# ============================================================
# CLEANUP
# ============================================================

cleanup() {
    # Restart pager service if not running
    if ! pgrep -x pineapple >/dev/null; then
        /etc/init.d/pineapplepager start 2>/dev/null
    fi
}

# Ensure pager service restarts on exit
trap cleanup EXIT

# ============================================================
# MAIN
# ============================================================

# Check dependencies automatically
check_dependencies

# Check network connectivity (at least one interface with IP)
HAS_NETWORK=false
for IP in $(ip -4 addr 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1); do
    if [ "$IP" != "127.0.0.1" ]; then
        HAS_NETWORK=true
        break
    fi
done

if [ "$HAS_NETWORK" = false ]; then
    LOG ""
    LOG "red" "=== NO NETWORK CONNECTED ==="
    LOG ""
    LOG "Loki requires a network connection to scan."
    LOG "Please connect to a network first:"
    LOG "  - WiFi client mode (wlan0cli)"
    LOG "  - Ethernet/USB (br-lan)"
    LOG ""
    LOG "Press any button to exit..."
    WAIT_FOR_INPUT >/dev/null 2>&1
    exit 1
fi

# Show info/splash screen
LOG ""
LOG "green" "Loki for WiFi Pineapple Pager"
LOG "cyan" "by *brAinphreAk*"
LOG ""
LOG "yellow" "Features:"
LOG "cyan" "  - Automated network reconnaissance"
LOG "cyan" "  - Port scanning with nmap"
LOG "cyan" "  - SSH/SMB/FTP/Telnet/RDP/SQL brute force"
LOG "cyan" "  - Data exfiltration"
LOG "cyan" "  - Vulnerability scanning"
LOG "cyan" "  - Web UI and theme support"
LOG ""
LOG "green" "GREEN = Start"
LOG "red" "RED = Exit"
LOG ""

while true; do
    BUTTON=$(WAIT_FOR_INPUT 2>/dev/null)
    case "$BUTTON" in
        "GREEN"|"A")
            break
            ;;
        "RED"|"B")
            LOG "Exiting."
            exit 0
            ;;
    esac
done

# Create data directory
mkdir -p "$DATA_DIR" 2>/dev/null

# Stop pager service and show spinner while initializing
SPINNER_ID=$(START_SPINNER "Starting Loki...")
/etc/init.d/pineapplepager stop 2>/dev/null
sleep 0.5
STOP_SPINNER "$SPINNER_ID" 2>/dev/null

# Payload loop — Loki can hand off to other apps via exit code 42
# Python writes the target launch script path to data/.next_payload
NEXT_PAYLOAD_FILE="$DATA_DIR/.next_payload"

while true; do
    cd "$PAYLOAD_DIR"
    python3 loki_menu.py
    EXIT_CODE=$?

    # Exit code 42 = hand off to another payload
    if [ "$EXIT_CODE" -eq 42 ] && [ -f "$NEXT_PAYLOAD_FILE" ]; then
        NEXT_SCRIPT=$(cat "$NEXT_PAYLOAD_FILE")
        rm -f "$NEXT_PAYLOAD_FILE"
        if [ -f "$NEXT_SCRIPT" ]; then
            sh "$NEXT_SCRIPT"
            # Only loop back to Loki if launched app exits 42
            [ $? -eq 42 ] && continue
        fi
    fi

    # Exit code 99 = return to main menu (from pause menu)
    # bjorn_menu.py handles this internally, but as safety net
    if [ "$EXIT_CODE" -eq 99 ]; then
        continue
    fi

    break
done

exit 0
