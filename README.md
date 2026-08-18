# Pineapple Pager Suite

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform: WiFi Pineapple Pager](https://img.shields.io/badge/Platform-WiFi%20Pineapple%20Pager-2ea44f)](https://hak5.org/)
[![Payloads: 187](https://img.shields.io/badge/Payloads-187-orange)](#included-payloads)

A reproducible WiFi Pineapple Pager payload suite containing pinEAPol, Loki,
PagerGotchi, and 184 payloads from the Hak5 community library. Payloads are
pinned as independently maintained Git submodules at Pager-native paths.

> [!WARNING]
> These payloads are intended only for authorized security assessments and
> controlled research. Use them solely on networks, systems, accounts, and
> devices covered by explicit written authorization. Protect captured
> credentials, handshakes, logs, and other retained engagement evidence.

## What is the Pineapple Pager Suite?

The Pineapple Pager Suite provides independently maintained and community
developed Pager payloads in one reproducible repository:

- **pinEAPol** performs controlled WPA-Enterprise EAP assessment and evidence
  capture with a verified hostapd-mana backend.
- **Loki** provides autonomous network discovery, service enumeration,
  credential testing, vulnerability scanning, and authorized data collection.
- **PagerGotchi** automates wireless discovery and WPA handshake/PMKID capture
  with interactive targeting, privacy, and display controls.
- **Hak5 user payloads** provide 164 community payloads across nine namespaced
  categories, including general utilities, reconnaissance, games,
  interception, exfiltration, remote access, Evil Portal tools, pranks, and
  Virtual Pager tools.
- **Hak5 alert and contextual recon payloads** provide 9 event-driven alert
  handlers and 11 access-point/client actions at the exact system paths
  expected by the Pager.

The suite records an explicit payload commit at every required Pager path while
`.gitmodules` identifies the long-lived payload branch used for deliberate
updates. A normal checkout therefore remains reproducible instead of silently
changing when a branch advances. The three original payloads use one submodule
each; the Hak5 fork uses one submodule per user category plus dedicated alert
and recon submodules so every payload retains the layout required by the Pager.

## Documentation map

- [Review the included payloads](#included-payloads)
- [Clone the complete suite](#installation)
- [Deploy it to a Pager](#deploy-to-the-pager)
- [Choose how user categories are handled](#optional-replace-the-stock-user-categories)
- [Understand the repository layout](#repository-layout)
- [Update payload branches safely](#updating-the-suite)
- [Verify a checkout](#verification)
- [Resolve common problems](#troubleshooting)

## Included payloads

| Payload | Suite path | Purpose | Source |
|---|---|---|---|
| **pinEAPol** | `payloads/user/capture/pineapol` | Authorized WPA-Enterprise EAP assessment and evidence capture | [R4g3D/pineapple_pager_pineapol](https://github.com/R4g3D/pineapple_pager_pineapol) |
| **Loki** | `payloads/user/pager-apps/loki` | Autonomous LAN reconnaissance, service testing, and Pager-native reporting | [R4g3D/pineapple_pager_loki](https://github.com/R4g3D/pineapple_pager_loki) |
| **PagerGotchi** | `payloads/user/pager-apps/pagergotchi` | Wireless discovery and WPA handshake/PMKID capture companion | [R4g3D/pineapple_pager_pagergotchi](https://github.com/R4g3D/pineapple_pager_pagergotchi) |
| **Hak5 Evil Portal** (10) | `payloads/user/hak5-evil-portal` | Evil Portal installation, configuration, and control | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Exfiltration** (6) | `payloads/user/hak5-exfiltration` | Authorized data transfer and capture workflows | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Games** (11) | `payloads/user/hak5-games` | Games and interactive demonstrations | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 General** (81) | `payloads/user/hak5-general` | Pager utilities, configuration, diagnostics, and management | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Interception** (5) | `payloads/user/hak5-interception` | Authorized portal and traffic-interception workflows | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Prank** (4) | `payloads/user/hak5-prank` | Non-destructive demonstration payloads | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Reconnaissance** (32) | `payloads/user/hak5-reconnaissance` | Wireless, network, Bluetooth, and OSINT reconnaissance | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Remote Access** (13) | `payloads/user/hak5-remote-access` | Authorized remote connectivity and administration | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Virtual Pager** (2) | `payloads/user/hak5-virtual-pager` | Virtual Pager display customization | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Alerts** (9) | `payloads/alerts` | Event-driven handlers for deauth, handshake, authentication, and client events | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Contextual Recon** (11) | `payloads/recon` | Actions launched against selected access points and clients | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |

The payload repositories contain their own detailed requirements, controls,
output locations, technical notes, and legal guidance. Read the relevant
payload documentation before an engagement. Hak5 library payloads are
community-developed; inclusion records a reviewed source and deployable layout,
but does not imply that every payload has been functionally tested on every
firmware or hardware configuration.

## Requirements

- A Hak5 WiFi Pineapple Pager.
- Git with submodule support on the workstation used to clone the suite.
- SSH access to the Pager for manual deployment.
- Enough Pager storage for the complete suite, particularly Loki's bundled
  binaries, Python packages, web assets, themes, and the Hak5 community
  library.
- Any network access required by an individual payload's documented first-run
  dependency checks.

Payload-specific hardware and operational requirements still apply. For
example, pinEAPol needs an AP-capable radio, Loki needs a connected target
network, and PagerGotchi benefits from an optional monitor-capable secondary
adapter.

## Installation

Clone the suite and initialize all payload submodules in one command:

```sh
git clone --recurse-submodules git@github.com:R4g3D/pineapple_pager_suite.git
cd pineapple_pager_suite
```

The submodules use HTTPS URLs, so an HTTPS superproject clone works too:

```sh
git clone --recurse-submodules https://github.com/R4g3D/pineapple_pager_suite.git
cd pineapple_pager_suite
```

If the repository was cloned without `--recurse-submodules`, initialize the
payloads afterward:

```sh
git submodule sync --recursive
git submodule update --init --recursive
```

## Deploy to the Pager

The included installer packages all three payload roots, copies them over SSH,
extracts them beneath `/root/payloads`, and verifies the number of payloads on
the Pager. Run it from the suite checkout on your workstation:

```sh
./install.sh
```

The default Pager address is `172.16.52.1`. You can supply another address as a
positional argument or use the explicit connection options:

```sh
./install.sh 172.16.52.1

./install.sh \
  --host 172.16.52.1 \
  --port 22 \
  --identity ~/.ssh/id_ed25519
```

Run `./install.sh --help` for all options. The script checks the checkout and
SSH connection before transferring anything. It preserves file modes, excludes
Git metadata, and does not delete existing payloads on the Pager.

The suite's `payloads/` directory mirrors `/root/payloads/` on the Pager. For a
manual installation, create and transfer the same deployment archive:

```sh
tar --exclude='.git' \
  -czf pineapple-pager-suite.tar.gz \
  -C payloads .

scp pineapple-pager-suite.tar.gz root@<pager-ip>:/tmp/
ssh root@<pager-ip> \
  'mkdir -p /root/payloads && \
   tar -xzf /tmp/pineapple-pager-suite.tar.gz -C /root/payloads && \
   rm /tmp/pineapple-pager-suite.tar.gz'
```

After extraction, the installed payloads are located at:

```text
/root/payloads/user/capture/pineapol
/root/payloads/user/hak5-evil-portal/<payload>
/root/payloads/user/hak5-exfiltration/<payload>
/root/payloads/user/hak5-games/<payload>
/root/payloads/user/hak5-general/<payload>
/root/payloads/user/hak5-interception/<payload>
/root/payloads/user/hak5-prank/<payload>
/root/payloads/user/hak5-reconnaissance/<payload>
/root/payloads/user/hak5-remote-access/<payload>
/root/payloads/user/hak5-virtual-pager/<payload>
/root/payloads/user/pager-apps/loki
/root/payloads/user/pager-apps/pagergotchi
/root/payloads/alerts/<event>/hak5-<payload>
/root/payloads/recon/<target-type>/hak5-<payload>
```

The alert event directories and recon target-type directories are fixed Pager
integration points. Their payload leaf directories and displayed titles use a
Hak5 prefix so they remain distinguishable from custom handlers and actions.

The archive is ignored by this repository and can be removed locally after
deployment.

### Optional: replace the stock user categories

Pager firmware records its expected payload directories in
`/etc/config/payloads`. The stock `user/...` entries can cause empty default
category folders to be recreated after they are removed. A normal installer
run deliberately leaves this configuration unchanged.

To remove only the ten stock user-category entries and register the suite's
top-level user categories instead, opt in explicitly:

```sh
./install.sh --replace-user-categories
```

This mode registers the following user categories:

```text
capture
hak5-evil-portal
hak5-exfiltration
hak5-games
hak5-general
hak5-interception
hak5-prank
hak5-reconnaissance
hak5-remote-access
hak5-virtual-pager
pager-apps
```

The installer does not remove or change the firmware's `alerts/...` and
`recon/...` entries. Before changing UCI, it creates a timestamped backup such
as `/etc/config/payloads.suite-backup.20260818-120000.1234`. It uses `rmdir` for
the old stock folders, so a directory containing payload data is reported and
preserved rather than deleted recursively.

Nested custom category behavior can vary with Pager firmware. The suite
therefore registers only the immediate directories below `user/`; alert event
folders and recon target folders retain their firmware-defined paths. Firmware
updates or factory resets may restore the stock UCI manifest, in which case run
the installer with this option again.

## Repository layout

```text
pineapple_pager_suite/
├── .gitmodules
├── .gitignore
├── install.sh
├── LICENSE
├── README.md
└── payloads/
    ├── alerts/              # Git submodule: suite-payload/alerts
    ├── recon/               # Git submodule: suite-payload/recon
    └── user/
        ├── capture/
        │   └── pineapol/       # Git submodule: suite-payload
        ├── hak5-evil-portal/    # Git submodule: suite-payload/evil-portal
        ├── hak5-exfiltration/   # Git submodule: suite-payload/exfiltration
        ├── hak5-games/          # Git submodule: suite-payload/games
        ├── hak5-general/        # Git submodule: suite-payload/general
        ├── hak5-interception/   # Git submodule: suite-payload/interception
        ├── hak5-prank/          # Git submodule: suite-payload/prank
        ├── hak5-reconnaissance/ # Git submodule: suite-payload/reconnaissance
        ├── hak5-remote-access/  # Git submodule: suite-payload/remote-access
        ├── hak5-virtual-pager/  # Git submodule: suite-payload/virtual-pager
        └── pager-apps/
            ├── loki/           # Git submodule: suite-payload
            └── pagergotchi/    # Git submodule: suite-payload
```

The Loki and PagerGotchi payloads are installed together under **Pager Apps**.
Their launch scripts use those paths to hand control between the two apps.

## Branch model

The pinEAPol, Loki, and PagerGotchi repositories each have two suite branches:

- `suite-source` contains the full source repository layout plus the suite
  integration changes.
- `suite-payload` is generated from the Pager payload directory with
  `git subtree split` and places the deployable payload at the branch root.

The suite stores a gitlink to a specific `suite-payload` commit. The branch
entry in `.gitmodules` is used only when an operator explicitly requests a
remote update.

Changes should be made in the payload repository's `suite-source` branch and
then propagated through a new subtree split. Do not make independent commits
directly on `suite-payload`, because they will not be represented in the full
source branch.

The Hak5 fork keeps the same full-layout `suite-source` branch but generates a
separate branch for every deployable subtree. User category branches come from
`library/user/<category>`; the two system integrations come from
`library/alerts` and `library/recon`:

```text
suite-payload/evil-portal
suite-payload/exfiltration
suite-payload/games
suite-payload/general
suite-payload/interception
suite-payload/prank
suite-payload/reconnaissance
suite-payload/remote-access
suite-payload/virtual-pager
suite-payload/alerts
suite-payload/recon
```

This lets several submodules use the same HTTPS repository while each one
remains rooted at the correct deployment boundary. Changes and upstream merges
belong on the Hak5 fork's `suite-source`; payload branches are generated
artifacts and must not be edited directly.

## Updating the suite

Fetch the latest configured `suite-payload` branch for every submodule:

```sh
git submodule update --remote --checkout
git status --short
git submodule status
```

An update changes the suite's recorded gitlink only when a payload branch has
advanced. Review and validate those changes before recording them:

```sh
git diff --submodule=log
git add .gitmodules payloads
git commit -m "Update suite payloads"
```

For an ordinary pull that should retain the commits already recorded by the
suite, use:

```sh
git pull
git submodule sync --recursive
git submodule update --init --recursive
```

## Verification

Confirm the expected paths, URLs, branches, and pinned commits:

```sh
git status --short --branch
git submodule status
git config -f .gitmodules --get-regexp '^submodule\..*\.(path|url|branch)$'
```

A healthy checkout reports exactly fourteen initialized submodules with no `-`
or `+` prefix in `git submodule status`. The configured URLs should use HTTPS.
The original three branches should be `suite-payload`; Hak5 category branches
should be under `suite-payload/`.

Repository-side syntax and regression checks:

```sh
bash -n install.sh

bash -n payloads/user/capture/pineapol/payload.sh
payloads/user/capture/pineapol/tests/test_parsers.sh

find payloads/user/pager-apps/loki \
  -type f -name '*.sh' -exec sh -n {} +

bash -n \
  payloads/user/pager-apps/pagergotchi/payload.sh \
  payloads/user/pager-apps/pagergotchi/launch_loki.sh \
  payloads/user/pager-apps/pagergotchi/launch_pagergotchi.sh
sh -n payloads/user/pager-apps/pagergotchi/pagerctl.sh

find payloads/user/hak5-* payloads/alerts payloads/recon \
  -type f -name 'payload.sh' -exec bash -n {} +

find payloads/user/hak5-* payloads/alerts payloads/recon \
  -type f -name 'payload.sh' ! -perm -111 -print
```

The final command should print nothing.

## Third-party licensing

The repository-level GPL-3.0 license covers the suite's original coordination,
documentation, and integration work. It does not relicense code contained in
Git submodules. Each payload remains subject to the notices and terms supplied
by its source repository and contributors. The Hak5 category submodules retain
the upstream Hak5 repository's legal and attribution notices; review those
notices and each payload's documentation before use or redistribution.

## Troubleshooting

### Submodule directories are empty

The suite was cloned without its submodules. Run:

```sh
git submodule update --init --recursive
```

### A submodule has a `-` prefix

The submodule is not initialized. Run the initialization command above.

### A submodule has a `+` prefix

Its working tree is checked out at a commit different from the one recorded by
the suite. To return to the recorded version:

```sh
git submodule update --checkout
```

### A payload branch has advanced

The suite does not update automatically. Run:

```sh
git submodule update --remote --checkout
```

Review the gitlink change, perform the documented checks, and commit the new
pinned payload revision in this repository.

### HTTPS authentication fails

Public payload repositories normally clone without authentication. If a payload
repository becomes private, configure a GitHub credential helper or authenticate
with GitHub CLI before initializing the submodule.

### The installer cannot connect over SSH

Confirm that the Pager is booted, connected, and reachable at the selected
address, then test the same account directly:

```sh
ssh root@172.16.52.1
```

The installer respects normal OpenSSH host-key checking and authentication. Use
`--identity <key-file>` when the Pager requires a specific SSH key.

### Restore the previous payload-directory configuration

When `--replace-user-categories` is used, the installer prints the exact backup
path it created. Restore that file on the Pager and commit the UCI package:

```sh
cp /etc/config/payloads.suite-backup.<timestamp> /etc/config/payloads
uci commit payloads
```

Reboot if the Pager UI does not immediately reflect the restored categories.

## Credits

- **Suite maintenance and pinEAPol:** R4g3D
- **Loki and PagerGotchi:** brAinphreAk and their credited upstream projects
- **WiFi Pineapple Pager:** Hak5
- **hostapd-mana:** SensePost and the hostapd/wpa_supplicant contributors

See each payload's source repository and included notices for complete upstream
attribution.

## License

The suite's original documentation and repository configuration are licensed
under the [GNU General Public License v3.0](LICENSE) (`GPL-3.0-only`).

The payloads are independent Git submodules and retain their own copyright and
license terms:

- pinEAPol: GPL-3.0-only, with separately licensed bundled hostapd-mana material.
- Loki: MIT.
- PagerGotchi: GPL-3.0 and the applicable upstream Pwnagotchi terms.

This suite license does not replace or alter a submodule's license. Consult the
source repository and notices for each payload before redistribution or
modification.

## Legal notice

The suite may collect credentials, challenge-response material, wireless
handshakes, service information, vulnerability results, and files made
available through authorized credentials. Use it only within an explicitly
authorized assessment scope, minimize collection, secure retained evidence,
and follow all applicable laws and engagement rules.
