# Pineapple Pager Suite

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform: WiFi Pineapple Pager](https://img.shields.io/badge/Platform-WiFi%20Pineapple%20Pager-2ea44f)](https://hak5.org/)
[![Payloads: 167](https://img.shields.io/badge/Payloads-167-orange)](#included-payloads)

A reproducible WiFi Pineapple Pager payload suite containing pinEAPol, Loki,
PagerGotchi, and 164 user payloads from the Hak5 community library. Payloads
are pinned as independently maintained Git submodules at Pager-native paths.

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

The suite records an explicit payload commit at every required Pager path while
`.gitmodules` identifies the long-lived payload branch used for deliberate
updates. A normal checkout therefore remains reproducible instead of silently
changing when a branch advances. The three original payloads use one submodule
each; the Hak5 fork uses one submodule per category so the Pager receives the
supported `category/payload/payload.sh` layout without another nesting level.

## Documentation map

- [Review the included payloads](#included-payloads)
- [Clone the complete suite](#installation)
- [Deploy it to a Pager](#deploy-to-the-pager)
- [Understand the repository layout](#repository-layout)
- [Update payload branches safely](#updating-the-suite)
- [Verify a checkout](#verification)
- [Resolve common problems](#troubleshooting)

## Included payloads

| Payload | Suite path | Purpose | Source |
|---|---|---|---|
| **pinEAPol** | `payloads/capture/pineapol` | Authorized WPA-Enterprise EAP assessment and evidence capture | [R4g3D/pineapple_pager_pineapol](https://github.com/R4g3D/pineapple_pager_pineapol) |
| **Loki** | `payloads/pager-apps/loki` | Autonomous LAN reconnaissance, service testing, and Pager-native reporting | [R4g3D/pineapple_pager_loki](https://github.com/R4g3D/pineapple_pager_loki) |
| **PagerGotchi** | `payloads/pager-apps/pagergotchi` | Wireless discovery and WPA handshake/PMKID capture companion | [R4g3D/pineapple_pager_pagergotchi](https://github.com/R4g3D/pineapple_pager_pagergotchi) |
| **Hak5 Evil Portal** (10) | `payloads/hak5-evil-portal` | Evil Portal installation, configuration, and control | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Exfiltration** (6) | `payloads/hak5-exfiltration` | Authorized data transfer and capture workflows | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Games** (11) | `payloads/hak5-games` | Games and interactive demonstrations | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 General** (81) | `payloads/hak5-general` | Pager utilities, configuration, diagnostics, and management | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Interception** (5) | `payloads/hak5-interception` | Authorized portal and traffic-interception workflows | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Prank** (4) | `payloads/hak5-prank` | Non-destructive demonstration payloads | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Reconnaissance** (32) | `payloads/hak5-reconnaissance` | Wireless, network, Bluetooth, and OSINT reconnaissance | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Remote Access** (13) | `payloads/hak5-remote-access` | Authorized remote connectivity and administration | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |
| **Hak5 Virtual Pager** (2) | `payloads/hak5-virtual-pager` | Virtual Pager display customization | [R4g3D/pineapple_pager_hak5](https://github.com/R4g3D/pineapple_pager_hak5) |

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

The suite layout maps directly beneath `/root/payloads/user/` on the Pager. To
avoid copying local Git metadata, create a deployment archive from the contents
of `payloads/`:

```sh
tar --exclude='.git' \
  -czf pineapple-pager-suite.tar.gz \
  -C payloads .

scp pineapple-pager-suite.tar.gz root@<pager-ip>:/tmp/
ssh root@<pager-ip> \
  'mkdir -p /root/payloads/user && \
   tar -xzf /tmp/pineapple-pager-suite.tar.gz -C /root/payloads/user && \
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
```

The archive is ignored by this repository and can be removed locally after
deployment.

## Repository layout

```text
pineapple_pager_suite/
├── .gitmodules
├── .gitignore
├── LICENSE
├── README.md
└── payloads/
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
separate branch for each selected `library/user/<category>` subtree:

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
```

This lets several category submodules use the same HTTPS repository while each
one remains rooted directly at its payload directories. Changes and upstream
merges belong on the Hak5 fork's `suite-source`; category branches are generated
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

A healthy checkout reports exactly twelve initialized submodules with no `-`
or `+` prefix in `git submodule status`. The configured URLs should use HTTPS.
The original three branches should be `suite-payload`; Hak5 category branches
should be under `suite-payload/`.

Repository-side syntax and regression checks:

```sh
bash -n payloads/capture/pineapol/payload.sh
payloads/capture/pineapol/tests/test_parsers.sh

find payloads/pager-apps/loki \
  -type f -name '*.sh' -exec sh -n {} +

bash -n \
  payloads/pager-apps/pagergotchi/payload.sh \
  payloads/pager-apps/pagergotchi/launch_loki.sh \
  payloads/pager-apps/pagergotchi/launch_pagergotchi.sh
sh -n payloads/pager-apps/pagergotchi/pagerctl.sh

find payloads/hak5-* \
  -type f -name 'payload.sh' -exec bash -n {} +

find payloads/hak5-* \
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
