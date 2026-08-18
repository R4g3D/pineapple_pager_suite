#!/bin/bash
set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PAYLOAD_DIR=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
FIXTURE="$TEST_DIR/fixtures/hostapd-eap.log"
MANA_FIXTURE="$TEST_DIR/fixtures/mana-credentials.log"
TEST_OUTPUT=$(mktemp -d)

cleanup_test() {
    case "$(basename "$TEST_OUTPUT")" in
        tmp.*)
            case "$TEST_OUTPUT" in
                /tmp/*|/private/tmp/*|/var/folders/*/T/*) rm -rf "$TEST_OUTPUT" ;;
            esac
            ;;
    esac
}
trap cleanup_test EXIT

PINEAPOL_LIBRARY_ONLY=1 . "$PAYLOAD_DIR/payload.sh"
LOG() { :; }
MANA_CREDOUT="$MANA_FIXTURE"

# Simulate the Pager UI staging payload.sh away from its installed support
# files. An explicit installed-folder hint must still resolve the bundled bin.
mkdir -p "$TEST_OUTPUT/ui-stage"
cp "$PAYLOAD_DIR/payload.sh" "$TEST_OUTPUT/ui-stage/payload.sh"
PINEAPOL_PAYLOAD_DIR="$PAYLOAD_DIR" bash -c '
    export PINEAPOL_LIBRARY_ONLY=1
    . "$1"
    test "$PAYLOAD_DIR" = "$2"
    test -f "$MANA_BUNDLED_BIN"
' _ "$TEST_OUTPUT/ui-stage/payload.sh" "$PAYLOAD_DIR"

is_hostapd_version_output 'hostapd-mana v2.12
MANA Edition https://github.com/sensepost/hostapd-mana'
is_hostapd_version_output 'hostapd v2.12'
! is_hostapd_version_output 'unrelated program v2.12'

extract_eap_identities "$FIXTURE" | sort -u > "$TEST_OUTPUT/identities.actual"
grep -Fxq 'outer@example.com' "$TEST_OUTPUT/identities.actual"
grep -Fxq 'fixture-user' "$TEST_OUTPUT/identities.actual"
! grep -Fxq 'Peer' "$TEST_OUTPUT/identities.actual"

extract_contextual_cleartext "$FIXTURE" > "$TEST_OUTPUT/cleartext.actual"
grep -Fq $'GTC\tfixture-password' "$TEST_OUTPUT/cleartext.actual"

parse_credentials "$FIXTURE" "$TEST_OUTPUT"
grep -Fq $'aa:bb:cc:dd:ee:ff\t1' "$TEST_OUTPUT/eap_sessions.tsv"
grep -Fq $'failure\tauthentication-result' "$TEST_OUTPUT/eap_sessions.tsv"
grep -Fq $'outer@example.com\ttest\tPEAP' "$TEST_OUTPUT/eap_sessions.tsv"
grep -Fxq 'test' "$TEST_OUTPUT/identities.txt" || grep -Fxq 'outer@example.com' "$TEST_OUTPUT/identities.txt"
grep -Fxq 'User' "$TEST_OUTPUT/identities.txt"
grep -Fxq 'pap-user' "$TEST_OUTPUT/identities.txt"
grep -Fq $'TTLS-PAP\tpap-user\tfixture-pap-password' "$TEST_OUTPUT/mana_cleartext_creds.tsv"
grep -Fq $'EAP-GTC\tgtc-user\tfixture-gtc-password' "$TEST_OUTPUT/mana_cleartext_creds.tsv"
grep -Fq $'TTLS-CHAP\tchap-user\tffeeddccbbaa99887766554433221100\t00112233445566778899aabbccddeeff\t01' \
    "$TEST_OUTPUT/mana_chap.tsv"

effective_challenge=$(sed -n '2s/.*\t//p' "$TEST_OUTPUT/mschapv2_raw.tsv")
case "$effective_challenge" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) echo "Invalid derived MSCHAPv2 challenge: $effective_challenge" >&2; exit 1 ;;
esac

test -s "$TEST_OUTPUT/hashcat_5500.txt"
grep -Fxq 'User::::82309ecd8d708b5ea08faa3981cd83544233114a3d85d6df:d02e4386bce91226' \
    "$TEST_OUTPUT/hashcat_5500.txt"
test "$(grep -Fxc 'User::::82309ecd8d708b5ea08faa3981cd83544233114a3d85d6df:d02e4386bce91226' \
    "$TEST_OUTPUT/hashcat_5500.txt")" = 1
grep -Fq $'User\t5b5d7c7d7b3f2f3e3c2c602132262628\t21402324255e262a28295f2b3a337c7e\t82309ecd8d708b5ea08faa3981cd83544233114a3d85d6df\td02e4386bce91226' \
    "$TEST_OUTPUT/mschapv2_raw.tsv"

# Live monitoring consumes MANA's immediate stdout records, which are available
# before its dedicated credential file is necessarily flushed.
LIVE_MANA_FIXTURE="$TEST_OUTPUT/live-mana.log"
cat > "$LIVE_MANA_FIXTURE" << 'EOF'
MANA EAP EAP-MSCHAPV2 HASHCAT | fixture-one::::03e3368898f83ae16bc694025a6f62d8cd5f22be57530371:31eaa0499a8ceb48
MANA EAP EAP-MSCHAPV2 HASHCAT | testing::::810a78653a7cf5e9818bdf8ddf42bffecb0829fe16d04f01:604a3d8c04124aff
MANA EAP EAP-MSCHAPV2 HASHCAT | hello::::663c171e5b0227bd65ec7e14e6979330d0c4ec63d38c1d91:2fd64e09365cc1e1
EOF
extract_mana_hashcat_hostapd "$LIVE_MANA_FIXTURE" > "$TEST_OUTPUT/live-mana.actual"
test "$(wc -l < "$TEST_OUTPUT/live-mana.actual" | tr -d ' ')" = 3
grep -Fxq 'testing::::810a78653a7cf5e9818bdf8ddf42bffecb0829fe16d04f01:604a3d8c04124aff' \
    "$TEST_OUTPUT/live-mana.actual"

publish_unique_lines_atomic "$TEST_OUTPUT/live-hashcat.txt" "$(cat "$TEST_OUTPUT/live-mana.actual")"
test "$(wc -l < "$TEST_OUTPUT/live-hashcat.txt" | tr -d ' ')" = 3

# RFC 2759 section 9 example: ChallengeHash must be D02E4386BCE91226.
rfc_challenge=$(derive_mschapv2_challenge \
    '21402324255E262A28295F2B3A337C7E' \
    '5B5D7C7D7B3F2F3E3C2C602132262628' \
    'User')
test "$rfc_challenge" = 'd02e4386bce91226'

EAP_PROFILE_DIR="$TEST_OUTPUT/eap-profiles"
SESSION_LOG=""
mkdir -p "$EAP_PROFILE_DIR"
for profile in broad peap-mschapv2 peap-gtc ttls-pap ttls-mschapv2 eap-tls fast md5; do
    EAP_PROFILE="$profile"
    EAP_USER_FILE="$TEST_OUTPUT/$profile.eap_user"
    write_eap_user_file
    test -s "$EAP_USER_FILE"
done

! grep -Rq '"anonymous".*\[2\]' "$TEST_OUTPUT"/*.eap_user
for tunneled_profile in broad peap-mschapv2 peap-gtc ttls-pap ttls-mschapv2 fast; do
    grep -Eq '^"t"[[:space:]].*\[2\]$' "$TEST_OUTPUT/$tunneled_profile.eap_user"
    ! grep -Eq '^\*[[:space:]].*\[2\]$' "$TEST_OUTPUT/$tunneled_profile.eap_user"
done

EAP_PROFILE="peap-mschapv2"
EAP_USER_FILE="$TEST_OUTPUT/peap-mschapv2.eap_user"
HOSTAPD_CONF="$TEST_OUTPUT/hostapd.conf"
CERT_DIR="$TEST_OUTPUT/certificates"
PINEAPOL_IFACE="wlan_test"
write_hostapd_config 'FixtureSSID' 6
hostapd_config_is_managed "$HOSTAPD_CONF"
grep -Fxq 'eap_server=1' "$HOSTAPD_CONF"
grep -Fxq 'mana_wpe=1' "$HOSTAPD_CONF"
grep -Fxq "mana_credout=$MANA_CREDOUT" "$HOSTAPD_CONF"
grep -Fxq 'enable_mana=0' "$HOSTAPD_CONF"
grep -Fxq 'mana_eapsuccess=0' "$HOSTAPD_CONF"
grep -Fxq 'mana_eaptls=0' "$HOSTAPD_CONF"
! grep -q '^eap_fast_' "$HOSTAPD_CONF"

test -f "$PAYLOAD_DIR/bin/hostapd-mana-mipsel_24kc"
test "$(calculate_sha256 "$PAYLOAD_DIR/bin/hostapd-mana-mipsel_24kc")" = "$MANA_EXPECTED_SHA256"

PINEAPOL_HOME="$TEST_OUTPUT/persistent"
LOOT_DIR="$PINEAPOL_HOME/sessions"
PERSISTENT_CONFIG_DIR="$PINEAPOL_HOME/config"
EAP_PROFILE_DIR="$PERSISTENT_CONFIG_DIR/eap-profiles"
HOSTAPD_CACHE_DIR="$PINEAPOL_HOME/bin"
CERT_STORE="$PINEAPOL_HOME/certificates"
CURRENT_LINK="$PINEAPOL_HOME/current"
TARGET_SSID=""
initialize_persistent_storage
test -d "$SESSION_RESULTS_DIR"
test -f "$SESSION_LOG"
test -d "$RUNTIME_DIR"
test -d "$RUNTIME_LOCK_DIR"
test "$(sed -n '1p' "$PAYLOAD_PID_FILE")" = "$$"
test -s "$PAYLOAD_START_FILE"
# Simulate a concurrent launcher: it must not steal a live owner's lock.
RUNTIME_LOCK_HELD=0
! acquire_runtime_lock
RUNTIME_LOCK_HELD=1
TARGET_SSID="Fixture SSID"
rename_session_for_target
case "$SESSION_DIR" in "$PINEAPOL_HOME"/sessions/*_Fixture_SSID) ;; *) exit 1 ;; esac
release_runtime_lock
test ! -d "$RUNTIME_LOCK_DIR"

# A lock whose owner is no longer alive is recoverable.
mkdir "$RUNTIME_LOCK_DIR"
printf '%s\n' 999999 > "$PAYLOAD_PID_FILE"
printf '%s\n' 1 > "$PAYLOAD_START_FILE"
acquire_runtime_lock
test "$(sed -n '1p' "$PAYLOAD_PID_FILE")" = "$$"
release_runtime_lock

unmanaged_hostapd_conf="$TEST_OUTPUT/unmanaged-hostapd.conf"
printf '%s\n' '# pinEAPol hostapd-mana configuration' 'interface=wlan1mon' > "$unmanaged_hostapd_conf"
! hostapd_config_is_managed "$unmanaged_hostapd_conf"
! grep -Eq '(pkill|killall)' "$PAYLOAD_DIR/payload.sh"

# Simulate a payload parent that vanished without running EXIT cleanup. The
# supervisor must remove only wlan_pineapol, clear stale state, and release the
# dead owner's lock even when no child process remains.
watchdog_home="$TEST_OUTPUT/watchdog"
watchdog_session="$watchdog_home/sessions/fixture"
mkdir -p "$watchdog_home/run/lock" "$watchdog_session/config" "$watchdog_session/logs"
printf '%s\n' "$watchdog_session/config/hostapd.conf" > "$watchdog_home/run/hostapd.config"
printf '%s\n' 999999 > "$watchdog_home/run/lock/payload.pid"
printf '%s\n' 1 > "$watchdog_home/run/lock/payload.start"
touch "$TEST_OUTPUT/wlan_pineapol.exists"
iw() {
    case "$*" in
        "dev wlan_pineapol info") [ -e "$TEST_OUTPUT/wlan_pineapol.exists" ] ;;
        "dev wlan_pineapol del") rm -f "$TEST_OUTPUT/wlan_pineapol.exists" ;;
        *) return 1 ;;
    esac
}
ifconfig() { :; }
(
    cleanup_watchdog_main 999999 1 "$watchdog_home" /proc wlan_pineapol \
        "$MANA_EXPECTED_SHA256"
)
test ! -e "$TEST_OUTPUT/wlan_pineapol.exists"
test ! -d "$watchdog_home/run/lock"
grep -Fq 'Detached watchdog cleanup complete' "$watchdog_session/logs/session.log"
unset -f iw ifconfig

CERT_CN='unsafe/value'
CERT_DNS_SANS=''
CERT_KEY_BITS=1234
normalize_certificate_settings
test "$CERT_CN" = 'radius-server-auth.local'
test "$CERT_DNS_SANS" = 'radius-server-auth.local'
test "$CERT_KEY_BITS" = 2048

test "$(eap_profile_label broad)" = 'Broad / automatic'
test "$(eap_profile_label peap-mschapv2)" = 'PEAP + MSCHAPv2 [hash]'

PROMPT() { return 0; }
NUMBER_PICKER() { printf '%s' 2; }
fallback_choice=$(ui_list_picker "Fixture Picker" "First" "First" "Second")
test "$fallback_choice" = 'Second'
unset -f PROMPT NUMBER_PICKER

LIST_PICKER() { printf '%s' "$3"; }
native_choice=$(ui_list_picker "Fixture Picker" "Second" "First" "Second")
test "$native_choice" = 'Second'
unset -f LIST_PICKER

mkdir -p "$CERT_STORE/alpha" "$CERT_STORE/beta" "$CERT_STORE/ignored"
touch "$CERT_STORE/alpha/profile.conf" "$CERT_STORE/beta/profile.conf"
discovered_profiles=$(discover_certificate_profiles)
printf '%s\n' "$discovered_profiles" | grep -Fxq alpha
printf '%s\n' "$discovered_profiles" | grep -Fxq beta
! printf '%s\n' "$discovered_profiles" | grep -Fxq ignored

# A launcher that does not own the runtime lock must not tear down the active
# instance when its EXIT cleanup runs.
cleanup_probe="$TEST_OUTPUT/non-owner-cleanup-called"
stop_runtime_watchdog() { touch "$cleanup_probe"; }
stop_managed_hostapd() { touch "$cleanup_probe"; }
stop_capture() { touch "$cleanup_probe"; }
remove_managed_interfaces() { touch "$cleanup_probe"; }
LED() { :; }
RUNTIME_LOCK_HELD=0
CLEANUP_ACTIVE=0
SESSION_LOG=""
SESSION_DIR=""
START_TIME=""
cleanup
test ! -e "$cleanup_probe"

# An owning cleanup must leave its detached supervisor active until hostapd,
# tcpdump, and the managed interface have all been handled.
cleanup_order=""
stop_managed_hostapd() { cleanup_order="${cleanup_order} hostapd"; }
stop_capture() { cleanup_order="${cleanup_order} capture"; }
remove_managed_interfaces() { cleanup_order="${cleanup_order} interface"; }
stop_runtime_watchdog() { cleanup_order="${cleanup_order} watchdog"; }
release_runtime_lock() { cleanup_order="${cleanup_order} unlock"; }
RUNTIME_LOCK_HELD=1
CLEANUP_ACTIVE=0
cleanup
test "$cleanup_order" = " hostapd capture interface watchdog unlock"

grep -Fq 'setsid "$bash_bin" "$PAYLOAD_DIR/payload.sh" --cleanup-watchdog' "$PAYLOAD_DIR/payload.sh"
grep -Fq "trap '' HUP INT TERM QUIT" "$PAYLOAD_DIR/payload.sh"

echo "pinEAPol parser fixtures passed"
