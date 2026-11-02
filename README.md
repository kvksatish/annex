# Annex engine

🌐 **Want the app? Get Annex at [annex-mac.vercel.app](https://annex-mac.vercel.app/)**

This is the open-source engine behind Annex: it turns one Mac into a full-screen extended display for another, over a Thunderbolt/USB-C cable or Wi-Fi. No UI, no setup help. Just the connection. Run one command on each Mac.

**[⬇ Download the Annex app](https://github.com/kvksatish/annex/releases/latest/download/Annex.dmg)** (free) if you want the finished product: one-click pairing, automatic reconnect, live stats, drag-to-arrange, updates. The app is built on this engine; its interface is not open source.

## Try it

Two Macs with Apple silicon and macOS 14 or later, on the same network or joined by a cable.

```sh
./scripts/build.sh                 # → build/annex  (needs Xcode Command Line Tools)
```

On the Mac whose screen you want to borrow:

```sh
build/annex recv
```

On the Mac you work on (give your terminal Screen Recording permission first):

```sh
build/annex send 192.168.1.20      # the receiver's address; a cable link is usually 169.254.x.x
```

A new display appears, sized to the receiver's screen. Ctrl-C ends it. `annex recv` accepts any sender on your network, so only run it on networks you trust.

## How it works

```
sender                                                         receiver
virtual display → ScreenCaptureKit → H.264 (hardware) ──TCP──▶ hardware decode → full-screen window
                                         ▲                                 │
                                         └──── ping / pong (latency, liveness) ┘
```

- **Virtual display:** `CGVirtualDisplay` (private macOS API, also used by DeskPad and BetterDisplay), sized to the receiver's screen at 2× (HiDPI).
- **Capture:** ScreenCaptureKit, only when pixels change.
- **Encode and decode:** VideoToolbox H.264 with low-latency rate control; `AVSampleBufferDisplayLayer` shows each frame immediately. The receiver's window sits above the menu bar, so the notch strip is used too.
- **Link:** TCP with `TCP_NODELAY`. A ping every second measures latency and detects a dead link within a few seconds. Thunderbolt Bridge links are detected so a cable gets a higher bitrate.

The wire protocol is documented at the top of `src/engine/ANXCommon.h`.

```
src/engine/   ANXCommon (protocol, sockets), ANXSender (display + capture + encode), ANXReceiver (decode + window)
src/cli/      the annex command
```

## License

MIT. See [LICENSE](LICENSE). Bugs in the engine: open an issue.
