#!/bin/bash
# Title: PagerGotchi
# Description: Pwnagotchi for WiFi Pineapple Pager - Automated WiFi handshake capture with personality
# Author: brAinphreAk
# Version: 2.1.2
# Requires: python3, python3-asyncio, python3-codecs, python3-ctypes, python3-logging
# Category: Pager Apps
# Library: libpagerctl.so (pagerctl)

# Payload directory (standard Pager installation path)
PAYLOAD_DIR="/root/payloads/user/pager-apps/pagergotchi"
DATA_DIR="$PAYLOAD_DIR/data"

cd "$PAYLOAD_DIR" || {
    LOG "red" "ERROR: $PAYLOAD_DIR not found"
    exit 1
}

#
# Find and setup pagerctl dependencies (libpagerctl.so + pagerctl.py)
# Check bundled lib/ first, then PAGERCTL utilities dir
#
PAGERCTL_FOUND=false
PAGERCTL_SEARCH_PATHS=(
    "$PAYLOAD_DIR/lib"
    "/mmc/root/payloads/user/utilities/PAGERCTL"
)

for dir in "${PAGERCTL_SEARCH_PATHS[@]}"; do
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
    for dir in "${PAGERCTL_SEARCH_PATHS[@]}"; do
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

# If pagerctl files aren't in our lib dir, copy them there
if [ "$PAGERCTL_DIR" != "$PAYLOAD_DIR/lib" ]; then
    mkdir -p "$PAYLOAD_DIR/lib" 2>/dev/null
    cp "$PAGERCTL_DIR/libpagerctl.so" "$PAYLOAD_DIR/lib/" 2>/dev/null
    cp "$PAGERCTL_DIR/pagerctl.py" "$PAYLOAD_DIR/lib/" 2>/dev/null
    LOG "green" "Copied pagerctl from $PAGERCTL_DIR"
fi

#
# Setup local paths for bundled binaries and libraries
# Uses libpagerctl.so for display/input handling
# MMC paths needed when python3 installed with opkg -d mmc
#
export PATH="/mmc/usr/bin:$PAYLOAD_DIR/bin:$PATH"
export PYTHONPATH="$PAYLOAD_DIR/lib:$PAYLOAD_DIR:$PYTHONPATH"
export LD_LIBRARY_PATH="/mmc/usr/lib:$PAYLOAD_DIR/lib:$LD_LIBRARY_PATH"

LOOT_DIR="/root/loot/Pagergotchi"
DEPENDENCY_LOG_DIR="$LOOT_DIR/logs"
DEPENDENCY_LOG="$DEPENDENCY_LOG_DIR/dependency-install.log"
PYTHON_PREFLIGHT_LOG="$DEPENDENCY_LOG_DIR/python-preflight.log"
OPKG_RETRIES=3

#
# Check and install Python runtime dependencies.
#
# OpenWrt splits parts of the Python standard library into separate packages.
# Checking only for the python3 executable is therefore not sufficient: a
# python3-light installation can exist while asyncio, ctypes, logging, or
# codecs are still unavailable.
#
declare -a MISSING_PYTHON_PACKAGES=()
declare -a MISSING_PYTHON_FEATURES=()

add_missing_python_package() {
    local package="$1"
    local feature="$2"
    local existing

    for existing in "${MISSING_PYTHON_PACKAGES[@]}"; do
        [ "$existing" = "$package" ] && return
    done

    MISSING_PYTHON_PACKAGES+=("$package")
    MISSING_PYTHON_FEATURES+=("$feature")
}

check_python_dependencies() {
    MISSING_PYTHON_PACKAGES=()
    MISSING_PYTHON_FEATURES=()

    if ! command -v python3 >/dev/null 2>&1; then
        add_missing_python_package "python3" "Python 3 runtime"
        add_missing_python_package "python3-asyncio" "asyncio module"
        add_missing_python_package "python3-codecs" "codecs module"
        add_missing_python_package "python3-ctypes" "ctypes module"
        add_missing_python_package "python3-logging" "logging module"
        return
    fi

    python3 -c "import asyncio" 2>/dev/null || \
        add_missing_python_package "python3-asyncio" "asyncio module"
    python3 -c "import codecs" 2>/dev/null || \
        add_missing_python_package "python3-codecs" "codecs module"
    python3 -c "import ctypes" 2>/dev/null || \
        add_missing_python_package "python3-ctypes" "ctypes module"
    python3 -c "import logging" 2>/dev/null || \
        add_missing_python_package "python3-logging" "logging module"
}

log_command_output() {
    local output="$1"

    [ -z "$output" ] && return
    printf '%s\n' "$output" >> "$DEPENDENCY_LOG"
    while IFS= read -r line; do
        LOG "  $line"
    done <<< "$output"
}

