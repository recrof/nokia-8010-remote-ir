# Nokia Streaming Box 8010 remote: pairing notes and IR setup from a Mac

The Bluetooth remote that ships with the Nokia Streaming Box 8010 (models RC 212 / RC 222) has an IR blaster
for the TV's Power and Volume keys. Normally the box configures it. This repo documents how, and has a macOS
tool that does it without the box, so the remote can control a non-Nokia TV (tested with a Samsung).

Not affiliated with Nokia, StreamView or SEI Robotics. Use at your own risk. The remote's settings are
reversible (see below), but nothing here is guaranteed for other remotes or firmware versions.

## Findings

1. **The Mac can't pair with the remote, and that is expected.** The remote advertises as `NOKIA` (BLE HID,
   Realtek chip). It needs no encryption for any of its GATT services, so macOS never starts pairing. The remote
   drops the link about 10 seconds after connecting, which shows in System Settings as an endless spinner on Connect.
   The remote was never designed to be bonded by anything but an Android TV host.
2. **The IR setup is a separate feature, not pairing.** The box's firmware has a "Smart RCU" app
   (`com.standard.irtvcontrol`) that writes IR settings to the remote over a vendor GATT service. The 8010 is a
   rebrand of the SEI Robotics SEI804 reference platform, and the Homatics Box R 4K Plus firmware ships the same app.
3. **Unpaired writes work.** The remote accepts the IR setup writes without bonding, so a Mac can program it.
4. **Only some keys are IR-capable.** For a remote advertising as `NOKIA`, the app offers Power, Vol+, Vol- and Mute.
   Writing the Input slot (5) is accepted but no button on this remote uses it. The IR code stored in a slot is
   arbitrary, so you can store a different code than the key's name, e.g. Samsung Source on the Mute slot.

## Protocol (as used by the Smart RCU app)

Service `00000AA0-3C17-D293-8E48-14FE2E4DA212`. Characteristic `B002` is write + notify, `B001` is read.
All writes are write-with-response, in this order:

| Step | Bytes | Meaning |
|---|---|---|
| Select key | `10 <key>` | key: 1 Power, 2 Vol+, 3 Vol-, 5 Input, 6 OK, 17 Mute |
| Header | `01 08 <rnd> 00 26 00 <n lo> <n hi> <sum lo> <sum hi>` | `0x26` = 38 kHz carrier, `n` = number of timing values, `sum` = sum of values mod 65536 |
| Data | `02 <idx> <up to 18 bytes>` | timings in units of 10 µs as little-endian 16-bit, mark/space alternating, starting with a mark |
| End | `04 <rnd> 00` | `rnd` is the same byte as in the header |
| Set mode | `11 <key> <mode>` | mode: 1 Bluetooth key only, 2 IR only, 3 both |

The remote answers a mode change with a notification `13 <key> <mode>`. Writing `11 <key> 01` puts a key back to
its normal Bluetooth behavior.

Other opcodes seen in the app but not used here: `A0 <key>` (read key type), `C3 01/02` (long-press power).

## Other services on the remote (do not write blindly)

- `D0FF` and `6287` look like Realtek firmware-update (OTA/DFU) services. The tools never write to them.
- `AB5E0001-5A21-4F05-BC7D-AF01F617B664` is the Google Android TV voice-remote service.
- `D1FF` (`A001`, `A002`) is a command channel whose purpose I did not determine.

## Tools (macOS, Swift)

```sh
tools/build.sh
```

Your terminal app needs Bluetooth permission (System Settings, Privacy & Security, Bluetooth). Put the remote in
pairing mode first (hold Home + Back for 5 to 15 seconds), and keep it close.

- `tools/probe/probe`: connects to the remote, reads every readable value and subscribes to notifications.
  Reads only.
- `tools/irprog/irprog [ir|irble|ble] [keys...] [--dry-run]`: programs Samsung TV IR codes (Samsung32 at 38 kHz).
  Keys: `power`, `vol+`, `vol-`, `mute`, `input`, `muteassource` (Samsung Source code in the Mute slot).

```sh
tools/irprog/irprog ir power vol+ vol- mute     # Power and Volume control a Samsung TV over IR
tools/irprog/irprog ir muteassource             # Mute button now sends Samsung Source
tools/irprog/irprog ble mute                    # put Mute back to the normal Bluetooth key
tools/irprog/irprog --dry-run power             # print the packets without touching Bluetooth
```

To use another TV brand, change the code table at the top of `irprog.swift`.

## How the protocol was found

From a Homatics Box R 4K Plus firmware update (SEI804HM, Android 14). The package is a block-based OTA with EROFS
partitions. Unpack it with `brotli`, convert the `.new.dat` files to raw images with sdat2img, extract with
`fsck.erofs --extract` (from erofs-utils), find the Smart RCU APK in `system/app` and decompile it with jadx.
`sei_remote.conf` in `vendor/etc/config` lists the supported remote names, including `NOKIA`, `RC212` and `RC222`.
The firmware and decompiled code are not included here.

## Open questions

- Whether the settings survive removing the batteries. Not tested.
- Whether slots 5 and 6 are used on the RC 212 remote when it advertises as `RC212` rather than `NOKIA`.
- What `D1FF` does.
