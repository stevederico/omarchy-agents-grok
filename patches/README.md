# Plugin patches

Grok-only edits on top of stock `omarchy.agents`. The live plugin in
`plugin/sd.agents/` is the applied result, including the local rename to
`sd.agents` / "My Agents". These patches do **not** include that rename.

| Patch | Needed for | Notes |
|---|---|---|
| `Main.qml.patch` | Nothing in the patch itself | The file on disk is one local comment. The live `Main.qml` is ahead of it: Grok sorts first, and Overall is appended last. Do not apply this patch as the current behavior. |
| `Panel.qml.patch` | Weekly-limit button / Auto toggle / braille mark | Behind the live panel. Missing Overall, the 10M day floor, the active-day average, and month dates. |
| `manifest.json.patch` | Settings keys used by the panel UI | Only if you take `Panel.qml.patch`. |

Stock policy is that adding an agent is adding a collector plus optional
`assets/<id>.svg`. The panel is supposed to stay a display. The extra
controls fight that a bit, so they are a second, more opinionated commit —
not the minimum PR.

If the plugin and these patches drift, trust `plugin/sd.agents/`.
