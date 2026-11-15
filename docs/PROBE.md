# JARVIS Probe: find out everything about the Mac mini

A small bootable USB image that **only reads**: it writes nothing to any disk of
the computer, installs nothing and sends nothing anywhere. It boots on UEFI or
legacy BIOS, collects what the computer reports about itself, and gives you the
report three ways so that it can be handed to a person (or to me) without typing.

## Get it
Run the **Probe image** workflow (it runs by itself when `probe/` changes) and
download the artifact `jarvis-probe-iso` from the run page (you must be signed in
to GitHub; kept 14 days). Check the SHA-256 against the `.sha256` file, then write
the ISO to a USB stick (Rufus in "DD Image" mode, or balenaEtcher).

## Use it
1. Plug in the stick, the Ethernet cable, a screen and a keyboard. Optional: a
   **second** USB stick formatted FAT32 and named `REPORT`.
2. Switch the Mac mini on holding the **Option (Alt) key**, choose the stick
   ("EFI Boot" is the UEFI entry). A menu appears and starts by itself after 5
   seconds. If the screen stays blank, restart and pick the second entry
   ("graphics drivers enabled").
3. After about a minute the screen shows a summary: machine, firmware, CPU and its
   instruction sets, memory, disks, network chips with their PCI ids, sound cards.
4. Get the full report in whichever way works:
   - **On the network:** open `http://<the address shown>:8080/report.txt` (or
     `http://jarvis-probe.local:8080/report.txt`) from another computer. It stays
     up for 20 minutes.
   - **USB stick:** a stick named `REPORT` is detected by itself and gets
     `jarvis-probe-<time>.txt` and a kernel log.
   - **On the machine:** Alt+F2 gives a shell; `less /run/probe/www/report.txt`.
5. Paste the report (or attach the file) into the chat.

## What is in the report
Machine and firmware identity (DMI), boot mode and UEFI word size (a Mac's EFI can
be 32 or 64 bit), boot entries, secure-boot state, CPU and instruction sets (SSSE3,
SSE4.1, SSE4.2, AVX, ...), memory modules, every PCI device with its
`vendor:device` id and the driver in use (the Wi-Fi chip shows up here), USB
devices, disks with SMART health and whether they are SSD or hard disk, partition
tables and file systems already on them, network interfaces with drivers and link
state, wireless and rfkill state, graphics and display (EDID) information, sound
cards and microphones, input devices, temperatures, and the kernel messages that
mention errors, firmware or network chips.

## Privacy
Serial numbers, UUIDs and the second half of every MAC address are replaced with
`<redacted>` / `xx` before the report leaves the machine. `jarvis-probe --full`
(from the Alt+F2 shell) keeps them, for your own use. The network page needs no
password and is limited to 20 minutes; do not leave the probe running on a network
you do not trust. There is no SSH and no other remote access.

## What is proven
CI boots the ISO with BIOS and with UEFI in QEMU (Core 2 class CPU), without any
key, with a `REPORT` stick attached; reads the report over HTTP; checks the
sections, the CPU readout, the PCI ids, the redaction, and that the stick got a
copy. It has not run on the real Mac mini.
