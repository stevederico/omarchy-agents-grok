# Plugin patches

These are the Grok-only edits on top of stock `omarchy.agents`.
They do **not** include the local rename to `sd.agents`.

| Patch | Needed for | Notes |
|---|---|---|
| `Panel.qml.patch` | Weekly-limit button / Auto toggle / braille mark | Optional for a first PR. Stock already renders any `grok.json` the collector writes. |
| `manifest.json.patch` | Settings keys used by the panel UI | Only if you take `Panel.qml.patch`. |
| `Main.qml.patch` | Nothing functional | One local comment. Drop it. |

Stock policy is that adding an agent is adding a collector plus optional `assets/<id>.svg`. The panel is supposed to stay a display. The TUI scrape controls fight that a bit, so they are the second, more opinionated commit — not the minimum PR.

The live clone at `~/.config/omarchy/plugins/sd.agents` also renamed the plugin id. That rename is **not** in these patches and should not go upstream.
