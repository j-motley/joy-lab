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

## The correct PM5 procedure (community-proven, Aug 2026)

The PM5 firmware/client lives on a **dedicated branch**, not stock RRG master. The PM5 doc
states it plainly: *"Only the client and firmware of this PR can support PM5. Please do not
use the client and firmware from the master branch to flash PM5."*

**Source:** `github.com/xianglin1998/proxmark3`, the **`proxmark5` branch**.

> **⚠️ Remove the WiFi/Bluetooth/battery add-on (BWM) before flashing.** The PM5↔BWM
> communication driver is still on the TODO list; the add-on causes flashing/UART issues.
> Flash the bare board.

```bash
git clone https://github.com/xianglin1998/proxmark3.git
cd proxmark3
git checkout proxmark5
cp Makefile.platform.sample Makefile.platform
echo 'PLATFORM=PM5' > Makefile.platform      # PM5 target, not PM3RDV4
make clean && make -j"$(nproc)"              # builds firmware + client
```
If the `armsrc` (firmware) build errors, the PM5 doc notes armsrc may require **cmake**
while the client builds via make; the make path worked for the community as of 2026-08-11,
so try it first.

**Enter FLASH MODE:**
1. Unplug. Press and hold the button.
2. Plug into the USB-C port **next to the button / ABCD LEDs** (the client port — NOT the
   CEP / F0 expansion port).
3. Keep holding ~3 s until **LED_B and LED_D** light up together, then release.

**Flash both stages (bootrom alone is not enough):**
```bash
./pm3-flash-all          # bootrom + fullimage
./pm3
```
Inside the client:
```
hw version               # client<->firmware now match; shows AT32F435 + GOWIN
hw tune                  # antenna health (LF 125 kHz + HF 13.56 MHz voltages)
lf search                # 125 kHz tag on the antenna
hf search                # 13.56 MHz card on the antenna
```

- `Permitted flash range: 0x08000000-0x08100000` is **informational, not an error** — it's
  the Cortex-M flash base (0x08000000) spanning 1 MB, matching the AT32F435RG.
- **Recovery:** if a bootrom flash fails, hold the button **6-8 s** to enter **ISP mode**
  (the un-brick path).
- **WiFi/BT will not work yet** — that integration is unfinished. LF/HF are faster than the
  PM3 (GOWIN FPGA has built-in flash, so no runtime FPGA load).

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

- https://github.com/xianglin1998/proxmark3/tree/proxmark5  (PM5 firmware/client branch)
- https://github.com/xianglin1998/proxmark3/blob/proxmark5/doc/md/Development/Proxmark5.md  (PM5 dev/flash doc)
- https://proxmark.com/proxmark-news/proxmark5/  (PM5: AT32F435 + GOWIN FPGA)
- https://github.com/RfidResearchGroup/proxmark3  (legacy AT91SAM7 firmware — NOT for PM5)
- Artery AT32F435 datasheet — Cortex-M4, up to 288 MHz, 1 MB flash (RG), flash base 0x08000000
