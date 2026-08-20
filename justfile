# Show the available recipes.
default:
	@just --list

# Compile the program to ~/.local/bin/disable-thru.
build:
	@mkdir -p ~/.local/bin
	swiftc -O -o ~/.local/bin/disable-thru disable-thru.swift
	@echo "Built ~/.local/bin/disable-thru"

# List the input devices that expose a Thru setting.
list: build
	@~/.local/bin/disable-thru --list

# Turn Thru off now, on a device you pick from a list.
pick: build
	#!/usr/bin/env bash
	set -euo pipefail

	device=$(just --quiet _choose)
	[ -n "${device:-}" ] || { echo "Nothing selected." >&2; exit 1; }
	~/.local/bin/disable-thru "$device"

# Pick a device, then generate dist/local.disable-thru.plist for it.
configure: build
	#!/usr/bin/env bash
	set -euo pipefail

	device=$(just --quiet _choose)
	[ -n "${device:-}" ] || { echo "Nothing selected." >&2; exit 1; }
	just --quiet _write-plist "$device"

# Generate the plist for a named device, without the interactive picker.
configure-for device:
	@just --quiet _write-plist "{{ device }}"

# Fill in the template for a device and check the result parses.
[private]
_write-plist device:
	#!/usr/bin/env bash
	set -euo pipefail

	# IOAudioDeviceModelID carries the USB vendor and product IDs in hex, as
	# "<name>:<vendor>:<product>". That is an exact link from the audio device
	# to its USB identity, so nothing has to be guessed from the names.
	model=$(ioreg -r -c IOAudioDevice -l \
		| grep -A40 "\"IOAudioDeviceName\" = \"{{ device }}\"" \
		| grep '"IOAudioDeviceModelID"' | head -1 | sed 's/.*= //' | tr -d '"')

	if [ -z "$model" ]; then
		model=$(ioreg -r -c IOAudioDevice -l \
			| grep '"IOAudioDeviceModelID"' \
			| grep -F "{{ device }}" | head -1 | sed 's/.*= //' | tr -d '"')
	fi

	# Split "<name>:<vendor>:<product>" from the right, because the device name
	# itself may contain a colon.
	product_hex="${model##*:}"
	rest="${model%:*}"
	vendor_hex="${rest##*:}"

	if [ -z "$model" ] || [ "$vendor_hex" = "$model" ]; then
		echo "Could not read the USB IDs for '{{ device }}'." >&2
		echo "The device may not be USB. Check with: just usb" >&2
		exit 1
	fi

	vendor=$((16#$vendor_hex))
	product=$((16#$product_hex))

	sed -e "s/__DEVICE_NAME__/{{ device }}/g" \
		-e "s/__ID_VENDOR__/$vendor/g" \
		-e "s/__ID_PRODUCT__/$product/g" \
		dist/local.disable-thru.plist.template > dist/local.disable-thru.plist

	plutil -lint dist/local.disable-thru.plist
	echo "Wrote dist/local.disable-thru.plist"
	echo "  device  : {{ device }}"
	echo "  usb ids : vendor $vendor (0x$vendor_hex), product $product (0x$product_hex)"
	echo
	echo "Install it with: just install"

# Print the chosen device name. Used by the recipes above.
[private]
_choose:
	#!/usr/bin/env bash
	set -euo pipefail

	devices=$(~/.local/bin/disable-thru --list)
	if [ -z "$devices" ]; then
		echo "No input devices with a Thru setting found." >&2
		exit 1
	fi

	# fzf gives a searchable list. Without it, fall back to a numbered menu so
	# the recipe still works on a machine that has no fzf.
	if command -v fzf >/dev/null 2>&1; then
		printf '%s\n' "$devices" | fzf --prompt='Device: ' --height=~10 --no-multi
	else
		PS3='Device: '
		select device in $devices; do
			[ -n "${device:-}" ] && break
		done
		printf '%s\n' "$device"
	fi

# Print a USB device's vendor and product IDs. Find the name with `just usb`.
ids device:
	#!/usr/bin/env bash
	set -euo pipefail

	ids=$(ioreg -r -c IOUSBHostDevice -n "{{ device }}" -l \
		| grep -E '"(idVendor|idProduct)"' \
		| sed 's/^[ |]*//' \
		| sort -u)

	if [ -z "$ids" ]; then
		echo "No USB device named '{{ device }}'." >&2
		echo "List them all with: just usb" >&2
		exit 1
	fi

	echo "$ids"
	echo
	echo "\`just configure\` fills these in for you. This recipe is for"
	echo "checking them by hand."

# List every USB device with its vendor and product IDs.
usb:
	@ioreg -r -c IOUSBHostDevice -l \
		| grep -E '"(USB Product Name|idVendor|idProduct)"' \
		| sed 's/^[ |]*//'

# Install the launch agent, so Thru stays off across restarts and replugs.
install: build
	cp dist/local.disable-thru.plist ~/Library/LaunchAgents/
	launchctl unload ~/Library/LaunchAgents/local.disable-thru.plist 2>/dev/null || true
	launchctl load ~/Library/LaunchAgents/local.disable-thru.plist
	@echo "Loaded. Check it with: just status"

# Show whether the launch agent is registered, and its last exit status.
status:
	@launchctl list | grep disable-thru || echo "Not loaded."

# Remove the launch agent.
uninstall:
	-launchctl unload ~/Library/LaunchAgents/local.disable-thru.plist
	rm -f ~/Library/LaunchAgents/local.disable-thru.plist
	@echo "Removed the launch agent. ~/.local/bin/disable-thru is still in place."

# Delete the compiled program.
clean:
	rm -f ~/.local/bin/disable-thru
