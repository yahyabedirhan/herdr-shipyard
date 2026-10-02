#!/bin/sh
# Tests the plugin's scripts the way Herdr runs them, with a fake shipyard, a
# fake download (curl), a fake uname and recorded event JSON. Each test gets a
# fresh copy of the plugin and its own HOME.
#
# Usage: sh tests/run.sh
set -u

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
fixtures="$repo/tests/fixtures"
release_url="https://github.com/yahyabedirhan/shipyard/releases/latest/download"
passed=0
failed=0

# --- sandbox -----------------------------------------------------------------

setup() {
	sandbox=$(mktemp -d "${TMPDIR:-/tmp}/herdr-shipyard-test.XXXXXX")
	plugin="$sandbox/herdr-shipyard"
	mkdir -p "$plugin" "$sandbox/home" "$sandbox/fakebin" "$sandbox/release"
	cp -R "$repo/herdr-plugin.toml" "$repo/scripts" "$plugin/"
	cp "$repo/tests/fakes/curl" "$repo/tests/fakes/uname" "$sandbox/fakebin/"
	chmod 755 "$sandbox/fakebin/curl" "$sandbox/fakebin/uname"
	HOME="$sandbox/home"
	PATH="$sandbox/fakebin:$ORIGINAL_PATH"
	FAKE_RELEASE_DIR="$sandbox/release"
	FAKE_CURL_LOG="$sandbox/curl.log"
	FAKE_SHIPYARD_LOG="$sandbox/shipyard.log"
	export HOME PATH FAKE_RELEASE_DIR FAKE_CURL_LOG FAKE_SHIPYARD_LOG
	unset SHIPYARD_BINARY FAKE_UNAME_S FAKE_UNAME_M FAKE_SHIPYARD_EXIT FAKE_SHIPYARD_LIST \
		HERDR_PLUGIN_EVENT HERDR_PLUGIN_EVENT_JSON
	: >"$FAKE_CURL_LOG"
	: >"$FAKE_SHIPYARD_LOG"
}

# Publishes a fake release asset with its checksum file, as the release
# workflow does: "<asset>" and "<asset>.sha256" holding "<hex>  <asset>".
publish() {
	cp "$repo/tests/fakes/shipyard" "$FAKE_RELEASE_DIR/$1"
	(cd "$FAKE_RELEASE_DIR" && sha256sum "$1" >"$1.sha256")
}

local_binary() {
	cp "$repo/tests/fakes/shipyard" "$sandbox/shipyard-local"
	chmod 755 "$sandbox/shipyard-local"
	echo "$sandbox/shipyard-local"
}

install_plugin_binary() {
	mkdir -p "$plugin/bin"
	cp "$repo/tests/fakes/shipyard" "$plugin/bin/shipyard"
	chmod 755 "$plugin/bin/shipyard"
}

run() {
	sh "$@" >"$sandbox/stdout" 2>"$sandbox/stderr"
	status=$?
}

# --- assertions --------------------------------------------------------------

fail() {
	printf '    %s\n' "$*"
	printf '    stdout: %s\n' "$(cat "$sandbox/stdout" 2>/dev/null)"
	printf '    stderr: %s\n' "$(cat "$sandbox/stderr" 2>/dev/null)"
	exit 1
}

assert_status() { [ "$status" -eq "$1" ] || fail "expected exit $1, got $status"; }
assert_contains() { grep -qF -- "$2" "$1" || fail "expected $1 to contain: $2"; }
assert_not_contains() { ! grep -qF -- "$2" "$1" || fail "expected $1 not to contain: $2"; }
assert_lines() {
	printf '%s\n' "$2" >"$sandbox/expected"
	cmp -s "$sandbox/expected" "$1" || fail "expected $1 to be exactly: $2 (it was: $(cat "$1"))"
}
assert_link() {
	[ -L "$HOME/.local/bin/shipyard" ] || fail "expected ~/.local/bin/shipyard to be a link"
	[ "$(readlink "$HOME/.local/bin/shipyard")" = "$1" ] ||
		fail "expected ~/.local/bin/shipyard to link to $1, not $(readlink "$HOME/.local/bin/shipyard")"
}

# --- install-shipyard.sh: the build step -------------------------------------

