#!/bin/bash
# Title: Loki
# Requires: /root/payloads/user/pager-apps/loki
# Loki launcher — runs loki_menu.py, which handles its menu and process loop.
# Used for handoff from PagerGotchi (or any payload) to Loki.

LOKI_DIR="/root/payloads/user/pager-apps/loki"

if [ ! -d "$LOKI_DIR" ]; then
    echo "Loki not found at $LOKI_DIR"
    exit 1
fi

# Loki environment
export PATH="/mmc/usr/bin:$PATH"
export PYTHONPATH="$LOKI_DIR/lib:$LOKI_DIR:$PYTHONPATH"
export LD_LIBRARY_PATH="/mmc/usr/lib:$LOKI_DIR/lib:$LOKI_DIR:$LD_LIBRARY_PATH"
export CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1

cd "$LOKI_DIR"
python3 loki_menu.py
exit $?
