#!/bin/sh
# Links ~/.local/bin/shipyard to this plugin's shipyard, so agents find it on
# their PATH.
#
# It replaces only a link this plugin made: one into a herdr-shipyard plugin, or
# one left dangling by a plugin directory that's gone. Anything else already at
# ~/.local/bin/shipyard is left alone and reported.
#
# Herdr runs it at startup and as the `link` action, and scripts/shipyard.sh
# runs it with --quiet before every command, which keeps the link in place
# without reporting anything.
set -eu

quiet=false
[ "${1:-}" = "--quiet" ] && quiet=true

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
binary="$root/bin/shipyard"
link_dir="$HOME/.local/bin"
link="$link_dir/shipyard"
plugin_id="yahyabedirhan.herdr-shipyard"

say() { [ "$quiet" = true ] || printf 'herdr-shipyard: %s\n' "$*"; }

# A herdr-shipyard plugin directory's binary, or a dangling link to where one
# used to be.
made_by_this_plugin() {
	case "$1" in
	/*/bin/shipyard) ;;
	*) return 1 ;;
	esac
	if [ ! -e "$1" ]; then
		case "$1" in
		*herdr-shipyard*) return 0 ;;
		*) return 1 ;;
		esac
	fi
	grep -qxF "id = \"$plugin_id\"" "${1%/bin/shipyard}/herdr-plugin.toml" 2>/dev/null
}

if [ ! -x "$binary" ]; then
	say "this plugin has no shipyard at $binary yet; reinstall the plugin, or run scripts/install-shipyard.sh"
	[ "$quiet" = true ] && exit 0
	exit 1
fi

if [ -L "$link" ]; then
	current=$(readlink "$link")
	if [ "$current" = "$binary" ]; then
		say "$link already links to $binary"
		exit 0
	fi
	if ! made_by_this_plugin "$current"; then
		say "$link links to $current, which isn't this plugin's; left it alone. This plugin's shipyard is $binary"
		exit 0
	fi
elif [ -e "$link" ]; then
	say "$link is already there and isn't this plugin's; left it alone. This plugin's shipyard is $binary"
	exit 0
fi

mkdir -p "$link_dir"
# A new link renamed over the old one, so a command never sees it missing.
ln -sf "$binary" "$link.herdr-shipyard.$$"
mv -f "$link.herdr-shipyard.$$" "$link"
say "linked $link to $binary"

case ":${PATH:-}:" in
*":$link_dir:"*) ;;
*) say "$link_dir isn't on PATH here; add it to your shell's PATH so agents find shipyard" ;;
esac
