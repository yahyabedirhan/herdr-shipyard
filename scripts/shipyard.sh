#!/bin/sh
# Runs this plugin's shipyard with the given arguments. Herdr's event hooks and
# the `list` action go through it.
#
# It first makes sure ~/.local/bin/shipyard links here (quietly), so the
# command is on agents' PATH soon after an install, then hands over to
# shipyard with Herdr's environment (HERDR_PLUGIN_EVENT,
# HERDR_PLUGIN_EVENT_JSON and the rest) untouched.
#
# Herdr runs plugin commands inside the plugin's directory, a git checkout of
# this repository. Shipyard runs from / instead, so a ping never takes this
# plugin's repository for the agent's.
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
binary="${here%/scripts}/bin/shipyard"

if [ ! -x "$binary" ]; then
	printf 'herdr-shipyard: this plugin has no shipyard at %s; reinstall the plugin, or run scripts/install-shipyard.sh\n' "$binary" >&2
	exit 1
fi

sh "$here/link-shipyard.sh" --quiet >/dev/null || true
cd /
exec "$binary" "$@"
