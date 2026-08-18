# pinEAPol

**Type:** User Payload  
**Category:** Capture  
**Author:** R4g3D  
**Version:** 3.5

pinEAPol is a WiFi Pineapple Pager payload for authorized WPA-Enterprise
assessment. It discovers or accepts a target and deploys a configurable test AP
using hostapd-mana's built-in EAP server and WPE credential writer. It preserves
EAP identities and method negotiation, plaintext exposed through GTC/PAP, CHAP
material, MSCHAPv2 challenge-response data, raw hostapd diagnostics, and an
optional EAPOL packet capture.

The supplied password verifier is intentionally a dummy account. Unknown
credentials normally fail authentication, but supported methods can still yield
capture material before that failure occurs.

Use pinEAPol only on networks and devices covered by explicit written authorization.

## Major features

- Persistent runtime storage; pinEAPol does not use `/tmp` for its own data.
- Bundled, pinned `mipsel_24kc` hostapd-mana backend with checksum and runtime validation.
- Persistent hostapd-mana installation that never replaces the system hostapd/wpad package.
- Named, reusable certificate profiles editable from the Pager UI.
- Native list-based EAP and certificate selection with older-firmware fallback.
- Pre-deployment configuration review with change and cancel actions.
- Certificate reuse and expiry-aware renewal.
- Broad and focused EAP configuration profiles.
- BusyBox-compatible parsing without `grep -P`.
- Per-station EAP session events in TSV format.
- MANA's structured output as the primary MSCHAPv2 and plaintext source.
- Correct MSCHAPv2 effective-challenge derivation from debug output as a fallback.
- One-second incremental monitoring of MANA's immediate MSCHAPv2 Hashcat events,
  plus a lightweight check of MANA's credential file for GTC/PAP records.
- Atomic result publication, so readers never observe a truncated or partially
  rebuilt credential file.
- Raw `hostapd -ddd -K` message-dump logging and optional tcpdump retention.
- Verified tcpdump startup with persistent diagnostics and clean PCAP flushing.
- Crash-safe sessions: cleanup stops services but does not delete evidence.
- Ownership-validated runtime recovery that never targets the Pager's system hostapd.
- Persistent PID/start-time records, an exclusive-run lock, and a detached cleanup supervisor.

## Compatibility and requirements

The bundled backend was built for the WiFi Pineapple Pager firmware target
`ramips/mt76x8`, architecture `mipsel_24kc`, using the OpenWrt 24.10.1 SDK. It is
not a general-purpose hostapd-mana binary for other Pineapple models or CPU
architectures.

Required on the Pager:

- Bash (the payload uses arrays, local variables, and here-strings)
- `openssl`, supplied by `openssl-util`
- `iw` and `ifconfig`
- `iwinfo` for automatic enterprise-network discovery; manual SSID/channel entry
  remains available if discovery returns no results
- A radio that advertises AP mode; pinEAPol prefers `phy1` and falls back to
  `phy0`
- The bundled executable at `bin/hostapd-mana-mipsel_24kc`

`tcpdump` is optional and enables the EAPOL PCAP. `opkg` and network access are
needed only if the UI offers to install missing command dependencies.

The bundled binary was built from hostapd-mana commit
`785ced85088725913df1202b85a99ac3724caa4b`. Its expected SHA-256 is
`0c1c6b332ba13e1c2b07b3375b5de4c5f8390ce9a6f092152795ef0477a8c2b7`.

## Persistent layout

```text
/root/loot/pineapol/
├── config/
│   ├── pineapol.conf
│   └── eap-profiles/
├── bin/
│   ├── mana-<source-commit>/
│   │   ├── hostapd
│   │   └── manifest
│   ├── mana-current -> mana-<source-commit>/
│   └── mana-current.manifest
├── certificates/
│   └── <profile>/
├── sessions/
│   └── <timestamp>_<ssid>/
│       ├── config/
│       ├── logs/
│       ├── captures/
│       ├── results/
│       └── work/
├── run/
│   ├── lock/                         # present only while a run owns the lock
│   ├── hostapd.pid
│   ├── hostapd.start
│   ├── hostapd.config
│   ├── tcpdump.pid
│   └── tcpdump.start
└── current -> sessions/<latest-session>/
```

