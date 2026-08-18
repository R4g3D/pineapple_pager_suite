#!/usr/bin/env bash

set -euo pipefail

DEFAULT_HOST="172.16.52.1"
PAGER_HOST="$DEFAULT_HOST"
PAGER_USER="root"
PAGER_PORT="22"
IDENTITY_FILE=""
REPLACE_USER_CATEGORIES=0
HOST_SET=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/payloads"
ARCHIVE=""

usage() {
    cat <<'EOF'
Usage: ./install.sh [options] [pager-host]

Copy the suite's user, recon, and alert payloads to a WiFi Pineapple Pager.

Options:
  --host HOST                    Pager hostname or IP (default: 172.16.52.1)
  --user USER                    SSH user (default: root)
  --port PORT                    SSH port (default: 22)
  --identity FILE                SSH private key to use
  --replace-user-categories      Remove the stock user category entries from
                                 /etc/config/payloads and register the suite's
                                 top-level user categories instead
  -h, --help                     Show this help

The category replacement is deliberately opt-in. Without that option, the
installer copies payloads but does not modify the Pager's UCI configuration.
EOF
}

fail() {
    printf '[!] %s\n' "$*" >&2
    exit 1
}

info() {
    printf '[*] %s\n' "$*"
}

ok() {
    printf '[+] %s\n' "$*"
}

cleanup() {
    if [[ -n "$ARCHIVE" && -f "$ARCHIVE" ]]; then
        rm -f -- "$ARCHIVE"
    fi
}

