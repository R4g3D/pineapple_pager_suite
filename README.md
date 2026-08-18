# Pineapple Pager Suite

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform: WiFi Pineapple Pager](https://img.shields.io/badge/Platform-WiFi%20Pineapple%20Pager-2ea44f)](https://hak5.org/)
[![Payloads: 3](https://img.shields.io/badge/Payloads-3-orange)](#included-payloads)

A curated WiFi Pineapple Pager payload suite containing pinEAPol, Loki, and
PagerGotchi as independently maintained Git submodules.

> [!WARNING]
> These payloads are intended only for authorized security assessments and
> controlled research. Use them solely on networks, systems, accounts, and
> devices covered by explicit written authorization. Protect captured
> credentials, handshakes, logs, and other retained engagement evidence.

## What is the Pineapple Pager Suite?

The Pineapple Pager Suite provides three complementary Pager payloads in one
reproducible repository:

- **pinEAPol** performs controlled WPA-Enterprise EAP assessment and evidence
  capture with a verified hostapd-mana backend.
- **Loki** provides autonomous network discovery, service enumeration,
  credential testing, vulnerability scanning, and authorized data collection.
- **PagerGotchi** automates wireless discovery and WPA handshake/PMKID capture
  with interactive targeting, privacy, and display controls.

Each payload remains in its own source repository. This suite records a tested
payload commit at the required Pager path while `.gitmodules` identifies the
long-lived `suite-payload` branch used for explicit updates. A normal checkout
therefore remains reproducible instead of silently changing when a payload
branch advances.

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

The payload repositories contain their own detailed requirements, controls,
output locations, technical notes, and legal guidance. Read the relevant
payload documentation before an engagement.

## Requirements

- A Hak5 WiFi Pineapple Pager.
- Git with submodule support on the workstation used to clone the suite.
- SSH access to the Pager for manual deployment.
- Enough Pager storage for the complete suite, particularly Loki's bundled
  binaries, Python packages, web assets, and themes.
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
    └── pager-apps/
        ├── loki/           # Git submodule: suite-payload
        └── pagergotchi/    # Git submodule: suite-payload
```

The Loki and PagerGotchi payloads are installed together under **Pager Apps**.
Their launch scripts use those paths to hand control between the two apps.

## Branch model

Each payload repository has two suite branches:

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
git add \
  payloads/capture/pineapol \
  payloads/pager-apps/loki \
  payloads/pager-apps/pagergotchi
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

A healthy checkout reports exactly three initialized submodules with no `-` or
`+` prefix in `git submodule status`. The configured URLs should use HTTPS and
every configured branch should be `suite-payload`.

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
```

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
