# herdr-shipyard

A [Herdr](https://herdr.dev) plugin that lets agents on your other machines ping [shipyard](https://github.com/yahyabedirhan/shipyard), the macOS menu bar app, on your Mac.

Install it on each Linux machine where your agents run in Herdr. It:

- puts the `shipyard` command on the machine, so an agent there sends a ping with the same `shipyard ping "<title>"` it would use on your Mac;
- pings you by itself when an agent on the machine is blocked waiting for you, naming the agent and its tab, and withdraws that ping when the agent goes on or its pane closes;
- answers your Mac's shipyard when it asks the machine for its pings;
- holds the notices agents post with `shipyard notify` until your Mac's shipyard collects them (see [Notices](#notices)).

Your Mac reaches the machine through Herdr's own connection to it. Nothing on the machine reaches out to your Mac, and shipyard never runs `ssh` or opens a port.

## Install

On the machine (Linux, x86_64 or aarch64, Herdr 0.9.0 or later):

```sh
herdr plugin install yahyabedirhan/herdr-shipyard
```

The install downloads the latest shipyard release's `shipyard` command for the machine's architecture, checks it against the SHA-256 checksum published with the release, and keeps it inside the plugin. Herdr shows you the commands it'll run before you confirm.

The plugin then links `~/.local/bin/shipyard` to its `shipyard`, the next time Herdr starts or an agent's status changes. To link it straight away:

```sh
herdr plugin action invoke link --plugin yahyabedirhan.herdr-shipyard
herdr plugin log list --plugin yahyabedirhan.herdr-shipyard
```

If `~/.local/bin/shipyard` already exists and isn't the plugin's, the plugin leaves it alone and says so in that log. Make sure `~/.local/bin` is on your shell's `PATH` so agents find `shipyard`.

To update `shipyard` after a new shipyard release, install the plugin again.

## On your Mac

Name the machine in shipyard's `config.toml` by its label in Herdr's saved machines, the label you'd pass to `herdr --machine`:

```toml
[remote]
machines = ["my-vps"]
```

Shipyard then asks the machine for its pings every 30 seconds and on ⌘R, through Herdr. The Mac doesn't need this plugin: shipyard's own `shipyard` command handles pings there. Installing the plugin on macOS is harmless; it does nothing there.

## What runs, and when

| When | What runs |
|---|---|
| `herdr plugin install` | `scripts/install-shipyard.sh`: downloads, checks and keeps `shipyard` |
| Herdr starts, or you invoke the `link` action | `scripts/link-shipyard.sh`: links `~/.local/bin/shipyard` |
| An agent's status changes, or a pane closes | `shipyard herdr-event`, which sends or withdraws the blocked ping |
| A tab or workspace closes | `shipyard herdr-event`, which withdraws the blocked pings of the panes that closed with it (Herdr sends no `pane.closed` for them) |
| Your Mac's shipyard asks for pings (the `list` action) | `shipyard ping list --json` |
| Your Mac's shipyard asks for notices (the `notices` action) | `scripts/notices.sh list` |
| Your Mac's shipyard has read them (the `notices-read` action) | `scripts/notices.sh read` |

## Notices

A notice is a disposable status message an agent posts with `shipyard notify`. On a machine with no faster route to your Mac, `shipyard` hands the notice to this plugin, and your Mac's shipyard collects it on the same poll that collects pings. The plugin treats a notice as opaque JSON: it stores it as given and never looks inside.

`scripts/notices.sh` holds them. `shipyard` on the machine finds it beside itself: `~/.local/bin/shipyard` links to the plugin's `bin/shipyard`, and the script is the plugin's `scripts/notices.sh`.

| Command | What it does |
|---|---|
| `notices.sh add <id>` | Stores the notice on standard input under `<id>`, replacing the one stored under the same id. The notice is a JSON object with at least an `id` and a `sent` time; `<id>` is that `id`. Exits 2 with nothing on standard input, and 1 for a notice larger than a listing can carry (about 48 KiB). |
| `notices.sh list` | Prints the stored notices, oldest first by when each was stored (two stored within a few milliseconds may come in either order), as one line: `{"version":1,"truncated":false,"notices":[…]}`. The document stays within 48 KiB; when the next notice wouldn't fit, the listing stops and `truncated` is `true`, and the rest wait for the next poll. It remembers which notices it handed out, for `read`. |
| `notices.sh read` | Removes the notices the last listing handed out, except any replaced since (the Mac hasn't read the new one), and prints `{"version":1,"removed":<count>}`. A second read, without a listing between, removes nothing. Meant for one Mac: a listing made between another's `notices` and `notices-read` hands out the notices that one removes. |
| `notices.sh remove <id>…` | Removes the notices stored under those ids, if any. |

Herdr actions take no arguments, so the Mac reaches the two that need none: `notices` runs `list`, and `notices-read` runs `read`. A poll invokes `notices`, reads its output from the plugin's command log as it does for pings, and then invokes `notices-read`.

On disk, in `~/.local/share/shipyard` beside shipyard's own `pings`:

- `notices/<id>.json` holds each notice as given, its file named by the id's bytes in lowercase hex, so any id is a safe name. A notice is dropped an hour after it was stored, read or not, as is anything else in `notices/` that old.

Shipyard's plan also has the Mac leave each machine a settings copy (which projects have notices turned off), so `shipyard` there can refuse those notices at once. That waits on Herdr plugin actions accepting data: today an action takes no arguments, so the Mac has no way to hand the copy over.

## Trying a local build

Before a shipyard release carries Linux builds, or to try your own, point `SHIPYARD_BINARY` at a `shipyard` you built and link the plugin from a clone:

```sh
git clone https://github.com/yahyabedirhan/herdr-shipyard
cd herdr-shipyard
SHIPYARD_BINARY=/path/to/shipyard sh scripts/install-shipyard.sh
herdr plugin link "$PWD"
herdr plugin action invoke link --plugin yahyabedirhan.herdr-shipyard
```

`herdr plugin link` doesn't run the install step, so run it yourself first, and again after rebuilding `shipyard`.

## Uninstall

```sh
herdr plugin uninstall yahyabedirhan.herdr-shipyard
rm ~/.local/bin/shipyard   # if it links to the plugin
```

Pings already sent on the machine stay in `~/.local/share/shipyard/pings` until they expire. Notices waiting in `~/.local/share/shipyard/notices` stay too, until an hour after each was stored.

## Development

```sh
shellcheck scripts/*.sh tests/run.sh tests/fakes/*
sh tests/run.sh
```

The tests run the scripts as Herdr does, with a fake `shipyard`, a fake download and recorded Herdr event JSON. They need `python3` 3.11 or later.

## License

MIT
