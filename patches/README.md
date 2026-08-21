# Plugin patches

Grok-only edits on top of stock `omarchy.agents`. The live plugin in
`plugin/sd.agents/` is the applied result, including the local rename to
`sd.agents` / "My Agents". These patches do **not** include that rename.

| Patch | Needed for | Notes |
|---|---|---|
| `Panel.qml.patch` | Weekly-limit button / Auto toggle / braille mark | Optional for a first PR. Stock already renders any `grok.json` the collector writes. |
| `manifest.json.patch` | Settings keys used by the panel UI | Only if you take `Panel.qml.patch`. |
| `Main.qml.patch` | Nothing functional | One local comment. Drop it. |

Stock policy is that adding an agent is adding a collector plus optional
`assets/<id>.svg`. The panel is supposed to stay a display. The extra
controls fight that a bit, so they are a second, more opinionated commit —
not the minimum PR.

If the plugin and these patches drift, trust `plugin/sd.agents/`.
