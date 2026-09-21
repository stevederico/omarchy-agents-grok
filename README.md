# omarchy-agents-grok

Grok support for Omarchy's menubar **Agents** panel.

This is the only source tree for that work. Stock Omarchy already treats a
new agent as a collector that prints one JSON record. The panel watches
`~/.local/state/omarchy/agents/usage/` and draws whatever appears there.
Claude, Codex, and Fireworks ship; Grok did not.

Do not copy this into `Projects/omarchy` until you are opening a PR. Do not
keep a second clone under `Projects/plugins` or `omarchy-dotfiles`.

## Layout

| Path | What it is |
|---|---|
| `bin/omarchy-agent-usage-grok` | Collector. Session tokens from `~/.grok/sessions`; weekly SuperGrok credits from the CLI billing endpoint, falling back to `~/.grok/logs/unified.jsonl`. |
| `plugin/sd.agents/` | Live **My Agents** panel (`sd.agents`). Grok is the first chip and the tab the pane opens on. **Overall** sums tokens across every agent that already has a chip. Days under 10M are hidden, and the day header shows the average of the days that remain. A span longer than a week uses dates (`9/11`) instead of repeating weekday names. The Grok weekly meter comes from the billing endpoint on the collector timer, not a manual scrape. |
| `assets/` | Grok SVG marks (and a braille fallback) for an upstream PR. |
| `patches/` | Grok-only delta vs stock `omarchy.agents`. Optional for a first PR. |
| `extras/` | Local timer, path unit, and login hook. Not first-party Omarchy. |
| `tests/` | Token split, session scan, credits stub, and record-contract checks. |

## This machine

```bash
make test
make install-user
systemctl --user enable --now omarchy-agent-usage-grok.timer omarchy-agent-usage-grok.path
```

That installs the collector to `~/.local/lib/omarchy/`, symlinks
`~/.config/omarchy/plugins/sd.agents` at this repo's `plugin/sd.agents`,
and installs the user units. The shell watcher does not follow that
symlink, so after a QML edit run `omarchy-shell shell rescanPlugins` or
`omarchy-restart-shell`. Refresh a record with:

```bash
omarchy-agent-usage-grok --write
omarchy-agent-usage-grok --force --write
```

## Smallest Omarchy PR

`omarchy-agent-usage-update` runs every `omarchy-agent-usage-*` binary in
`$OMARCHY_PATH/bin`. Adding Grok is:

1. `bin/omarchy-agent-usage-grok`
2. `shell/plugins/agents/assets/grok.svg`
3. `shell/plugins/agents/assets/grok-light.svg`
4. A row in `shell/plugins/agents/README.md`

No plugin rename. No panel controls. The stock widget will show a Grok tab
as soon as the collector writes `grok.json`. Keep `plugin/sd.agents` and
`extras/` out of that PR.

Suggested first-PR title: **Add a Grok collector to the Agents panel**.
