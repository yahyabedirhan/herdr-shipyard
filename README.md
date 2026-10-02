# herdr-shipyard

A [Herdr](https://herdr.dev) plugin that lets agents on your other machines ping [shipyard](https://github.com/yahyabedirhan/shipyard), the macOS menu bar app, on your Mac.

Install it on each Linux machine where your agents run in Herdr. It:

- puts the `shipyard` command on the machine, so an agent there sends a ping with the same `shipyard ping "<title>"` it would use on your Mac;
- pings you by itself when an agent on the machine is blocked waiting for you, naming the agent and its tab, and withdraws that ping when the agent goes on or its pane closes;
- answers your Mac's shipyard when it asks the machine for its pings.

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

Pings already sent on the machine stay in `~/.local/share/shipyard/pings` until they expire.

## Development

```sh
shellcheck scripts/*.sh tests/run.sh tests/fakes/*
sh tests/run.sh
```

The tests run the scripts as Herdr does, with a fake `shipyard`, a fake download and recorded Herdr event JSON.

## License

MIT
