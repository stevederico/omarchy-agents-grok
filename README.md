<div align="center">

# omarchy-agents-grok

### grok usage in the omarchy agents menubar

</div>

<br />

Stock Omarchy draws an Agents panel from JSON records in
`~/.local/state/omarchy/agents/usage/`. Claude, Codex, and Fireworks ship
a collector. Grok does not. This repo is the Grok collector, the Grok marks,
and the live `sd.agents` panel that shows them.

<br />

## 🚀 **Quick start**

```bash
make test
make install-user
systemctl --user enable --now omarchy-agent-usage-grok.timer omarchy-agent-usage-grok.path
```

`make install-user` copies the collector to `~/.local/lib/omarchy/`, links it
onto `~/.local/bin`, symlinks `~/.config/omarchy/plugins/sd.agents` at
`plugin/sd.agents`, and installs the user units.

The shell does not follow that symlink. After a QML edit, restart the shell
with `omarchy-restart-shell`. `omarchy-shell shell rescanPlugins` often keeps
the previous component.

Write a record by hand with:

```bash
omarchy-agent-usage-grok --write
omarchy-agent-usage-grok --force --write
```

`--force` ignores the session-scan cache. `--limits-only` reuses a scan up to
15 minutes old and still probes billing. `--write` stores `grok.json`. With
no flag the command prints the record.

<br />

## ✨ **What's included**

### **Collector**

- **Session tokens** from `~/.grok/sessions` turn completions, last 7 days. `GROK_HOME` overrides that directory.
- **Weekly credits** from `GET {base}/billing?format=credits`. The base is `GROK_CLI_CHAT_PROXY_BASE_URL` or `https://cli-chat-proxy.grok.com/v1`. That call does not send a prompt. If it fails, the collector uses the newest open reading in `~/.grok/logs/unified.jsonl`.
- **User timer** every 2 minutes (`extras/systemd/`), plus a path unit on `~/.grok/active_sessions.json`. Both run `omarchy-agent-usage-grok --write`.
- **Scan cache** of 20 seconds unless you pass `--force` or `--limits-only`.

### **Panel**

`plugin/sd.agents/` is **My Agents** (`sd.agents`), cloned from stock `omarchy.agents`. Details are in `plugin/sd.agents/README.md`.

- **Grok first**, then the other agents A–Z, then **Overall** when at least two have data. The pane opens on Grok.
- **Days under 10M** hidden. The day header is the average of the days that remain. A span longer than a week uses `M/D`.
- **Pool estimate** on each week or month meter (`≈ 868M/week`). Cursor's Other Models meter and Overall skip it. Once the meter has ticked twice a whole point apart, the estimate is the tokens between those ticks over the percents between them, so it stops jumping each time a whole-percent meter moves. Readings live in `~/.local/state/omarchy/agents/meter-ticks.json`.
- **Export for Open Usage** button at the bottom copies draft [Open Usage](https://github.com/stevederico/open-usage) reports to the clipboard: tokens, meter percents and token mix per meter. Nothing is sent anywhere. Scripts can get the same JSON with `qs ipc -p /usr/share/omarchy/shell call sd.agents exportReports`.
- **Monthly price** under Weekly Total. The line under the field is that price × 12/52, over the Saturday–Friday token total (`$75.00 this week · $0.058 / 1M`). Overall adds every priced plan, and `0` counts.
- **Grok mark** is `assets/grok.svg` (white) or `assets/grok-light.svg` on a light bar, drawn at 1.4× the other marks. `assets/grok.txt` is an unused braille transcription.
- **Cursor** has marks here and no collector. A `cursor.json` from elsewhere still gets a chip.

The panel's own refresh is `refreshIntervalSec` (default 900). That runs `omarchy-agent-usage-update` for every enabled agent. It is separate from the 2-minute Grok timer.

### **Not for an upstream PR**

- **`patches/`** is an old Grok-only delta. Trust `plugin/sd.agents/` when they disagree.
- **`extras/`** is the local timer, path unit, and login hook.

<br />

## 🔀 **Upstream PR**

`omarchy-agent-usage-update` runs every `omarchy-agent-usage-*` binary in
`$OMARCHY_PATH/bin`. The smallest Grok PR is the collector plus the two marks:

1. `bin/omarchy-agent-usage-grok`
2. `shell/plugins/agents/assets/grok.svg`
3. `shell/plugins/agents/assets/grok-light.svg`
4. A row in `shell/plugins/agents/README.md`

Leave `plugin/sd.agents/` and `extras/` out. The stock widget shows a Grok tab
once the collector writes `grok.json`. Do not copy this tree into an Omarchy
checkout until you are opening that PR.

<br />

## 📄 **License**

MIT. See [LICENSE](LICENSE).