test_install_downloads_the_x86_64_build_and_checks_it() {
	publish shipyard-linux-x86_64
	run "$plugin/scripts/install-shipyard.sh"
	assert_status 0
	cmp -s "$FAKE_RELEASE_DIR/shipyard-linux-x86_64" "$plugin/bin/shipyard" || fail "bin/shipyard isn't the release asset"
	[ -x "$plugin/bin/shipyard" ] || fail "bin/shipyard isn't executable"
	assert_lines "$FAKE_CURL_LOG" "$release_url/shipyard-linux-x86_64
$release_url/shipyard-linux-x86_64.sha256"
	assert_contains "$sandbox/stdout" "installed shipyard 0.0.6-fake at $plugin/bin/shipyard"
}

test_install_downloads_the_aarch64_build_on_arm() {
	publish shipyard-linux-aarch64
	for arch in aarch64 arm64; do
		: >"$FAKE_CURL_LOG"
		FAKE_UNAME_M=$arch run "$plugin/scripts/install-shipyard.sh"
		assert_status 0
		assert_contains "$FAKE_CURL_LOG" "$release_url/shipyard-linux-aarch64.sha256"
		[ -x "$plugin/bin/shipyard" ] || fail "no bin/shipyard on $arch"
	done
}

test_install_accepts_an_uppercase_checksum() {
	publish shipyard-linux-x86_64
	tr 'a-f' 'A-F' <"$FAKE_RELEASE_DIR/shipyard-linux-x86_64.sha256" >"$sandbox/upper"
	mv "$sandbox/upper" "$FAKE_RELEASE_DIR/shipyard-linux-x86_64.sha256"
	run "$plugin/scripts/install-shipyard.sh"
	assert_status 0
}

test_install_refuses_a_download_that_does_not_match_its_checksum() {
	publish shipyard-linux-x86_64
	echo "tampered" >>"$FAKE_RELEASE_DIR/shipyard-linux-x86_64"
	run "$plugin/scripts/install-shipyard.sh"
	assert_status 1
	assert_contains "$sandbox/stderr" "shipyard-linux-x86_64 doesn't match its published checksum"
	[ ! -e "$plugin/bin/shipyard" ] || fail "a mismatched download was installed"
	[ -z "$(ls -A "$plugin/bin")" ] || fail "the install left files behind: $(ls -A "$plugin/bin")"
}

test_install_refuses_a_checksum_file_without_a_checksum() {
	publish shipyard-linux-x86_64
	echo "not a checksum" >"$FAKE_RELEASE_DIR/shipyard-linux-x86_64.sha256"
	run "$plugin/scripts/install-shipyard.sh"
	assert_status 1
	assert_contains "$sandbox/stderr" "shipyard-linux-x86_64.sha256 doesn't hold a SHA-256 checksum"
	[ ! -e "$plugin/bin/shipyard" ] || fail "an unchecked download was installed"
}

test_install_fails_clearly_when_the_release_has_no_linux_build() {
	run "$plugin/scripts/install-shipyard.sh"
	assert_status 1
	assert_contains "$sandbox/stderr" "couldn't download $release_url/shipyard-linux-x86_64"
	[ ! -e "$plugin/bin/shipyard" ] || fail "something was installed"
}

test_install_fails_when_the_checksum_file_is_missing() {
	publish shipyard-linux-x86_64
	rm "$FAKE_RELEASE_DIR/shipyard-linux-x86_64.sha256"
	run "$plugin/scripts/install-shipyard.sh"
	assert_status 1
	assert_contains "$sandbox/stderr" "couldn't download $release_url/shipyard-linux-x86_64.sha256"
	[ ! -e "$plugin/bin/shipyard" ] || fail "an unchecked download was installed"
}

test_install_fails_on_an_architecture_without_a_build() {
	FAKE_UNAME_M=riscv64 run "$plugin/scripts/install-shipyard.sh"
	assert_status 1
	assert_contains "$sandbox/stderr" "shipyard has no Linux build for riscv64"
	[ ! -s "$FAKE_CURL_LOG" ] || fail "it downloaded something"
}

test_install_fails_off_linux_without_a_local_binary() {
	FAKE_UNAME_S=Darwin run "$plugin/scripts/install-shipyard.sh"
	assert_status 1
	assert_contains "$sandbox/stderr" "for Linux only; set SHIPYARD_BINARY"
}

