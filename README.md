# Turn off "Thru" on a Blue Yeti automatically

macOS forgets the **Thru** setting on a Blue Yeti microphone. Thru routes the
microphone input straight back to its own headphone output, so you hear
yourself. If you do not want that, you turn it off in Audio MIDI Setup, and
macOS turns it back on at the next restart.

This is not a bug in your settings. The Thru state lives on the CoreAudio
device object rather than in a preference file. macOS rebuilds that object
from the driver default every time the device appears, which means every
restart and every time you unplug the microphone.

Nothing you click in Audio MIDI Setup can survive that, because there is no
file to save it in. The fix is a small program that turns Thru off, plus a
launch agent that runs the program at the right moments.

## What you get

- A command, `yeti-thru`, that turns Thru off on demand.
- A launch agent that runs it at login, and again whenever you plug the
  microphone in.

## Before you start

You need three things.

- **A Mac with a Blue Yeti.** Other Blue and Logitech microphones work too,
  but you must look up your own device IDs. Step 4 explains how.
- **The Command Line Tools.** These supply the Swift compiler. You do not
  need full Xcode. Check with `swiftc --version`. If that fails, run
  `xcode-select --install` and accept the prompt.
- **About ten minutes**, including one restart to confirm the result.

Tested on macOS 26. The CoreAudio and launchd interfaces used here are long
established, so earlier versions should also work.

## Step 1: Get the files

```sh
git clone https://github.com/mapitman/yeti-thru.git
cd yeti-thru
```

Keep the clone. You need the source again if you ever rebuild the program.

## Step 2: Compile the program

```sh
mkdir -p ~/.local/bin
swiftc -O -o ~/.local/bin/yeti-thru yeti-thru.swift
```

This prints nothing when it succeeds.

## Step 3: Test the program

Open **Audio MIDI Setup** from Applications › Utilities. Select your Yeti
input device in the left list. It is the entry that reads `2 ins / 0 outs`.
Confirm that **Thru** is switched on, so the test proves something.

Then run:

```sh
~/.local/bin/yeti-thru
```

You should see a line like this, and Thru should now be off:

```
Thru disabled: Yeti Stereo Microphone [id 150]
```

The device ID varies between machines and between restarts. That does not
matter. The program finds the microphone by name each time it runs, then
picks the entry that has input channels.

If you instead see `No input device found`, your microphone reports a
different name. Open `yeti-thru.swift`, change the `targetName` line to match
the name shown in Audio MIDI Setup, and compile again.

## Step 4: Find your device IDs

The launch agent needs the USB vendor and product IDs of your microphone, so
that macOS knows which device should trigger it.

```sh
ioreg -r -c IOUSBHostDevice -n "Blue Microphones" -l | grep -E '"(idVendor|idProduct)"'
```

On a Blue Yeti this reports vendor `1133` and product `2743`, which are the
values already in the plist. If you get those two numbers, change nothing and
go to step 5.

If the command prints nothing, your microphone uses a different USB name. List
every USB device and find yours:

```sh
ioreg -r -c IOUSBHostDevice -l | grep -E '"(USB Product Name|idVendor|idProduct)"'
```

Find your microphone in that output, note the `idVendor` and `idProduct`
values printed with it, then edit those two numbers in
`dist/local.yeti-thru.plist`. Use the decimal values exactly as `ioreg`
prints them, because the plist expects decimal rather than hexadecimal.

Note that `system_profiler SPUSBDataType` shows the same information in a
friendlier layout, but it returns nothing in some environments. Use `ioreg`
when that happens.

## Step 5: Install the launch agent

```sh
cp dist/local.yeti-thru.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/local.yeti-thru.plist
```

Confirm that macOS registered it:

```sh
launchctl list | grep yeti
```

You should see `local.yeti-thru`. The middle column is the exit status, and
`0` means the last run succeeded. A dash in the first column is correct,
because the job finishes rather than staying resident.

If you are replacing an earlier version of this file, unload it first.
Otherwise macOS keeps using the old definition:

```sh
launchctl unload ~/Library/LaunchAgents/local.yeti-thru.plist
```

## Step 6: Confirm it works

Two things happen automatically, so test them separately.

**Unplugging.** Turn Thru on in Audio MIDI Setup. Unplug the microphone, plug
it back in, then wait about ten seconds. Thru should switch itself off.

**Restarting.** Turn Thru on again, then restart the Mac. Thru should be off
when you log back in.

The delay on the second test is deliberate. The USB device appears before
CoreAudio finishes registering it, so the agent retries for up to ten seconds
rather than giving up on the first attempt.

## If it does not work

Run the program by hand first:

```sh
~/.local/bin/yeti-thru
```

If that reports `Thru disabled`, the program is fine and the problem is in the
launch agent. If it reports anything else, go back to step 3.

To make the agent run immediately, without unplugging anything:

```sh
launchctl kickstart -k gui/$(id -u)/local.yeti-thru
tail -5 ~/Library/Logs/yeti-thru.log
```

For a wider view, read the system log:

```sh
log show --predicate 'eventMessage CONTAINS "yeti-thru"' --last 10m
```

If login works but unplugging does not, your device IDs are probably wrong.
Repeat step 4 with the microphone connected.

## How to remove it

```sh
launchctl unload ~/Library/LaunchAgents/local.yeti-thru.plist
rm ~/Library/LaunchAgents/local.yeti-thru.plist
rm ~/.local/bin/yeti-thru
```

Removing these files changes nothing else. The next restart brings Thru back,
as it did before.

## How it works

The program asks CoreAudio for every audio device, keeps the ones whose name
starts with `Yeti Stereo Microphone`, and then keeps only those with input
channels. That second filter matters. macOS splits the Yeti into two devices
that share one name, an input and an output, and only the input carries the
Thru control.

On the matching device it sets `kAudioDevicePropertyPlayThru` to zero.

The launch agent runs the program on two triggers. `RunAtLoad` covers login.
A `LaunchEvents` block with `com.apple.iokit.matching` covers the microphone
being plugged in, watching for the vendor and product IDs from step 4.

The plist runs the program through `/bin/sh` rather than calling it directly,
because launchd does not expand `~` or `$HOME` in its own path settings. A
shell does expand them, which keeps the file usable by any account without
editing.

One caveat is worth stating plainly. `IOMatchLaunchStream`, the key that makes
the plug-in trigger work, is not documented by Apple. It is widely used and it
works here, but Apple could change it. If it ever stops working, replace the
whole `LaunchEvents` block with a timed check, which is documented and
dependable but slower to react:

```xml
<key>StartInterval</key>
<integer>30</integer>
```
