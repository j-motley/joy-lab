#!/usr/bin/env bash
#
# Proxmark5 native-Ubuntu HOST PREP helper.
#
# IMPORTANT: This does NOT clone, build, or flash any firmware.
# The Proxmark5 is an Artery AT32F435 (Cortex-M4) + GOWIN FPGA board. The stock
# RfidResearchGroup/proxmark3 firmware is built for the legacy Atmel AT91SAM7 + Xilinx
# architecture and will NOT run on a PM5 — do not flash it. Get the PM5-specific client
# and firmware from the vendor (see README.md).
#
# This script only prepares the Linux host: serial permissions + ModemManager. Those steps
# are firmware-independent and safe.

set -euo pipefail

info() { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
  warn "Run this as your normal user, not root (it uses sudo where needed)."
  exit 1
fi

# --- Build/runtime dependencies for a PM5 client ---------------------------------------
# (Harmless to install even before you have the vendor client; these are the usual
# Proxmark client deps on Debian/Ubuntu.)
info "Installing common client dependencies..."
sudo apt update || warn "apt update failed (lock held by another process?) — continuing"
sudo apt install --no-install-recommends -y \
  git ca-certificates build-essential pkg-config libreadline-dev \
  qt6-base-dev libbz2-dev liblz4-dev zlib1g-dev libbluetooth-dev \
  libpython3-dev libssl-dev libgd-dev

# --- Serial permissions ----------------------------------------------------------------
if ! id -nG "$USER" | grep -qw dialout; then
  info "Adding $USER to the dialout group..."
  sudo usermod -aG dialout "$USER"
  warn "Log out and back in for the dialout group change to take effect."
else
  info "Already in the dialout group."
fi

# --- ModemManager (grabs /dev/ttyACM* and interferes) ----------------------------------
if systemctl is-active --quiet ModemManager 2>/dev/null; then
  info "Stopping ModemManager (it grabs the serial port)..."
  sudo systemctl stop ModemManager
  warn "To stop it permanently: sudo systemctl disable ModemManager"
else
  info "ModemManager is not active."
fi

cat <<'EOF'

Host prep complete.

Next steps (NOT handled by this script — see README.md):
  1. Get the Proxmark5-specific client + firmware from the vendor
     (proxmark.com/proxmark-news/proxmark5, proxmark5.com, your reseller,
      or a PM5 repo/branch under github.com/RfidResearchGroup).
  2. Plug the PM5 into its Port 1 (client) USB-C; confirm: ls -l /dev/ttyACM*
  3. Run the PM5 client and verify with `hw version`.

Do NOT build/flash RfidResearchGroup/proxmark3 stock firmware onto a PM5.
EOF