trap cleanup EXIT INT TERM

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            [[ $# -ge 2 ]] || fail "--host requires a value"
            [[ "$HOST_SET" -eq 0 ]] || fail "only one pager host may be specified"
            PAGER_HOST="$2"
            HOST_SET=1
            shift 2
            ;;
        --user)
            [[ $# -ge 2 ]] || fail "--user requires a value"
            PAGER_USER="$2"
            shift 2
            ;;
        --port)
            [[ $# -ge 2 ]] || fail "--port requires a value"
            PAGER_PORT="$2"
            shift 2
            ;;
        --identity)
            [[ $# -ge 2 ]] || fail "--identity requires a value"
            IDENTITY_FILE="$2"
            shift 2
            ;;
        --replace-user-categories)
            REPLACE_USER_CATEGORIES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            if [[ $# -gt 0 ]]; then
                [[ $# -eq 1 && "$HOST_SET" -eq 0 ]] || fail "only one pager host may be specified"
                PAGER_HOST="$1"
                HOST_SET=1
                shift
            fi
            break
            ;;
        -*)
            fail "unknown option: $1"
            ;;
        *)
            [[ "$HOST_SET" -eq 0 ]] || fail "only one pager host may be specified"
            PAGER_HOST="$1"
            HOST_SET=1
            shift
            ;;
    esac
done

[[ $# -eq 0 ]] || fail "unexpected argument: $1"
[[ "$PAGER_HOST" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "invalid pager host: $PAGER_HOST"
[[ "$PAGER_USER" =~ ^[A-Za-z0-9._-]+$ ]] || fail "invalid SSH user: $PAGER_USER"
[[ "$PAGER_PORT" =~ ^[0-9]+$ ]] || fail "SSH port must be numeric"
(( PAGER_PORT >= 1 && PAGER_PORT <= 65535 )) || fail "SSH port must be between 1 and 65535"
[[ -z "$IDENTITY_FILE" || -f "$IDENTITY_FILE" ]] || fail "identity file not found: $IDENTITY_FILE"

for command_name in ssh scp tar gzip find mktemp; do
    command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
done

[[ -d "$PAYLOAD_DIR/user" ]] || fail "missing payloads/user; run this script from a complete suite checkout"
[[ -d "$PAYLOAD_DIR/recon" ]] || fail "missing payloads/recon; initialize the suite submodules first"
[[ -d "$PAYLOAD_DIR/alerts" ]] || fail "missing payloads/alerts; initialize the suite submodules first"

if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$SCRIPT_DIR" submodule status --recursive | grep -q '^-'; then
        fail "one or more payload submodules are uninitialized; run: git submodule update --init --recursive"
    fi
fi

PAYLOAD_COUNT="$(find "$PAYLOAD_DIR/user" "$PAYLOAD_DIR/recon" "$PAYLOAD_DIR/alerts" -type f -name payload.sh | wc -l | tr -d ' ')"
[[ "$PAYLOAD_COUNT" -gt 0 ]] || fail "no payload.sh files found"

USER_CATEGORIES=()
while IFS= read -r category_path; do
    category_name="${category_path##*/}"
    [[ "$category_name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "unsupported user category name: $category_name"
    USER_CATEGORIES+=("user/$category_name")
done < <(find "$PAYLOAD_DIR/user" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)

[[ ${#USER_CATEGORIES[@]} -gt 0 ]] || fail "no top-level user categories found"

SSH_ARGS=(-p "$PAGER_PORT" -o ConnectTimeout=10)
SCP_ARGS=(-P "$PAGER_PORT" -o ConnectTimeout=10)
if [[ -n "$IDENTITY_FILE" ]]; then
    SSH_ARGS+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)
    SCP_ARGS+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)
fi

PAGER_TARGET="$PAGER_USER@$PAGER_HOST"
REMOTE_ARCHIVE="/tmp/pineapple-pager-suite-$(date +%s)-$$.tar.gz"

printf '\nPineapple Pager Suite installer\n'
printf '  Target:   %s\n' "$PAGER_TARGET"
printf '  Payloads: %s\n' "$PAYLOAD_COUNT"
if [[ "$REPLACE_USER_CATEGORIES" -eq 1 ]]; then
    printf '  UCI mode: replace stock user categories\n\n'
else
    printf '  UCI mode: preserve existing configuration\n\n'
fi

info "Checking SSH access"
ssh "${SSH_ARGS[@]}" "$PAGER_TARGET" "test -d /root && command -v tar >/dev/null" \
    || fail "SSH connection failed or tar is unavailable on the Pager"
ok "SSH access verified"

ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/pineapple-pager-suite.XXXXXX.tar.gz")"
info "Building deployment archive"
tar --exclude='.git' -czf "$ARCHIVE" -C "$PAYLOAD_DIR" user recon alerts
ARCHIVE_SIZE="$(du -h "$ARCHIVE" | awk '{print $1}')"
ok "Archive ready ($ARCHIVE_SIZE)"

info "Copying payload archive to the Pager"
scp "${SCP_ARGS[@]}" -q "$ARCHIVE" "$PAGER_TARGET:$REMOTE_ARCHIVE"

info "Installing user, recon, and alert payloads"
ssh "${SSH_ARGS[@]}" "$PAGER_TARGET" \
    "set -e; archive='$REMOTE_ARCHIVE'; trap 'rm -f \"\$archive\"' EXIT; mkdir -p /root/payloads; tar -xzf \"\$archive\" -C /root/payloads"
ok "Payload files installed"

if [[ "$REPLACE_USER_CATEGORIES" -eq 1 ]]; then
    info "Replacing stock user category entries in /etc/config/payloads"
    ssh "${SSH_ARGS[@]}" "$PAGER_TARGET" sh -s -- "${USER_CATEGORIES[@]}" <<'REMOTE_SCRIPT'
set -eu

CONFIG_FILE=/etc/config/payloads
UCI_LIST='payloads.@directories[0].payloaddir'

command -v uci >/dev/null 2>&1 || {
    echo '[!] uci is unavailable on the Pager' >&2
    exit 1
}
[ -f "$CONFIG_FILE" ] || {
    echo '[!] /etc/config/payloads does not exist' >&2
    exit 1
}

BACKUP_FILE="${CONFIG_FILE}.suite-backup.$(date +%Y%m%d-%H%M%S).$$"
cp "$CONFIG_FILE" "$BACKUP_FILE"

for category in \
    evil_portal \
    exfiltration \
    games \
    general \
    incident_response \
    interception \
    prank \
    reconnaissance \
    remote_access \
    virtual_pager
do
    uci -q del_list "$UCI_LIST=user/$category" || true
done

for category in "$@"; do
    uci -q del_list "$UCI_LIST=$category" || true
    uci add_list "$UCI_LIST=$category"
done

uci commit payloads

for category in \
    evil_portal \
    exfiltration \
    games \
    general \
    incident_response \
    interception \
    prank \
    reconnaissance \
    remote_access \
    virtual_pager
do
    directory="/root/payloads/user/$category"
    if [ -d "$directory" ]; then
        if rmdir "$directory" 2>/dev/null; then
            echo "[+] Removed empty stock directory: $directory"
        else
            echo "[!] Preserved non-empty stock directory: $directory"
        fi
    fi
done

echo "[+] Previous UCI configuration backed up to $BACKUP_FILE"
REMOTE_SCRIPT
    ok "Suite user categories registered; alert and recon entries were left unchanged"
fi

info "Verifying installed payloads"
REMOTE_PAYLOAD_COUNT="$(ssh "${SSH_ARGS[@]}" "$PAGER_TARGET" \
    "find /root/payloads/user /root/payloads/recon /root/payloads/alerts -type f -name payload.sh 2>/dev/null | wc -l")"
REMOTE_PAYLOAD_COUNT="$(printf '%s' "$REMOTE_PAYLOAD_COUNT" | tr -d '[:space:]')"
[[ "$REMOTE_PAYLOAD_COUNT" =~ ^[0-9]+$ ]] || fail "could not verify the remote payload count"
(( REMOTE_PAYLOAD_COUNT >= PAYLOAD_COUNT )) \
    || fail "remote verification found fewer payloads than the suite contains ($REMOTE_PAYLOAD_COUNT < $PAYLOAD_COUNT)"

printf '\nInstallation complete.\n'
printf '  Suite payloads copied: %s\n' "$PAYLOAD_COUNT"
printf '  Payloads now found under the three remote roots: %s\n' "$REMOTE_PAYLOAD_COUNT"
printf '  Installed at: /root/payloads/{user,recon,alerts}\n'
if [[ "$REPLACE_USER_CATEGORIES" -eq 0 ]]; then
    printf '  Stock user category configuration was not changed.\n'
fi
