#!/usr/bin/env bash
#
# Proxmark5 native-Ubuntu setup helper.
# Idempotent: installs deps, clones/updates the Iceman firmware, sets PLATFORM=PM3RDV4,
# builds, installs udev rules, and adds you to the dialout group.
#
# It deliberately STOPS before flashing. Flashing is the one irreversible step and must be
# run by hand once the board is connected — see the end of this script for the command.
#
# Verified against RfidResearchGroup/proxmark3 master on 2026-08-11.

set -euo pipefail

REPO_URL="https://github.com/RfidResearchGroup/proxmark3.git"
SRC_DIR="${PM3_SRC_DIR:-$HOME/proxmark3}"
PLATFORM="PM3RDV4"   # No PM5 target exists; PM5 is RDV4-firmware compatible.

info()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
  warn "Run this as your normal user, not root (it uses sudo where needed)."
  exit 1
fi

# --- 1. Dependencies -------------------------------------------------------------------
info "Installing build dependencies..."
sudo apt update
DEPS=(
  git ca-certificates build-essential pkg-config libreadline-dev
  gcc-arm-none-eabi libnewlib-dev qt6-base-dev libbz2-dev liblz4-dev
  zlib1g-dev libbluetooth-dev libpython3-dev libssl-dev libgd-dev
)
if ! sudo apt install --no-install-recommends -y "${DEPS[@]}"; then
  warn "apt failed. On newer distros gcc-arm-none-eabi and libnewlib-dev can conflict."
  warn "Retrying with picolibc-arm-none-eabi in place of libnewlib-dev..."
  DEPS=( "${DEPS[@]/libnewlib-dev/picolibc-arm-none-eabi}" )
  sudo apt install --no-install-recommends -y "${DEPS[@]}"
fi

# --- 2. Clone / update -----------------------------------------------------------------
if [[ -d "$SRC_DIR/.git" ]]; then
  info "Updating existing checkout at $SRC_DIR ..."
  git -C "$SRC_DIR" pull --ff-only
else
  info "Cloning firmware into $SRC_DIR ..."
  git clone "$REPO_URL" "$SRC_DIR"
fi
cd "$SRC_DIR"

# --- 3. Platform selection -------------------------------------------------------------
info "Setting PLATFORM=$PLATFORM in Makefile.platform ..."
if [[ ! -f Makefile.platform ]]; then
  cp Makefile.platform.sample Makefile.platform
fi
# Replace any existing uncommented PLATFORM= line, else append one.
if grep -qE '^\s*PLATFORM\s*=' Makefile.platform; then
  sed -i -E "s|^\s*PLATFORM\s*=.*|PLATFORM=$PLATFORM|" Makefile.platform
else
  printf 'PLATFORM=%s\n' "$PLATFORM" >> Makefile.platform
fi
grep -E '^PLATFORM=' Makefile.platform

# --- 4. Build --------------------------------------------------------------------------
info "Building (make clean && make)..."
make clean
make -j"$(nproc)"

# --- 5. Install + permissions ----------------------------------------------------------
info "Installing (udev rules + client on PATH)..."
sudo make install
if ! id -nG "$USER" | grep -qw dialout; then
  info "Adding $USER to the dialout group..."
  sudo usermod -aG dialout "$USER"
  warn "Log out and back in for the dialout group change to take effect."
fi

# ModemManager can grab /dev/ttyACM0 during flashing.
if systemctl is-active --quiet ModemManager 2>/dev/null; then
  warn "ModemManager is active and may grab the serial port."
  warn "If the client can't connect, run: sudo systemctl stop ModemManager"
fi

cat <<EOF

\033[1;32mBuild + install complete.\033[0m

Next steps (run by hand, with the Proxmark5 plugged in):

  cd "$SRC_DIR"
  ./pm3-flash-all          # flash bootloader + fullimage (irreversible; only with the board connected)
  ./pm3                    # launch the client

Inside the client, verify before touching any cards:

  hw status
  hw version               # <-- capture this output

EOF
