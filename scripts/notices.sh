#!/bin/sh
# Holds shipyard's notices on this machine until the Mac's poll collects them.
#
# A notice is opaque: this script never looks inside one.
#
#   notices.sh add <id>      stores the notice on standard input under <id>,
#                            replacing the one stored under it
#   notices.sh list          prints the stored notices, oldest first (the
#                            `notices` action)
#   notices.sh read          removes the notices the last listing handed out,
#                            unless replaced since (the `notices-read` action)
#   notices.sh remove <id>…  removes the notices stored under those ids
#
# A notice lives in ~/.local/share/shipyard/notices as <hex of its id>.json,
# so any id is a safe file name, and is dropped an hour after it was stored.
set -eu

notices="$HOME/.local/share/shipyard/notices"
# What the last listing handed out: one "<file> <cksum>" line per notice.
handed="$notices/.handed"
retention_minutes=60
# Herdr keeps 64 KiB of an action's output; shipyard's ping list stays within
# 48 KiB, and so does a listing here.
byte_budget=49152
envelope_size=$(printf '{"version":1,"truncated":false,"notices":[]}\n' | wc -c)

say() { printf 'herdr-shipyard: %s\n' "$*" >&2; }

usage() {
	say "usage: notices.sh add <id> | list | read | remove <id>..."
	exit 2
}

# This run's temporary files, beside the notices and removed however the
# run ends. One left by a killed run is pruned.
trap 'rm -f "$notices"/.tmp.$$.*' EXIT
temporary() {
	mkdir -p "$1"
	echo "$1/.tmp.$$.$2"
}

# The file a notice with the id $1 is stored in.
file_for() {
	printf '%s/%s.json' "$notices" "$(printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n')"
}

# Drops whatever has waited more than an hour: notices, and an old listing or
# temporary file left behind.
prune() {
	[ -d "$notices" ] || return 0
	find "$notices" -type f -mmin +"$retention_minutes" -exec rm -f {} +
}

add() {
	if [ $# -ne 1 ] || [ -z "$1" ]; then usage; fi
	incoming=$(temporary "$notices" incoming)
	cat >"$incoming"
	size=$(wc -c <"$incoming")
	if [ "$size" -eq 0 ]; then
		say "no notice on standard input"
		exit 2
	fi
	if [ $((envelope_size + size)) -gt "$byte_budget" ]; then
		say "the notice is $size bytes, more than a listing can carry ($((byte_budget - envelope_size)) bytes)"
		exit 1
	fi
	mv -f "$incoming" "$(file_for "$1")"
	prune
}

list() {
	prune
	body=$(temporary "$notices" body)
	listing=$(temporary "$notices" listing)
	snapshot=$(temporary "$notices" snapshot)
	size=$envelope_size
	truncated=false
	count=0
	: >"$body"
	: >"$listing"
	# Oldest first by when each was stored. The names are hex, so they split
	# safely, and `ls` leaves out the dot files beside them.
	# shellcheck disable=SC2045
	for name in $(ls -tr "$notices"); do
		case "$name" in *.json) ;; *) continue ;; esac
		# A notice removed or replaced since `ls` is skipped or listed whole.
		cat "$notices/$name" >"$snapshot" 2>/dev/null || continue
		cost=$(wc -c <"$snapshot")
		[ "$count" -eq 0 ] || cost=$((cost + 1))
		if [ $((size + cost)) -gt "$byte_budget" ]; then
			truncated=true
			break
		fi
		[ "$count" -eq 0 ] || printf ',' >>"$body"
		cat "$snapshot" >>"$body"
		printf '%s %s\n' "$name" "$(cksum <"$snapshot")" >>"$listing"
		size=$((size + cost))
		count=$((count + 1))
	done
	if [ "$count" -gt 0 ]; then mv -f "$listing" "$handed"; else rm -f "$handed"; fi
	printf '{"version":1,"truncated":%s,"notices":[' "$truncated"
	cat "$body"
	printf ']}\n'
}

read_listed() {
	removed=0
	taken=$(temporary "$notices" taken)
	# Taking the listing means a second read, or one racing this, removes
	# nothing twice.
	if mv -f "$handed" "$taken" 2>/dev/null; then
		while read -r name sum; do
			[ -f "$notices/$name" ] || continue
			# Replaced since it was listed: the Mac hasn't read this one.
			[ "$(cksum <"$notices/$name" 2>/dev/null)" = "$sum" ] || continue
			rm -f "$notices/$name"
			removed=$((removed + 1))
		done <"$taken"
	fi
	printf '{"version":1,"removed":%s}\n' "$removed"
}

remove() {
	[ $# -gt 0 ] || usage
	for id in "$@"; do
		rm -f "$(file_for "$id")"
	done
}

command=${1:-}
[ $# -eq 0 ] || shift
case "$command" in
add) add "$@" ;;
list) [ $# -eq 0 ] || usage && list ;;
read) [ $# -eq 0 ] || usage && read_listed ;;
remove) remove "$@" ;;
*) usage ;;
esac
