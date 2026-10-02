#!/bin/sh
# Puts the shipyard command inside this plugin, at bin/shipyard.
#
# Herdr runs this as the plugin's build step during `herdr plugin install`. It
# downloads the latest shipyard release's build for this machine's
# architecture, checks it against the SHA-256 checksum published beside it,
# and keeps it only when it runs.
#
# SHIPYARD_BINARY=/path/to/shipyard installs that local binary instead, with no
# download, for testing before a release carries Linux builds.
#
# Herdr moves the plugin to its final directory after this step, so linking
# ~/.local/bin/shipyard happens later, from scripts/link-shipyard.sh.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
binary="$root/bin/shipyard"
release_url="https://github.com/yahyabedirhan/shipyard/releases/latest/download"

say() { printf 'herdr-shipyard: %s\n' "$*"; }
fail() {
	printf 'herdr-shipyard: %s\n' "$*" >&2
	exit 1
}

asset_name() {
	case "$(uname -s)" in
	Linux) ;;
	*) fail "shipyard publishes the shipyard command for Linux only; set SHIPYARD_BINARY to install a local binary" ;;
	esac
	case "$(uname -m)" in
	x86_64 | amd64) echo shipyard-linux-x86_64 ;;
	aarch64 | arm64) echo shipyard-linux-aarch64 ;;
	*) fail "shipyard has no Linux build for $(uname -m)" ;;
	esac
}

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d ' ' -f 1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d ' ' -f 1
	else
		fail "neither sha256sum nor shasum is installed, so the download can't be checked"
	fi
}

# A release is published before its Linux files are attached, a few minutes
# later, so a file it lacks (an HTTP error, curl's status 22) is most likely
# still on its way.
download() {
	status=0
	curl --fail --silent --show-error --location --retry 3 --output "$2" "$1" || status=$?
	case "$status" in
	0) ;;
	22) fail "the latest shipyard release has no Linux build yet (${1##*/} isn't there); try again in a few minutes, or set SHIPYARD_BINARY to install a local binary" ;;
	*) fail "couldn't download $1" ;;
	esac
}

# Work beside bin/shipyard, so the finished binary is renamed into place.
mkdir -p "$root/bin"
work=$(mktemp -d "$root/bin/.install.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' INT TERM
candidate="$work/shipyard"

if [ -n "${SHIPYARD_BINARY:-}" ]; then
	if [ ! -f "$SHIPYARD_BINARY" ] || [ ! -x "$SHIPYARD_BINARY" ]; then
		fail "SHIPYARD_BINARY=$SHIPYARD_BINARY isn't an executable file"
	fi
	cp "$SHIPYARD_BINARY" "$candidate"
	source="$SHIPYARD_BINARY"
else
	asset=$(asset_name)
	download "$release_url/$asset" "$candidate"
	download "$release_url/$asset.sha256" "$work/$asset.sha256"
	# The checksum file reads "<hex>  <name>", as sha256sum prints it.
	read -r expected _ <"$work/$asset.sha256" || true
	expected=$(printf '%s' "${expected:-}" | tr 'A-F' 'a-f')
	case "$expected" in
	*[!0-9a-f]* | '') fail "$asset.sha256 doesn't hold a SHA-256 checksum" ;;
	esac
	[ "${#expected}" -eq 64 ] || fail "$asset.sha256 doesn't hold a SHA-256 checksum"
	actual=$(sha256_of "$candidate")
	[ "$actual" = "$expected" ] ||
		fail "$asset doesn't match its published checksum (expected $expected, got $actual)"
	source="$release_url/$asset"
fi

chmod 755 "$candidate"
version=$("$candidate" --version 2>&1) ||
	fail "the shipyard from $source doesn't run on this machine: $version"

mv -f "$candidate" "$binary"
say "installed $version at $binary"