pinEAPol starts with `umask 077`. Persistent settings, private keys, cached
binaries, logs, and parsed results receive restrictive permissions. It does not
place its runtime state or engagement evidence in `/tmp`.

## Runtime ownership and recovery

Only one pinEAPol instance may own the runtime lock. Before terminating a
process, pinEAPol validates the recorded PID and process start time, the pinned
executable's SHA-256, and the generated configuration marker. This excludes the
Pager's `/usr/sbin/hostapd` service.

At startup, pinEAPol recovers validated stale MANA processes and removes only
its `wlan_pineapol` virtual AP interface. A cleanup supervisor runs in a
separate session, ignores the Pager UI's normal payload-group termination
signals, and performs the same scoped teardown if the parent disappears without
running its shell traps. It validates the recorded PID, process start time,
binary checksum, and generated configuration before signaling hostapd-mana.
Next-run recovery remains as a second safeguard after power loss or a forced
device shutdown.

An orderly stop flushes hostapd and tcpdump, performs the comprehensive final
parse, and creates the report. If power loss or forced termination prevents that
harvest step, the raw hostapd and MANA logs remain the authoritative evidence,
but derived result files may reflect only the last completed live update.

If hostapd reports a busy radio, the session's `logs/radio-state.log` records
`iw dev`, hostapd processes, and pinEAPol's runtime ownership state.

## Hostapd-mana backend

The payload carries a pinned MIPS hostapd-mana executable in its `bin/`
directory. On first use, pinEAPol copies it to the persistent
`bin/mana-<source-commit>/` directory. Subsequent sessions reuse that copy when
its SHA-256 still matches.

Before each session, pinEAPol verifies the checksum, executes `hostapd -v`,
checks for the `mana_wpe` and `mana_credout` features, and checks dynamic
libraries when `ldd` is available. A failed candidate is never launched.
pinEAPol does not download a vanilla OpenWrt hostapd package as a fallback,
because that would silently lose the WPE credential writer.

The bundled MANA build is pinned and is not automatically replaced from the
network. Updating it requires shipping a new compatible binary and updating its
commit and checksum metadata in the payload.

Of MANA's optional extensions, the payload enables only `mana_wpe`. Karma probe
responses, forced EAP success, and accept-any-client-certificate behavior remain
disabled.

## Certificate profiles

At runtime, pinEAPol discovers saved certificate profiles and presents them in a
scrollable list. A selected profile can be used unchanged, edited, or
regenerated. New named profiles can be created from the same menu. Configurable
fields include:

- CA and server common names
- Organization and organizational unit
- Country, state, and locality
- Comma-separated DNS and IP SANs
- Validity period
- RSA and Diffie-Hellman key sizes
- Forced regeneration

Profile data is parsed as data and is never sourced as shell code. Certificate
text is validated before being placed into OpenSSL configuration.

Certificates are reused when the profile is unchanged and the server certificate
remains valid beyond the renewal threshold. Generation occurs in the persistent
session work directory, and a verified candidate is copied into the profile only
after `openssl verify` succeeds.

The selected profile and server-certificate SHA-256 fingerprint are recorded in
every session that reaches certificate setup.

## EAP profiles

The Pager presents these choices in a scrollable list, with the previously
selected profile highlighted:

| UI choice | Outer method | Inner method or expected evidence |
|---|---|---|
| Broad / automatic | PEAP, TTLS, TLS, FAST, MD5 | MSCHAPv2, GTC, TTLS-PAP, or TTLS-MSCHAPv2 |
| PEAP + MSCHAPv2 | PEAPv0 | MSCHAPv2 Hashcat record |
| PEAP + GTC | PEAPv0 | Potential cleartext GTC response |
| TTLS + PAP | TTLS | Potential cleartext PAP credentials |
| TTLS + MSCHAPv2 | TTLS | MSCHAPv2 Hashcat record |
| EAP-TLS | TLS | Client-certificate negotiation; no password |
| FAST + MSCHAPv2/GTC | FAST | MSCHAPv2 record or potential GTC cleartext |
| EAP-MD5 | MD5 | Legacy challenge-response material |

