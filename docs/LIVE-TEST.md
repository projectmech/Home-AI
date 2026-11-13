# Trying the JARVIS OS live image on the Mac mini

**What this is:** an image that runs from a USB stick. It does not install anything and does not touch the Mac mini's internal disk. Unplug the stick and reboot, and the Mac mini is exactly as it was.

**What it is for:** finding out, on the real machine, whether it boots, whether the network comes up, and whether you can reach the JARVIS dashboard from another computer. It is a test image, not the finished operating system: there is no installer, no disk encryption, no login on the machine itself, and nothing you set up survives power-off.

**What has been tested:** in CI, in virtual machines only, as a Core 2-class CPU, with both BIOS and EFI boot. **Nobody has booted it on a Macmini4,1.** Everything below about the real machine is expectation, not fact.

## What you need
- A USB stick of at least 2 GB. **It will be erased.** Use one with nothing on it you want.
- The ISO: open the newest successful run of the **OS image** workflow in the repository's Actions tab and download the artifact `jarvis-os-live-iso` (about 330 MB zipped; you need to be signed in to GitHub). Unzip it to get `jarvis-os-amd64.iso`.
- The Mac mini connected to your router **with an Ethernet cable** (there is no Wi-Fi support in this image), plus a monitor and a keyboard.
- Another computer or phone on the same network, with a browser.

## Put the image on the stick (Windows)
1. Download Rufus (rufus.ie) or balenaEtcher.
2. Rufus: choose the stick and the ISO. When it asks, choose **"Write in DD Image mode"** (not ISO mode). Etcher: select the ISO and the stick and click Flash.
3. Wait for it to finish. Windows may say the stick needs formatting: do not format it.

## Boot the Mac mini from it
1. Shut the Mac mini down. Plug in the stick and the Ethernet cable.
2. Hold the **Option (Alt)** key and press the power button. Keep holding until a list of startup disks appears.
3. Pick the stick. You may see two entries for it: one labelled **EFI Boot** and one labelled **Windows**. Try **EFI Boot** first. If it does not start, restart and try the other one (that is the BIOS-style boot).
4. The image starts by itself after about 5 seconds at its menu. After about a minute the screen shows a box like this:

```
 JARVIS OS - live test image. Nothing is installed on this computer's disk.
 Dashboard:   https://192.168.1.50:8443
 Setup token: <64 characters>
 Network:     eth0  driver=forcedeth  state=up  cable connected
 Hardware:    Ethernet controller [0200]: ... [10de:xxxx]
 Hardware:    Network controller [0280]: ... [14e4:xxxx]   (the Wi-Fi chip)
 Certificate SHA-256: AA:BB:...
```

## Use the dashboard
1. On your other computer open the **Dashboard** address from the screen.
2. The browser warns about the certificate. Open the certificate details and compare its **SHA-256 fingerprint** with the one on the Mac mini's screen. If they match, continue.
3. Enter the **setup token**, create the administrator, and go through the wizard. Afterwards sign in with the account you made.
4. Try the Home page (simulated devices) and the Server page (the Mac mini's real CPU, memory and disk).

The token works for 60 minutes. For a new one, restart the Mac mini. `https://jarvis.local:8443` may also work if your computer supports `.local` names; the IP address always works.

## If it does not work
Please tell me exactly what you saw. The most useful details:
- Did the stick appear in the Option-key list? Under which name?
- Did you get past the boot menu? What does the screen show (black, error text, the box above)?
- If the box shows no address: is the Ethernet cable plugged in and lit? The Network line says whether the system sees a cable and which driver it uses.
- Please send the Hardware lines (a photo of the screen is fine). They name the exact wired and Wi-Fi chips, which decides whether Wi-Fi can be added.
- What does the Server page say about CPU model, memory and drive type? (That is real information about your machine.)

Known limits: wired network only; no sound, Wi-Fi or Bluetooth; no remote login of any kind (no SSH, no accounts, no sudo); the console has no login; the screen uses a plain text mode (the image starts with `nomodeset` to avoid graphics-driver problems on the 2010 NVIDIA chip).