run_opkg_with_retries() {
    local description="$1"
    local attempt output command_status
    shift

    attempt=1
    while [ "$attempt" -le "$OPKG_RETRIES" ]; do
        printf '\n[%s] %s (attempt %s/%s)\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$description" \
            "$attempt" "$OPKG_RETRIES" >> "$DEPENDENCY_LOG"

        output=$("$@" 2>&1)
        command_status=$?
        log_command_output "$output"

        if [ "$command_status" -eq 0 ]; then
            return 0
        fi

        if [ "$attempt" -lt "$OPKG_RETRIES" ]; then
            LOG "yellow" "$description failed; retrying ($((attempt + 1))/$OPKG_RETRIES)..."
            sleep 2
        fi
        attempt=$((attempt + 1))
    done

    return "$command_status"
}

cached_package_metadata_available() {
    local package

    for package in "${MISSING_PYTHON_PACKAGES[@]}"; do
        if [ -z "$(opkg list "$package" 2>/dev/null)" ]; then
            return 1
        fi
    done
    return 0
}

install_missing_python_packages() {
    LOG "Installing missing Python packages to MMC..."
    if run_opkg_with_retries "MMC package installation" \
        opkg -d mmc install "${MISSING_PYTHON_PACKAGES[@]}"; then
        return 0
    fi

    # Some installations do not define an mmc opkg destination. Fall back to
    # normal system storage instead of leaving first-run setup incomplete.
    LOG "yellow" "MMC installation failed; trying system storage..."
    run_opkg_with_retries "System package installation" \
        opkg install "${MISSING_PYTHON_PACKAGES[@]}"
}

