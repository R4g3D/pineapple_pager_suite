#!/bin/bash
# Title: Pagergotchi
# Direct Pagergotchi launcher — no pineapplepager needed
# Used for handoff from Loki (or any payload) to Pagergotchi
#
# Loki can call this with: /bin/sh /root/payloads/user/pager-apps/pagergotchi/launch_pagergotchi.sh
# Exit code 42 from Pagergotchi means "switch to Loki"

PAYLOAD_DIR="/root/payloads/user/pager-apps/pagergotchi"

if [ ! -d "$PAYLOAD_DIR/pwnagotchi_port" ]; then
    echo "Pagergotchi not found at $PAYLOAD_DIR"
    exit 1
fi

export PATH="/mmc/usr/bin:$PAYLOAD_DIR/bin:$PATH"
export PYTHONPATH="$PAYLOAD_DIR/lib:$PAYLOAD_DIR:$PYTHONPATH"
export LD_LIBRARY_PATH="/mmc/usr/lib:$PAYLOAD_DIR/lib:$LD_LIBRARY_PATH"

_restored=0
cleanup() {
    [ "$_restored" = "1" ] && return
    _restored=1
    [ -n "$PINEAPD_PID" ] && kill "$PINEAPD_PID" 2>/dev/null
    killall hcxdumptool 2>/dev/null
    killall pineapd 2>/dev/null
    /etc/init.d/pineapd start 2>/dev/null
}
trap 'cleanup; exit' INT TERM
trap cleanup EXIT

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

cd "$PAYLOAD_DIR"
python3 run_pagergotchi.py
EXIT_CODE=$?
exit $EXIT_CODE
