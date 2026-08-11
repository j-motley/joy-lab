# Proxmark5 — Native Ubuntu / Linux Setup

Corrected continuation of setup notes originally drafted in a Windows Claude Code session
(2026-08-10) and verified against the official RfidResearchGroup/proxmark3 repo on 2026-08-11.

**Hardware:** Proxmark5 (RFID Research Group / Iceman, announced 2026-05-12). It keeps
Proxmark3 RDV4 firmware compatibility and adds extended-range / UHF-ready hardware.
**Platform decision:** native / dual-boot Linux (not WSL) — USB is plug-and-play at
`/dev/ttyACM0`.

> **Heads-up on availability:** general hardware availability was announced as late 2026 /
> early 2027. If you have an early-bird or dev unit, its firmware may be ahead of the public
> `master` branch — always trust `hw version` output over any written doc.

Goals, in order: LF (125 kHz) → HF/NFC (13.56 MHz) → UHF → Flipper Zero pairing.

---

## 1. Dependencies (Debian / Ubuntu)

```bash
sudo apt update
sudo apt install --no-install-recommends \
  git ca-certificates build-essential pkg-config libreadline-dev \
  gcc-arm-none-eabi libnewlib-dev qt6-base-dev libbz2-dev liblz4-dev \
  zlib1g-dev libbluetooth-dev libpython3-dev libssl-dev libgd-dev
```

Notes:
- `libnewlib-dev` is correct (this is the documented package — do **not** substitute
  `libnewlib-arm-none-eabi`).
- On very recent distros, `gcc-arm-none-eabi` and `libnewlib-dev` can conflict. If apt
  refuses the install, replace `libnewlib-dev` with `picolibc-arm-none-eabi`.
- Qt (`qt6-base-dev`) is only needed for the optional GUI plot window; `qtbase5-dev` (Qt5)
  also works if that is what your release ships.

## 2. Clone + pick platform

```bash
git clone https://github.com/RfidResearchGroup/proxmark3.git
cd proxmark3
cp Makefile.platform.sample Makefile.platform
```

Edit `Makefile.platform` and set:

```
PLATFORM=PM3RDV4
```

**There is no `PM5` platform target** — the only valid options are `PM3RDV4`, `PM3GENERIC`,
`PM3ICOPYX`, and `PM3ULTIMATE`. Because the Proxmark5 is RDV4-firmware compatible, `PM3RDV4`
is the correct choice. Confirm after flashing with `hw version`.

## 3. Build

```bash
make clean && make -j"$(nproc)"
```

## 4. Permissions

```bash
sudo make install            # installs udev rules and puts pm3 tools on PATH
sudo usermod -aG dialout "$USER"
```

Then **log out and back in** for the group change to take effect.

Gotcha: ModemManager may grab the serial port. If the client can't connect:

```bash
sudo systemctl stop ModemManager      # or: sudo systemctl mask ModemManager
```

## 5. Connect, flash, verify

```bash
# from the proxmark3 build directory; device enumerates as /dev/ttyACM0
./pm3-flash-all              # flash bootloader + fullimage
./pm3                        # auto-detects /dev/ttyACM0
```

Inside the client:

```
hw status
hw version
```

**Capture the `hw version` output** — it confirms the firmware matches the client and shows
the platform, before touching any cards.

## 6. First real tests (once verified)

- **LF:** place a known 125 kHz tag on the antenna, run `lf search`
- **HF/NFC:** `hf search`, then MIFARE via `hf mf ...`
- **UHF:** newer capability, thinner docs — tackle after LF/HF work
- **Flipper pairing:** newest feature, least documented — do this last as its own step

## Notes / reminders

- Only read/write tags and cards you own or are explicitly authorized to test.
- To resume with the assistant later: paste this file plus your `hw version` output into a
  fresh session to get back up to speed.

## Sources

- https://proxmark.com/proxmark-news/proxmark5/
- https://github.com/RfidResearchGroup/proxmark3
- https://github.com/RfidResearchGroup/proxmark3/blob/master/doc/md/Installation_Instructions/Linux-Installation-Instructions.md