install_python_packages() {
    local used_cached_metadata=false

    if ! command -v opkg >/dev/null 2>&1; then
        LOG "red" "ERROR: opkg is unavailable; cannot install Python packages"
        return 1
    fi

    mkdir -p "$DEPENDENCY_LOG_DIR" 2>/dev/null || {
        LOG "red" "ERROR: Cannot create $DEPENDENCY_LOG_DIR"
        return 1
    }
    printf '\n=== PagerGotchi dependency check: %s ===\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >> "$DEPENDENCY_LOG"

    LOG ""
    LOG "yellow" "Missing Python requirements:"
    for feature in "${MISSING_PYTHON_FEATURES[@]}"; do
        LOG "  - $feature"
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

    # Cached metadata can point at package versions which have moved. Refresh
    # once, with retries, then repeat both destination attempts.
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
if [ "${#MISSING_PYTHON_PACKAGES[@]}" -gt 0 ]; then
    if ! install_python_packages; then
        LOG "red" "Failed to install PagerGotchi Python requirements."
        LOG "red" "Review the dependency log, connectivity, and available storage."
        LOG "red" "$DEPENDENCY_LOG"
        LOG ""
        LOG "Press any button to exit..."
        WAIT_FOR_INPUT >/dev/null 2>&1
        exit 1
    fi

    check_python_dependencies
    if [ "${#MISSING_PYTHON_PACKAGES[@]}" -gt 0 ]; then
        LOG "red" "Python dependency verification failed. Still missing:"
        for feature in "${MISSING_PYTHON_FEATURES[@]}"; do
            LOG "red" "  - $feature"
        done
        LOG ""
        LOG "Press any button to exit..."
        WAIT_FOR_INPUT >/dev/null 2>&1
        exit 1
    fi

    LOG "green" "Python requirements installed successfully."
    sleep 1
fi

# Import the complete application before stopping Pager services. This catches
# an incomplete OpenWrt Python installation while the normal UI is still up.
PYTHON_PREFLIGHT='import asyncio, codecs, configparser, csv, ctypes, datetime, enum, gettext, glob, hashlib, json, logging, queue, random, re, select, signal, socket, subprocess, threading, time; from pagerctl import Pager; import pwnagotchi_port.main'
mkdir -p "$DEPENDENCY_LOG_DIR" 2>/dev/null
if ! python3 -c "$PYTHON_PREFLIGHT" >"$PYTHON_PREFLIGHT_LOG" 2>&1; then
    LOG "red" "PagerGotchi Python import preflight failed:"
    while IFS= read -r line; do LOG "red" "  $line"; done < "$PYTHON_PREFLIGHT_LOG"
    LOG "red" "Details: $PYTHON_PREFLIGHT_LOG"
    LOG ""
    LOG "Press any button to exit..."
    WAIT_FOR_INPUT >/dev/null 2>&1
    exit 1
fi
rm -f "$PYTHON_PREFLIGHT_LOG"

# Verify pwnagotchi_port Python module exists
[ ! -d "$PAYLOAD_DIR/pwnagotchi_port" ] && {
    LOG "red" "ERROR: pwnagotchi_port module not found"
    exit 1
}

#
# Setup
#

# Create data directory
mkdir -p "$DATA_DIR" 2>/dev/null

_restored=0
restore_services() {
    [ "$_restored" = "1" ] && return
    _restored=1
    [ -n "$PINEAPD_PID" ] && kill "$PINEAPD_PID" 2>/dev/null
    killall hcxdumptool 2>/dev/null
    killall pineapd 2>/dev/null
    sleep 1
    /etc/init.d/pineapd start 2>/dev/null
    /etc/init.d/php8-fpm start 2>/dev/null
    /etc/init.d/nginx start 2>/dev/null
    /etc/init.d/bluetoothd start 2>/dev/null
    /etc/init.d/pineapplepager start 2>/dev/null
}
trap 'restore_services; exit' INT TERM
trap restore_services EXIT

start_capture_pineapd() {
    /etc/init.d/pineapd stop 2>/dev/null
    killall pineapd 2>/dev/null
    sleep 1
    mkdir -p /root/loot/Pagergotchi/handshakes
    /usr/sbin/pineapd \
        --recon=true \
        --reconpath /root/recon/ \
        --reconname pager \
        --handshakepath /root/loot/Pagergotchi/handshakes/ \
        --handshakes=true \
        --partialhandshakes=true \
        --interface wlan1mon \
        --band wlan1mon:2,5 \
        --type wlan1mon:max \
        --hop wlan1mon:fast \
        --primary wlan1mon \
        --inject wlan1mon &
    PINEAPD_PID=$!
    sleep 2
}

#
# Main
#

# Show info/splash screen first
LOG ""
LOG "green" "Pwnagotchi for WiFi Pineapple Pager"
LOG "cyan" "ported by *brAinphreAk* (www.brAinphreAk.net)"
LOG ""
LOG "yellow" "Features:"
LOG "cyan" "  - Automated WiFi handshake capture"
LOG "cyan" "  - PMKID and 4-way handshake attacks"
LOG "cyan" "  - Deauth Scope: Whitelist/Blacklist"
LOG "cyan" "  - Privacy Mode: Obfuscate display"
LOG "cyan" "  - Optional GPS & WiGLE logging"
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

# Now do setup after GREEN button pressed
LOG ""
SPINNER_ID=$(START_SPINNER "Setting up PagerGotchi...")

if ! iw dev 2>/dev/null | grep -q wlan1mon; then
    STOP_SPINNER "$SPINNER_ID" 2>/dev/null
    LOG "red" "wlan1mon not found - capture may not work"
    SPINNER_ID=$(START_SPINNER "Starting anyway...")
fi

# Stop services to free framebuffer
/etc/init.d/php8-fpm stop 2>/dev/null
/etc/init.d/nginx stop 2>/dev/null
/etc/init.d/bluetoothd stop 2>/dev/null
/etc/init.d/pineapplepager stop 2>/dev/null

STOP_SPINNER "$SPINNER_ID" 2>/dev/null

# Detect and setup GPS if available
LOG "Detecting GPS device..."
GPS_DEVICE=$(uci -q get gpsd.core.device 2>/dev/null)
if [ -n "$GPS_DEVICE" ] && [ -e "$GPS_DEVICE" ]; then
    LOG "green" "GPS detected: $GPS_DEVICE"
    LOG "Restarting gpsd..."
    /etc/init.d/gpsd restart 2>/dev/null
    sleep 2
else
    LOG "No GPS device detected (optional)"
fi

sleep 0.5

# Payload loop — PagerGotchi can hand off to other apps via exit code 42
# Python writes the target launch script path to data/.next_payload
# No pineapplepager restart needed between switches
NEXT_PAYLOAD_FILE="$DATA_DIR/.next_payload"

while true; do
    start_capture_pineapd
    if kill -0 "$PINEAPD_PID" 2>/dev/null; then
        LOG "green" "pineapd started with handshake capture (PID: $PINEAPD_PID)"
    else
        LOG "red" "Warning: pineapd may not have started correctly"
    fi

    cd "$PAYLOAD_DIR"
    python3 run_pagergotchi.py
    EXIT_CODE=$?

    killall hcxdumptool 2>/dev/null
    [ -n "$PINEAPD_PID" ] && kill "$PINEAPD_PID" 2>/dev/null
    PINEAPD_PID=""
    killall pineapd 2>/dev/null

    if [ "$EXIT_CODE" -eq 42 ] && [ -f "$NEXT_PAYLOAD_FILE" ]; then
        NEXT_SCRIPT=$(cat "$NEXT_PAYLOAD_FILE")
        rm -f "$NEXT_PAYLOAD_FILE"
        /etc/init.d/pineapd start 2>/dev/null
        if [ -f "$NEXT_SCRIPT" ]; then
            bash "$NEXT_SCRIPT"
            [ $? -eq 42 ] && continue
        fi
    fi

    break
done
