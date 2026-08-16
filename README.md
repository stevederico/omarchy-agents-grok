# omarchy-agents-grok

Grok support for Omarchy's menubar **Agents** panel, pulled out of the
`sd.agents` clone so it can become a PR.

Stock Omarchy already treats a new agent as a collector that prints one JSON
record. The panel watches `~/.local/state/omarchy/agents/usage/` and draws
whatever appears there. Claude, Codex, and Fireworks ship; Grok did not.

## What this is

| Path | What it is |
|---|---|
| `bin/omarchy-agent-usage-grok` | Collector. Scans `~/.grok/sessions/**/updates.jsonl` and optionally scrapes `/usage` from a throwaway TUI. |
| `assets/grok.svg`, `assets/grok-light.svg` | Marks for the panel hero. |
| `assets/grok.txt` | Braille mark used by the local panel when the SVG is too faint. |
| `patches/` | Grok-only edits to stock `omarchy.agents`. |
| `extras/` | Local timer, path unit, and login hook. Not first-party Omarchy. |
| `tests/` | Parser, token split, and session-scan checks. |

The live clone at `~/.config/omarchy/plugins/sd.agents` is **not** copied here.
That tree is almost all stock plugin plus the patches in `patches/`.

## Smallest Omarchy PR

`omarchy-agent-usage-update` runs every `omarchy-agent-usage-*` binary in
`$OMARCHY_PATH/bin`. Adding Grok is:

1. `bin/omarchy-agent-usage-grok`
2. `shell/plugins/agents/assets/grok.svg`
3. `shell/plugins/agents/assets/grok-light.svg`
4. A row in `shell/plugins/agents/README.md`

No plugin rename. No panel controls. The stock widget will show a Grok tab
as soon as the collector writes `grok.json`.

Weekly SuperGrok limits have no public API, so this collector opens a
headless `tmux` Grok, sends `/usage`, and parses the modal. `--limits-only`
(the flag the stock updater already passes) refreshes that meter when the
cache is stale. That is the part to call out in the PR: it works, and it is
also a screen scrape.

## Optional second change

`patches/Panel.qml.patch` adds a Grok-only footer: **Update weekly limit**,
an Auto toggle, and the braille mark. Stock policy is that the panel is
strictly a display, so keep this out of the first PR unless reviewers want
it.

Do not send the local rename to `sd.agents` / "My Agents".

## Local machine (already installed)

The collector this desktop runs is `~/.local/lib/omarchy/omarchy-agent-usage-grok`.
After edits here:

```bash
make test
make install-user
```

That installs the collector and the user units. It does not replace
`sd.agents`. Refresh a record with:

```bash
omarchy-agent-usage-grok --write
omarchy-agent-usage-grok --force --scrape-tui --write
```

## Opening the PR

Omarchy lives at https://github.com/basecamp/omarchy. Develop against a
clone, not `/usr/share/omarchy`:

```bash
gh repo fork basecamp/omarchy --clone
cd omarchy
cp ../omarchy-agents-grok/bin/omarchy-agent-usage-grok bin/
cp ../omarchy-agents-grok/assets/grok.svg ../omarchy-agents-grok/assets/grok-light.svg \
  shell/plugins/agents/assets/
```

Then add the README table row, run `./test/all`, and open the PR.

Suggested first-PR title: **Add a Grok collector to the Agents panel**.