test_install_refuses_a_build_that_does_not_run() {
	printf '#!/bin/sh\necho "exec format error" >&2\nexit 126\n' >"$FAKE_RELEASE_DIR/shipyard-linux-x86_64"
	(cd "$FAKE_RELEASE_DIR" && sha256sum shipyard-linux-x86_64 >shipyard-linux-x86_64.sha256)
	run "$plugin/scripts/install-shipyard.sh"
	assert_status 1
	assert_contains "$sandbox/stderr" "doesn't run on this machine: exec format error"
	[ ! -e "$plugin/bin/shipyard" ] || fail "a build that doesn't run was installed"
}

test_install_replaces_an_earlier_install() {
	install_plugin_binary
	echo "old" >"$plugin/bin/shipyard"
	chmod 755 "$plugin/bin/shipyard"
	publish shipyard-linux-x86_64
	run "$plugin/scripts/install-shipyard.sh"
	assert_status 0
	cmp -s "$FAKE_RELEASE_DIR/shipyard-linux-x86_64" "$plugin/bin/shipyard" || fail "the old binary is still there"
}

test_install_uses_SHIPYARD_BINARY_without_downloading() {
	binary=$(local_binary)
	SHIPYARD_BINARY=$binary FAKE_UNAME_S=Darwin run "$plugin/scripts/install-shipyard.sh"
	assert_status 0
	cmp -s "$binary" "$plugin/bin/shipyard" || fail "bin/shipyard isn't the local binary"
	[ ! -s "$FAKE_CURL_LOG" ] || fail "it downloaded something"
	assert_contains "$sandbox/stdout" "installed shipyard 0.0.6-fake"
}

test_install_refuses_a_SHIPYARD_BINARY_that_is_not_executable() {
	SHIPYARD_BINARY="$sandbox/missing" run "$plugin/scripts/install-shipyard.sh"
	assert_status 1
	assert_contains "$sandbox/stderr" "SHIPYARD_BINARY=$sandbox/missing isn't an executable file"
	[ ! -e "$plugin/bin/shipyard" ] || fail "something was installed"
}

test_install_does_not_touch_local_bin() {
	publish shipyard-linux-x86_64
	run "$plugin/scripts/install-shipyard.sh"
	assert_status 0
	[ ! -e "$HOME/.local/bin/shipyard" ] || fail "the build step linked ~/.local/bin/shipyard from Herdr's temporary checkout"
}

# --- link-shipyard.sh: ~/.local/bin/shipyard ---------------------------------

test_link_creates_the_link_when_nothing_is_there() {
	install_plugin_binary
	run "$plugin/scripts/link-shipyard.sh"
	assert_status 0
	assert_link "$plugin/bin/shipyard"
	assert_contains "$sandbox/stdout" "linked $HOME/.local/bin/shipyard to $plugin/bin/shipyard"
}

test_link_says_when_local_bin_is_not_on_PATH() {
	install_plugin_binary
	run "$plugin/scripts/link-shipyard.sh"
	assert_contains "$sandbox/stdout" "$HOME/.local/bin isn't on PATH here"
	rm "$HOME/.local/bin/shipyard"
	PATH="$HOME/.local/bin:$PATH" run "$plugin/scripts/link-shipyard.sh"
	assert_not_contains "$sandbox/stdout" "isn't on PATH"
}

test_link_keeps_its_own_link() {
	install_plugin_binary
	mkdir -p "$HOME/.local/bin"
	ln -s "$plugin/bin/shipyard" "$HOME/.local/bin/shipyard"
	run "$plugin/scripts/link-shipyard.sh"
	assert_status 0
	assert_link "$plugin/bin/shipyard"
	assert_contains "$sandbox/stdout" "already links to $plugin/bin/shipyard"
}

test_link_leaves_a_file_that_is_not_its_own_alone_and_reports_it() {
	install_plugin_binary
	mkdir -p "$HOME/.local/bin"
	echo "mine" >"$HOME/.local/bin/shipyard"
	run "$plugin/scripts/link-shipyard.sh"
	assert_status 0
	[ ! -L "$HOME/.local/bin/shipyard" ] || fail "it replaced the file"
	assert_contains "$HOME/.local/bin/shipyard" "mine"
	assert_contains "$sandbox/stdout" "is already there and isn't this plugin's; left it alone. This plugin's shipyard is $plugin/bin/shipyard"
}

