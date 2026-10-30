# Annex — User Manual

Annex turns your other Mac into a second display. It fills the whole screen, including the strip beside the notch: no black bars, no setup wizard, no account.

## What you need

- Two Macs on **macOS 14 Sonoma or newer** with Apple silicon (M1 or later).
- One of:
  - **A Thunderbolt or USB4 cable** between the two Macs (sharpest picture, lowest lag), or
  - **the same Wi-Fi network** for both Macs.

> Most USB-C cables that came with a charger are charge-only and won't work. Use a Thunderbolt/USB4 cable or a USB-C *data* cable.

## Set up (once, about a minute)

| # | Where | What you do |
|---|-------|-------------|
| 1 | Both Macs | Download Annex and drag it into **Applications**. |
| 2 | Both Macs | Open Annex. If macOS asks to *find devices on your local network*, click **Allow**. |
| 3 | The Mac you work on | Your other Mac appears under **Your other Macs**. Click **Use as Display**. |
| 4 | The other Mac | Click **Allow** when it asks whether your Mac may use this screen. |
| 5 | The Mac you work on, first time only | macOS asks for **Screen Recording**. Click **Open Settings**, turn on **Annex**, then click **Relaunch Annex**. |

That's it. The other Mac's screen now shows your extended desktop. Drag windows onto it like any monitor.

**From then on it's automatic.** Open both Macs and they reconnect by themselves. Turn on **Open Annex at login** on both and you never have to think about it again.

## Everyday use

- **Stop:** click **Stop** in Annex, or use the Annex icon in the menu bar.
- **Get the other Mac's screen back:** press **Esc** on it. Annex steps aside for 30 seconds so you can use that Mac.
- **Cable or Wi-Fi:** Annex picks the cable automatically when one is plugged in, and switches to it mid-session if you plug it in later. The green **Cable** or blue **Wi-Fi** badge shows which one it's using.
- **Unplug or walk away:** the extra display disappears and your windows move back. When the other Mac comes back, Annex reconnects.

## Battery and the cable

A cable between two MacBooks carries **power** as well as the picture. If neither Mac is on a charger, one Mac quietly charges the other and its own battery drains.

- **Simplest fix:** plug a charger into **either** Mac. Then both stay powered.
- **On battery for a while?** Annex shows an orange warning. Click **Use Wi-Fi Instead**, then unplug the cable. The picture keeps going over Wi-Fi and the charging stops.

macOS decides which Mac charges which; no app can switch that off.

## Settings

| Setting | What it does |
|---------|--------------|
| **Size** | *Default* matches the other Mac's own screen. *Larger Text* makes everything bigger; *More Space* fits more. |
| **Position** | Whether the display sits to the left or right of this Mac, so your mouse crosses over on the correct side. |
| **Connection** | *Automatic* uses the cable when plugged in, Wi-Fi otherwise. *Wi-Fi only* never uses the cable for video. |
| **Let my other Macs use this screen** | Turn off to stop this Mac from being used as a display. |
| **Reconnect automatically** | Reconnects to the last Mac you used whenever it's nearby. |
| **Open Annex at login** | Starts Annex quietly in the menu bar when you log in. |

## The Live panel

While extending, Annex shows:

- **Smoothness (fps):** frames per second. Annex only sends a frame when something changes, so a still screen shows a low number. That's normal.
- **Speed (Mbps):** how much data is flowing, with a 60-second graph.
- **Latency (ms):** round-trip time between the Macs. Cable is usually under 2 ms.
- **Connection:** Cable or Wi-Fi.

## Something wrong?

Open **Activity** at the bottom of the Annex window. Problems are shown in red.

| You see | Try this |
|---------|----------|
| *Looking for your other Mac…* forever | Make sure Annex is open on both Macs and both allowed **Local Network** access (System Settings → Privacy & Security → Local Network). Check that both are on the same Wi-Fi, or that the cable is a data cable. |
| *Screen Recording permission is off* | System Settings → Privacy & Security → Screen & System Audio Recording → turn on **Annex** → relaunch Annex. |
| *The other Mac isn't accepting right now* | On the other Mac, turn on **Let my other Macs use this screen**, or wait 30 s if someone pressed Esc. |
| It says *Wi-Fi* although a cable is plugged in | Open System Settings → Network on both Macs and check that **Thunderbolt Bridge** is connected. |
| *“Annex” can't be opened* when first opening it | Until Annex is notarized: open System Settings → Privacy & Security and click **Open Anyway**. |

Still stuck? Click **Report a Problem…** in the Activity section. It opens a GitHub issue that already includes your macOS version and the recent log. Add a sentence about what happened and submit. You can see and edit everything before it's sent.

The full log lives at `~/Library/Logs/Annex/annex.log`.

## Privacy

Annex talks only to your other Mac, directly over your cable or local network. No accounts, no cloud, no analytics. The *Set up in N s · N clicks* note at the bottom of the window is measured and stored only on your Mac.