Broad mode retains multiple outer and inner methods but does not include the
invalid anonymous phase-2 outer-method entry. Focused profiles are useful when
broad negotiation reveals what a client supports.

All tunneled profiles use MANA WPE's synthetic `"t"` phase-2 identity. MANA
rewrites the client's inner identity to this value for its EAP-user lookup before
issuing the configured inner-method challenge; the client's original identity
remains available in the logs and parsed results.

An in-menu help entry explains the expected result of each profile. Before any
certificate generation, interface creation, or AP deployment, pinEAPol displays
a configuration summary and allows the EAP profile, certificate profile, and
deauthentication choice to be changed.

Unknown MSCHAPv2 passwords normally fail verification against the configured
dummy password. A MANA Hashcat event emitted before the failure remains a valid
capture. pinEAPol does not claim that arbitrary credentials will authenticate
successfully.

## Runtime flow

1. Scan `wlan1`, falling back to `wlan1mon`, for advertised enterprise networks;
   or enter an SSID and channel manually.
2. Select the EAP and certificate profiles.
3. Optionally request one broadcast deauthentication burst. This choice is
   disabled by default and is unavailable for a manually entered target because
   no target BSSID is known.
4. Review the complete setup before certificate generation or radio changes.
5. Deploy `wlan_pineapol`, start hostapd-mana, and optionally start tcpdump.
6. Monitor new log data once per second. Each distinct MANA MSCHAPv2 record is
   published atomically and triggers the capture notification.
7. Press a Pager button to stop, flush processes, remove `wlan_pineapol`, run the
   final parser, and generate the report.

## Session output

A normally deployed and orderly harvested session has the following layout:

```text
sessions/<timestamp>_<ssid>/
├── certificate-fingerprint.txt
├── duration.txt
├── config/
│   ├── certificate-profile.conf
│   ├── eap_users
│   ├── hostapd.conf
│   ├── openssl.conf                 # when a certificate is generated
│   └── session.conf
├── logs/
│   ├── hostapd.log
│   ├── hostapd-mana-validation.log
│   ├── mana-credentials.log
│   ├── tcpdump.log                  # when tcpdump is available
│   ├── radio-state.log              # when radio startup fails
│   └── session.log
├── captures/
│   └── eap_capture.pcap             # when tcpdump is invoked
├── results/
│   ├── identities.txt
│   ├── cleartext_creds.tsv
│   ├── eap_sessions.tsv
│   ├── mana_cleartext_creds.tsv
│   ├── mana_mschapv2.tsv
│   ├── mana_chap.tsv
│   ├── mschapv2_raw.tsv
│   ├── hashcat_5500.txt
│   └── report.txt
└── work/
    ├── live-hostapd.delta           # rolling live-parser input
    └── certificate-generation/      # when certificate generation occurs
```

`duration.txt`, the comprehensive TSV files, and `report.txt` are finalized by
an orderly harvest. Conditional or empty files may be absent when their optional
producer is unavailable or when a run ends unexpectedly.

`eap_sessions.tsv` associates observed events with a station MAC and session
number where hostapd supplies enough context. Lines without a resolvable station
are retained as `unknown`; pinEAPol does not invent an association.

Plaintext output is limited to values emitted by MANA's PAP/GTC callback or
appearing in a verified GTC/PAP debug context. A generic `Response=` debug value
is not automatically treated as a password.

MANA writes MSCHAPv2 records directly in Hashcat mode 5500 form. Live monitoring
consumes MANA's immediate hostapd event stream, so a distinct response should be
reported on the next approximately one-second polling cycle. It does not reparse
the complete, growing debug log.

