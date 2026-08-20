# disable-thru

macOS forgets the **Thru** setting on a USB audio input device. Thru routes the
device's input straight back to its own output, so you hear yourself. If you do
not want that, you turn it off in Audio MIDI Setup, and macOS turns it back on
at the next restart.

This is not a bug in your settings. The Thru state lives on the CoreAudio device
object rather than in a preference file. macOS rebuilds that object from the
driver default every time the device appears, which means every restart and
every time you unplug the device.

Nothing you click in Audio MIDI Setup can survive that, because there is no file
to save it in. This program turns Thru off, and a launch agent runs it at the
right moments.

Written for a Blue Yeti, but it works with any input device that exposes a Thru
setting.

## Requirements

- macOS. The program uses CoreAudio, and the launch agent uses launchd.
- The **Command Line Tools**, which supply the Swift compiler. Check with
  `swiftc --version`. If that fails, run `xcode-select --install`.
- [`just`](https://github.com/casey/just), for the recipes below.
- [`fzf`](https://github.com/junegunn/fzf) is optional. The device picker uses
  it when present, and falls back to a numbered menu otherwise.

Tested on macOS 26. The CoreAudio and launchd interfaces are long established,
so earlier versions should also work.

## Quick start

```sh
git clone https://github.com/mapitman/disable-thru.git
cd disable-thru
just configure
just install
```

`just configure` builds the program, asks which device to target, and writes a
launch agent for it. `just install` loads that agent.

Then confirm it worked. Turn Thru on in Audio MIDI Setup, unplug the device,
plug it back in, and wait about ten seconds. Thru should switch itself off.

## The recipes

Run `just` with no arguments to list them.

| Recipe | What it does |
| --- | --- |
| `just build` | Compiles the program to `~/.local/bin/disable-thru`. |
| `just list` | Lists the input devices that expose a Thru setting. |
| `just pick` | Turns Thru off now, on a device you pick from a list. |
| `just configure` | Picks a device and writes the launch agent for it. |
| `just configure-for "<name>"` | The same, without the picker. |
| `just install` | Loads the launch agent. |
| `just status` | Shows whether the agent is registered, and its last exit status. |
| `just uninstall` | Unloads and removes the agent. |
| `just clean` | Deletes the compiled program. |
| `just ids` | Prints a USB device's vendor and product IDs. |
| `just usb` | Lists every USB device with its IDs. |

## Using the program directly

The program takes a device name, matched as a prefix:

```sh
disable-thru "Yeti Stereo Microphone"
```

It reports which device it changed, including the CoreAudio device ID:

```
Thru disabled: Yeti Stereo Microphone [id 114]
```

That ID changes between restarts and replugs, which is why the program matches
on the name instead.

To see the devices it can act on:

```sh
disable-thru --list
```

The list holds only devices that have input channels and expose a Thru setting,
so most audio devices do not appear.

## Why a launch agent

An `on-window-detected` rule or a login item is not enough here, for two
different reasons.

A login item starts the program inside a shell session, so it opens a terminal
window and keeps it open.

A launch agent has no terminal. It also supports two triggers, and this program
needs both:

- `RunAtLoad` covers logging in.
- A `LaunchEvents` block with `com.apple.iokit.matching` covers the device being
  plugged in.

The generated agent retries for up to ten seconds on the second trigger. The USB
device attaches before CoreAudio finishes registering it, so the first attempt
would otherwise find nothing.

## How the configuration works

`dist/local.disable-thru.plist.template` is a template, not a finished plist. It
holds three placeholders:

| Placeholder | Filled with |
| --- | --- |
| `__DEVICE_NAME__` | The device you chose. |
| `__ID_VENDOR__` | Its USB vendor ID, in decimal. |
| `__ID_PRODUCT__` | Its USB product ID, in decimal. |

`just configure` reads the USB IDs from the `IOAudioDeviceModelID` property in
the I/O registry, which holds them in the form `<name>:<vendor>:<product>`. That
is an exact link from the audio device to its USB identity, so the IDs are never
guessed from the device names, which do not match: a Blue Yeti reports as `Yeti
Stereo Microphone` to CoreAudio and as `Blue Microphones` over USB.

The generated `dist/local.disable-thru.plist` is ignored by git, because it is
specific to one machine's hardware. Re-run `just configure` after changing
device, then `just install`.

## Troubleshooting

Run the program by hand first:

```sh
just build
~/.local/bin/disable-thru --list
```

If your device is not listed, it has no Thru setting that CoreAudio exposes, and
no launch agent will change that.

To make the agent run immediately, without unplugging anything:

```sh
launchctl kickstart -k gui/$(id -u)/local.disable-thru
tail -5 ~/Library/Logs/disable-thru.log
```

For a wider view, read the system log:

```sh
log show --predicate 'eventMessage CONTAINS "disable-thru"' --last 10m
```

If logging in works but plugging the device in does not, the USB IDs in the
generated plist are probably wrong. Re-run `just configure` with the device
connected.

Note that `system_profiler SPUSBDataType` shows USB details in a friendlier
layout than `ioreg`, but it returns nothing in some environments. The recipes use
`ioreg` for that reason.

## A caveat

`IOMatchLaunchStream`, the key that makes the plug-in trigger work, is not
documented by Apple. It is widely used and it works, but Apple could change it.
If it ever stops working, replace the whole `LaunchEvents` block in the template
with a timed check, which is documented and dependable but slower to react:

```xml
<key>StartInterval</key>
<integer>30</integer>
```

## How it works

The program asks CoreAudio for every audio device, keeps the ones whose name
starts with the name you gave, and then keeps only those with input channels.
That last filter matters: macOS splits a Yeti into two devices that share one
name, an input and an output, and only the input carries the Thru control.

On the matching device it sets `kAudioDevicePropertyPlayThru` to zero.

## License

MIT. See [LICENSE](LICENSE).