test_link_leaves_someone_elses_link_alone_and_reports_it() {
	install_plugin_binary
	mkdir -p "$HOME/.local/bin" "$sandbox/elsewhere/bin"
	echo "other" >"$sandbox/elsewhere/bin/shipyard"
	ln -s "$sandbox/elsewhere/bin/shipyard" "$HOME/.local/bin/shipyard"
	run "$plugin/scripts/link-shipyard.sh"
	assert_status 0
	assert_link "$sandbox/elsewhere/bin/shipyard"
	assert_contains "$sandbox/stdout" "links to $sandbox/elsewhere/bin/shipyard, which isn't this plugin's; left it alone"
}

test_link_leaves_a_dangling_link_elsewhere_alone() {
	install_plugin_binary
	mkdir -p "$HOME/.local/bin"
	ln -s "/opt/gone/bin/shipyard" "$HOME/.local/bin/shipyard"
	run "$plugin/scripts/link-shipyard.sh"
	assert_status 0
	assert_link "/opt/gone/bin/shipyard"
}

test_link_moves_a_link_from_another_herdr_shipyard_directory() {
	install_plugin_binary
	other="$sandbox/old-checkout/herdr-shipyard"
	mkdir -p "$other/bin" "$HOME/.local/bin"
	cp "$plugin/herdr-plugin.toml" "$other/"
	cp "$plugin/bin/shipyard" "$other/bin/shipyard"
	ln -s "$other/bin/shipyard" "$HOME/.local/bin/shipyard"
	run "$plugin/scripts/link-shipyard.sh"
	assert_status 0
	assert_link "$plugin/bin/shipyard"
}

test_link_replaces_a_link_left_dangling_by_a_removed_plugin() {
	install_plugin_binary
	mkdir -p "$HOME/.local/bin"
	ln -s "$sandbox/plugins/github/yahyabedirhan.herdr-shipyard-0123abcd/bin/shipyard" "$HOME/.local/bin/shipyard"
	run "$plugin/scripts/link-shipyard.sh"
	assert_status 0
	assert_link "$plugin/bin/shipyard"
}

test_link_fails_clearly_without_a_binary() {
	run "$plugin/scripts/link-shipyard.sh"
	assert_status 1
	assert_contains "$sandbox/stdout" "this plugin has no shipyard at $plugin/bin/shipyard yet"
	[ ! -e "$HOME/.local/bin/shipyard" ] || fail "it linked a missing binary"
}

test_link_quiet_says_nothing() {
	run "$plugin/scripts/link-shipyard.sh" --quiet
	assert_status 0
	install_plugin_binary
	mkdir -p "$HOME/.local/bin"
	echo "mine" >"$HOME/.local/bin/shipyard"
	run "$plugin/scripts/link-shipyard.sh" --quiet
	assert_status 0
	[ ! -s "$sandbox/stdout" ] || fail "--quiet printed something"
}

# --- shipyard.sh: the event hooks and the list action ------------------------

# Runs the hook the way Herdr does: from the plugin directory, with the event's
# name and recorded JSON in the environment.
run_event() {
	(cd "$plugin" && HERDR_PLUGIN_EVENT="$1" HERDR_PLUGIN_EVENT_JSON="$(cat "$2")" \
		sh scripts/shipyard.sh herdr-event) >"$sandbox/stdout" 2>"$sandbox/stderr"
	status=$?
}

test_blocked_agent_runs_herdr_event_from_root_with_herdrs_environment() {
	install_plugin_binary
	run_event pane.agent_status_changed "$fixtures/events/pane-agent-status-changed-blocked.json"
	assert_status 0
	assert_lines "$FAKE_SHIPYARD_LOG" "args=herdr-event
cwd=/
event=pane.agent_status_changed
event_json=$(cat "$fixtures/events/pane-agent-status-changed-blocked.json")"
}

test_working_agent_runs_herdr_event() {
	install_plugin_binary
	run_event pane.agent_status_changed "$fixtures/events/pane-agent-status-changed-working.json"
	assert_status 0
	assert_contains "$FAKE_SHIPYARD_LOG" '"agent_status":"working"'
}

