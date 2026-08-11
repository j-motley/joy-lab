# Proxmark5 — Native Ubuntu / Linux Setup

Updated 2026-08-11 after hands-on setup on Ubuntu 26.04.

> ## ⚠️ Read this first — the important correction
>
> **The Proxmark5 is NOT a Proxmark3, and stock RfidResearchGroup/proxmark3 firmware will
> not run on it.** The genuine PM5 is a ground-up redesign built on an **Artery AT32F435**
> (288 MHz ARM Cortex-M4, 1 MB flash) paired with a **GOWIN FPGA**. The classic Proxmark3
> line — including the RDV4 — uses an **Atmel AT91SAM7** (ARM7TDMI) with a **Xilinx** FPGA.
> Those are different CPU families and different FPGAs; the stock firmware is binary-incompatible.
>
> The marketing phrase *"PM5 keeps Proxmark3 RDV4 firmware compatibility"* does **not** mean
> "flash stock RDV4 `master`." It refers to feature/workflow parity, not a flashable image.
>
> **Do not build and flash `RfidResearchGroup/proxmark3` onto a PM5.** Every attempt fails
> anyway (wrong size, `NACK` lock errors, "bootloader doesn't understand" warnings) — those
> failures are protective. Use the **PM5-specific client and firmware** from the vendor.

---

## How to confirm what you have

- **Main MCU marking `AT32F435...`** → genuine Proxmark5 (Artery Cortex-M4). The classic
  Proxmark3/RDV4 would read `AT91SAM7S256` or `AT91SAM7S512`.
- **Two USB-C ports** → PM5 (Port 1 = client/host, Port 2 = switchable host). RDV4 has one
  USB-C; a generic "Easy" clone has a single micro-USB.
- `lsusb` shows `9ac4:4b8f ... ProxMark-3 RFID Instrument` for all of them (shared USB ID),
  so that alone does **not** distinguish models.

## Getting the correct PM5 software

The PM5 ships with working factory firmware, so to start you mainly need the **matching PM5
client** — then connect and use it. Sources (reachable from a normal network; the notes
above were written where these domains were blocked):

- **Hacker Warehouse** product page / knowledgebase / support (if that's your reseller) —
  they ship the device and have the exact procedure.
- **proxmark.com/proxmark-news/proxmark5/** and **proxmark5.com** — official PM5 pages with
  firmware/client downloads and instructions.
- **github.com/RfidResearchGroup** — look for a PM5-specific repository or branch (the
  default `proxmark3` repo is the legacy AT91SAM7 codebase, not the PM5 one).

When switching or updating firmware on the PM5, follow the vendor's PM5 procedure — not the
Proxmark3 `pm3-flash-all` flow in the old notes.

---

## Host prep that IS valid on Linux (firmware-independent)

These steps apply regardless of which client you end up running:

```bash
# 1. Serial + permissions
sudo usermod -aG dialout "$USER"      # then log out / back in
groups | grep -o dialout              # verify

# 2. ModemManager grabs /dev/ttyACM* and interferes — stop (or mask) it
sudo systemctl stop ModemManager
# sudo systemctl disable ModemManager # optional, for a dedicated pentest laptop

# 3. Confirm the device enumerates (plug into the Port 1 / client USB-C)
ls -l /dev/ttyACM*                    # expect /dev/ttyACM0
```

`run setup.sh` in this folder to do the host prep (deps + dialout + ModemManager) only. It
intentionally does **not** clone/build/flash any firmware, because the correct PM5 image
comes from the vendor.

## Safety notes

- Only read/write tags and cards you own or are authorized to test.
- Never interrupt any bootloader/bootrom write. A failed bootrom write can require hardware
  recovery (JTAG/SWD).
- If in doubt about a firmware image's target hardware, **don't flash it** — confirm the
  chip/FPGA first.

## What went wrong the first time (so nobody repeats it)

The original notes assumed PM5 = RDV4-compatible and built `PLATFORM=PM3RDV4`, then
`PM3GENERIC` with `PLATFORM_SIZE=256`. Symptoms, in order: firmware "too big for your
platform," `NACK (expected ACK)` lock errors, "bootloader does not understand CMD_BL_VERSION".
Root cause: the images were for AT91SAM7 + Xilinx and the board is AT32F435 + GOWIN. The
chip marking is what finally settled it.

## Sources

- https://proxmark.com/proxmark-news/proxmark5/  (PM5: AT32F435 + GOWIN FPGA)
- https://proxmark5.com/
- https://github.com/RfidResearchGroup/proxmark3  (legacy AT91SAM7 firmware — NOT for PM5)
- Artery AT32F435 datasheet — Cortex-M4, up to 288 MHz, up to ~1 MB flash
