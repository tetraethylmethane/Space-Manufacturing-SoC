#!/usr/bin/env bash
# Install FuseSoC/Edalize (lowRISC forks) and Python deps into the user site.
# No root needed. --break-system-packages is required on Ubuntu 24.04 without python3-venv;
# it only touches ~/.local, not system packages.
set -euo pipefail
cd "$(dirname "$0")/.."
pip3 install --user --break-system-packages -q -r python-requirements.txt
~/.local/bin/fusesoc --version