test_closed_pane_runs_herdr_event() {
	install_plugin_binary
	run_event pane.closed "$fixtures/events/pane-closed.json"
	assert_status 0
	assert_lines "$FAKE_SHIPYARD_LOG" "args=herdr-event
cwd=/
event=pane.closed
event_json=$(cat "$fixtures/events/pane-closed.json")"
}

test_a_failing_herdr_event_fails_the_hook() {
	install_plugin_binary
	FAKE_SHIPYARD_EXIT=3 run_event pane.closed "$fixtures/events/pane-closed.json"
	assert_status 3
}

test_hook_links_shipyard_when_nothing_is_there() {
	install_plugin_binary
	run_event pane.closed "$fixtures/events/pane-closed.json"
	assert_link "$plugin/bin/shipyard"
}

test_hook_leaves_another_shipyard_alone_silently() {
	install_plugin_binary
	mkdir -p "$HOME/.local/bin"
	echo "mine" >"$HOME/.local/bin/shipyard"
	run_event pane.closed "$fixtures/events/pane-closed.json"
	assert_status 0
	assert_contains "$HOME/.local/bin/shipyard" "mine"
	if [ -s "$sandbox/stdout" ] || [ -s "$sandbox/stderr" ]; then fail "the hook printed something"; fi
}

test_hook_fails_clearly_without_a_binary() {
	run_event pane.closed "$fixtures/events/pane-closed.json"
	assert_status 1
	assert_contains "$sandbox/stderr" "this plugin has no shipyard"
}

test_list_action_prints_shipyards_json_untouched() {
	install_plugin_binary
	(cd "$plugin" && FAKE_SHIPYARD_LIST="$fixtures/ping-list.json" \
		sh scripts/shipyard.sh ping list --json) >"$sandbox/stdout" 2>"$sandbox/stderr"
	status=$?
	assert_status 0
	cmp -s "$fixtures/ping-list.json" "$sandbox/stdout" || fail "the action's stdout isn't shipyard's JSON"
	assert_lines "$FAKE_SHIPYARD_LOG" "args=ping list --json
cwd=/
event=
event_json="
}

# --- herdr-plugin.toml -------------------------------------------------------

test_manifest_declares_the_plugin_and_its_commands() {
	python3 - "$repo/herdr-plugin.toml" >"$sandbox/stdout" 2>"$sandbox/stderr" <<'EOF' || fail "manifest check failed"
import os, sys, tomllib
path = sys.argv[1]
m = tomllib.load(open(path, "rb"))
root = os.path.dirname(path)
assert m["id"] == "yahyabedirhan.herdr-shipyard", m["id"]
assert m["name"] == "herdr-shipyard", m["name"]
assert m["min_herdr_version"] == "0.9.0", m["min_herdr_version"]
assert m["platforms"] == ["linux", "macos"], m["platforms"]
assert m["build"] == [{"command": ["sh", "scripts/install-shipyard.sh"], "platforms": ["linux"]}], m["build"]
events = {e["on"]: e["command"] for e in m["events"]}
hook = ["sh", "scripts/shipyard.sh", "herdr-event"]
assert events == {"pane.agent_status_changed": hook, "pane.closed": hook}, events
actions = {a["id"]: a["command"] for a in m["actions"]}
assert actions["list"] == ["sh", "scripts/shipyard.sh", "ping", "list", "--json"], actions
for entry in m["build"] + m["startup"] + m["actions"] + m["events"]:
    assert os.path.isfile(os.path.join(root, entry["command"][1])), entry
EOF
}

# --- runner ------------------------------------------------------------------

ORIGINAL_PATH=$PATH
tests=$(grep -E '^test_[A-Za-z0-9_]+\(\)' "$0" | sed 's/().*//')
for name in $tests; do
	if (setup && "$name") >"${TMPDIR:-/tmp}/herdr-shipyard-test.out" 2>&1; then
		passed=$((passed + 1))
		printf 'ok   %s\n' "$name"
	else
		failed=$((failed + 1))
		printf 'FAIL %s\n' "$name"
		cat "${TMPDIR:-/tmp}/herdr-shipyard-test.out"
	fi
done
rm -f "${TMPDIR:-/tmp}/herdr-shipyard-test.out"
rm -rf "${TMPDIR:-/tmp}"/herdr-shipyard-test.??????

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