During final harvest, the dedicated credential file and immediate hostapd MANA
events are combined and deduplicated. `mana_mschapv2.tsv` splits those records
into username, NT response, and effective challenge. The debug parser preserves
authenticator challenge, peer challenge, NT response, and the locally derived
effective challenge only as a fallback when MANA did not provide that response.
Each published result file is replaced atomically.

To test an MSCHAPv2 capture against an authorized wordlist:

```sh
hashcat -m 5500 /path/to/session/results/hashcat_5500.txt wordlist.txt
```

## Installation

```sh
mkdir -p /mmc/root/payloads/user/capture
cp -r pineapol /mmc/root/payloads/user/capture/
chmod +x /mmc/root/payloads/user/capture/pineapol/payload.sh
```

Copy the complete directory, including `bin/`; copying only `payload.sh` will
fail backend validation. The installed directory and loot namespace are named
`pineapol`; the payload title remains **WPA-Enterprise Credential Harvester**
in the Pager UI.

The script checks its core command dependencies and offers to install missing
ones with `opkg`. It never installs over the system hostapd/wpad service.

## Verification

Repository-side checks:

```sh
bash -n payload.sh
tests/test_parsers.sh
grep -nE 'grep[[:space:]]+-[^[:space:]]*P' payload.sh
grep -n '/tmp/' payload.sh
```

The two `grep` checks should produce no output. `tests/test_parsers.sh` is a
repository-side regression test and is not required on the Pager.

Pager-side checks during a session:

```sh
readlink -f /root/loot/pineapol/current
cat /root/loot/pineapol/current/config/eap_users
cat /root/loot/pineapol/current/config/hostapd.conf
tail -f /root/loot/pineapol/current/logs/hostapd.log
tail -f /root/loot/pineapol/current/logs/mana-credentials.log
cat /root/loot/pineapol/current/results/hashcat_5500.txt

grep -Ein \
'PEAP|TTLS|FAST|TLS|MSCHAP|GTC|PAP|Identity|Phase 2|method|SUCCESS|FAIL|NAK' \
/root/loot/pineapol/current/logs/hostapd.log
```

Verify persistent backend reuse by running pinEAPol twice and confirming that
the same validated binary is selected:

```sh
readlink -f /root/loot/pineapol/bin/mana-current
cat /root/loot/pineapol/bin/mana-current.manifest
sha256sum /root/loot/pineapol/bin/mana-current/hostapd
```

## Troubleshooting

If hostapd fails, inspect:

```sh
cat /root/loot/pineapol/current/logs/hostapd-mana-validation.log
tail -n 100 /root/loot/pineapol/current/logs/hostapd.log
cat /root/loot/pineapol/current/logs/mana-credentials.log
```

Relevant EAP diagnostics:

```sh
grep -Ein \
'EAP-Response/Identity|Response-PEAP|EAP-PEAP|EAP-TTLS|EAP-FAST|EAP-MSCHAPV2|MSCHAPV2|GTC|PAP|Phase 2|NAK|PROPOSED-METHOD|EAP-SUCCESS|EAP-FAILURE|Supplicant used different EAP type|TLS:|SSL:' \
/root/loot/pineapol/current/logs/hostapd.log
```

The raw hostapd log, MANA credential log, and PCAP should be retained when
requesting further analysis.

An EAP failure after a `MANA EAP ... HASHCAT` line does not invalidate that
challenge-response capture; failure is expected for a password that does not
match the dummy verifier. If a run was forcibly terminated and parsed results
appear incomplete, check both `logs/mana-credentials.log` and the `MANA EAP`
lines in `logs/hostapd.log` before concluding that no credential was captured.

## Credits

pinEAPol was originally based on VENOM by sinXneo and was subsequently rewritten
around hostapd-mana, persistent Pager-native storage, structured parsing, runtime
ownership validation, and the current UI flow. hostapd-mana is a SensePost
project. See `THIRD_PARTY_NOTICES.md` for the bundled binary's provenance and
license notice.

## Legal notice

pinEAPol handles sensitive authentication material. Use it only within an
explicitly authorized assessment scope, protect retained sessions appropriately,
and follow applicable interception, privacy, and disclosure requirements.
