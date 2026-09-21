# Plugin patches

Grok-only edits on top of stock `omarchy.agents`. The live plugin in
`plugin/sd.agents/` is the applied result, including the local rename to
`sd.agents` / "My Agents". These patches do **not** include that rename.

| Patch | Needed for | Notes |
|---|---|---|
| `Main.qml.patch` | Nothing in the patch itself | The file on disk is one local comment. The live `Main.qml` is ahead of it: Grok sorts first, and Overall is appended last. Do not apply this patch as the current behavior. |
| `Panel.qml.patch` | Weekly-limit button, Auto toggle, braille mark | Historical. The live panel has no scrape controls. Grok is the SVG at 1.4× the other marks. The weekly meter comes from the billing endpoint. |
| `manifest.json.patch` | Settings keys used by the panel UI | Only if you take `Panel.qml.patch`. |

Stock policy is that adding an agent is a collector plus an optional
`assets/<id>.svg`. These patches still describe scrape controls and a braille
mark the live panel no longer has. Do not apply them as current behavior.

If the plugin and these patches drift, trust `plugin/sd.agents/`.
