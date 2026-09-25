import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "sd.agents"
  ipcTarget: "sd.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  // Prefer Grok when the panel opens; fall back to the first ready provider.
  property string selectedProviderId: "grok"
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var models: modelRows(provider)
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || ""),
      estimate: ""
    }
  }

  // Cursor's Other Models pool is optional. Grok 4.6 Fast still runs on
  // Cursor Models, so a full Other Models meter must not light the bar icon.
  function limitIsOtherModels(w) {
    return String((w && w.title) || "").toLowerCase().indexOf("other models") >= 0
  }

  // Claude's 5-hour session meter stays off Claude Code and Overall.
  // The weekly meter stays. Other agents keep their session meters.
  function limitIsClaudeSession(p, entry) {
    if (!p || !entry) return false
    var id = String(p.providerId || "")
    if (id !== "claude" && id !== "overall") return false
    var text = (String(entry.title || "") + " " + String(entry.label || "")).toLowerCase()
    if (text.indexOf("session") < 0) return false
    if (id === "overall" && text.indexOf("claude") < 0) return false
    return true
  }

  function localDateKey(ms) {
    var d = new Date(ms)
    if (isNaN(d.getTime())) return ""
    return d.getFullYear()
      + "-" + String(d.getMonth() + 1).padStart(2, "0")
      + "-" + String(d.getDate()).padStart(2, "0")
  }

  // Daily buckets cannot see a 5-hour session. A week or a billing month can.
  function windowSpanFor(entry) {
    var label = String((entry && (entry.title || entry.label)) || "")
    var span = windowSpanMs(label)
    if (span >= 24 * 3600 * 1000) return span
    if (span > 0) return 0
    var reset = new Date(String(entry && entry.resetsAt || "")).getTime()
    if (!isFinite(reset)) return 0
    if (reset - root.nowMs > 8 * 24 * 3600 * 1000) return 30 * 24 * 3600 * 1000
    return 0
  }

  function tokensInWindow(p, startMs) {
    var key = localDateKey(startMs)
    if (key === "") return -1
    var days = p && p.recentDays ? p.recentDays : []
    var sum = 0
    var any = false
    for (var i = 0; i < days.length; i++) {
      var day = days[i] || {}
      var date = String(day.date || "")
      if (date !== "" && date >= key) {
        sum += Number(day.messageCount || 0)
        any = true
      }
    }
    return any ? sum : -1
  }

  // One key per meter per window. Resets jitter by a second between probes,
  // so the hour is what identifies the window.
  function meterKey(p, entry) {
    var reset = new Date(String(entry && entry.resetsAt || "")).getTime()
    if (!p || !isFinite(reset)) return ""
    return p.providerId + "|" + String(entry.title || entry.label || "") + "|" + Math.round(reset / 3600000)
  }

  // Whole-percent meters make spent / percent jump 25% at 4% every time the
  // meter ticks. A tick is a fixed point on the meter, so the tokens between
  // the first and the latest tick over the percents between them is the cap,
  // whether the meter rounds or floors, and whatever the window's first day
  // bucket held before the window opened.
  property var meterTicks: ({})
  property bool meterTicksLoaded: false
  readonly property string meterTicksPath: usage.usageDir.replace(/\/usage$/, "") + "/meter-ticks.json"

  FileView {
    id: meterTicksFile
    path: root.meterTicksPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try { root.meterTicks = JSON.parse(text() || "{}") || {} } catch (e) { root.meterTicks = {} }
      root.meterTicksLoaded = true
      root.recordMeterTicks()
    }
    onLoadFailed: {
      root.meterTicksLoaded = true
      root.recordMeterTicks()
    }
  }

  onProvidersChanged: Qt.callLater(root.recordMeterTicks)

  // A tick sits halfway between the last reading before the percent moved
  // and the first one after. A meter or token count going backwards starts
  // the window over.
  function recordMeterTicks() {
    if (!meterTicksLoaded) return
    var now = Date.now()
    var old = meterTicks || {}
    var next = {}
    var changed = false
    for (var k in old) {
      if (Number(k.split("|").pop()) * 3600000 > now) next[k] = old[k]
      else changed = true
    }
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      if (!p || p.providerId === "overall") continue
      var list = p.limits || []
      for (var j = 0; j < list.length; j++) {
        var entry = list[j] || {}
        var span = windowSpanFor(entry)
        if (span < 24 * 3600 * 1000) continue
        var percent = Number(entry.percent)
        var key = meterKey(p, entry)
        if (!(percent >= 0) || key === "") continue
        var spent = tokensInWindow(p, new Date(String(entry.resetsAt)).getTime() - span)
        if (!(spent >= 0)) continue
        var m = next[key] || {}
        var last = m.last
        if (last && (percent < last.p || spent < last.t)) {
          m = {}
          last = null
        }
        if (last && percent > last.p) {
          var tick = { t: (last.t + spent) / 2, p: percent }
          if (!m.first) m.first = tick
          else m.latest = tick
        }
        if (!last || last.p !== percent || last.t !== spent) changed = true
        m.last = { t: spent, p: percent }
        next[key] = m
      }
    }
    if (!changed) return
    meterTicks = next
    meterTicksFile.setText(JSON.stringify(next) + "\n")
  }

  // Tokens between ticks over the fraction between them, once the meter has
  // moved a whole point since the first tick. Before that, spent in the open
  // window divided by the fraction used. Every week or month meter gets its
  // own estimate except Other Models, whose tokens are a different optional
  // pool. Overall mixes plans, so it skips.
  function estimateCap(p, entry) {
    if (!p || p.providerId === "overall") return ""
    var span = windowSpanFor(entry)
    if (span < 24 * 3600 * 1000) return ""
    var suffix = span >= 20 * 24 * 3600 * 1000 ? "/month" : "/week"
    var m = meterTicks[meterKey(p, entry)]
    if (m && m.first && m.latest && m.latest.p - m.first.p >= 0.0099) {
      var ticked = (m.latest.t - m.first.t) / (m.latest.p - m.first.p)
      if (ticked > 0) return "≈ " + usage.formatTokenCount(ticked) + suffix
    }
    var percent = Number(entry.percent)
    if (!(percent >= 0.02)) return ""
    var reset = new Date(String(entry.resetsAt || "")).getTime()
    if (!isFinite(reset)) return ""
    var spent = tokensInWindow(p, reset - span)
    if (!(spent > 0)) return ""
    var cap = spent / Math.min(percent, 1)
    return "≈ " + usage.formatTokenCount(cap) + suffix
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (!(percent >= 0)) continue
      if (limitIsClaudeSession(p, entry)) continue
      var window = limitWindow(entry.label, percent, entry.resetsAt, entry.title)
      if (!limitIsOtherModels(window))
        window.estimate = estimateCap(p, entry)
      out.push(window)
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (limitIsOtherModels(windows[i])) continue
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "") return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dateKey(d) {
    return d.getFullYear()
      + "-" + String(d.getMonth() + 1).padStart(2, "0")
      + "-" + String(d.getDate()).padStart(2, "0")
  }

  // Work week is Saturday noon through Friday noon, local time.
  // Before this Saturday's noon, that window is still last week's.
  function workWeek(nowMs) {
    var now = new Date(nowMs)
    var back = (now.getDay() + 1) % 7
    var saturday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - back, 12, 0, 0, 0)
    if (now.getTime() < saturday.getTime())
      saturday = new Date(saturday.getFullYear(), saturday.getMonth(), saturday.getDate() - 7, 12, 0, 0, 0)
    var friday = new Date(saturday.getFullYear(), saturday.getMonth(), saturday.getDate() + 6, 12, 0, 0, 0)
    return { start: saturday, end: friday }
  }

  // Day rows are whole dates, so this adds each calendar day from that
  // Saturday through that Friday. Saturday morning and Friday afternoon
  // stay in, because the chart has no hour split.
  function weekTokenTotal(p) {
    if (!p) return 0
    var week = workWeek(root.nowMs)
    var now = new Date(root.nowMs)
    var until = now.getTime() < week.end.getTime() ? now : new Date(week.end.getTime() - 1)
    var startKey = dateKey(week.start)
    var untilKey = dateKey(until)
    var days = p.recentDays || []
    var sum = 0
    for (var i = 0; i < days.length; i++) {
      var date = String(days[i] && days[i].date || "")
      if (date >= startKey && date <= untilKey)
        sum += Number(days[i].messageCount || 0)
    }
    return sum
  }

  // Plan prices live on the bar entry as monthlyUsd, keyed by provider id.
  // A missing key is unset. Zero is a real price (a plan included elsewhere).
  function monthlyPrice(id) {
    var map = settings && settings.monthlyUsd
    if (!map || map[id] === undefined || map[id] === null || map[id] === "") return NaN
    var n = Number(map[id])
    return isFinite(n) && n >= 0 ? n : NaN
  }

  function formatPriceInput(value) {
    var n = Math.round(Number(value) * 100) / 100
    if (!isFinite(n)) return ""
    if (Math.abs(n - Math.round(n)) < 0.001) return String(Math.round(n))
    return n.toFixed(2)
  }

  // Flat monthly fee spread across the panel's Saturday–Friday token total.
  function rateText(monthly, tokens) {
    if (!isFinite(monthly)) return ""
    var week = monthly * 12 / 52
    var text = formatMoney(week) + " this week"
    if (!(tokens > 0)) return text
    var perM = week / (tokens / 1000000)
    if (!(perM > 0)) return text + " · $0 / 1M"
    if (perM < 0.01) return text + " · $" + perM.toFixed(4) + " / 1M"
    if (perM < 1) return text + " · $" + perM.toFixed(3) + " / 1M"
    return text + " · $" + perM.toFixed(2) + " / 1M"
  }

  function costSummary(p) {
    if (!p) return { show: false, monthly: NaN, tokens: 0, editable: false }
    if (p.providerId !== "overall") {
      return {
        show: true,
        monthly: monthlyPrice(p.providerId),
        tokens: weekTokenTotal(p),
        editable: true
      }
    }
    var monthly = 0
    var tokens = 0
    var any = false
    for (var i = 0; i < providers.length; i++) {
      var item = providers[i]
      if (!item || item.providerId === "overall") continue
      var price = monthlyPrice(item.providerId)
      if (!isFinite(price)) continue
      any = true
      monthly += price
      tokens += weekTokenTotal(item)
    }
    return { show: any, monthly: any ? monthly : NaN, tokens: tokens, editable: false }
  }

  function saveMonthlyPrice(id, raw) {
    if (!id || id === "overall") return
    var trimmed = String(raw || "").replace(/[$,\s]/g, "")
    var copy = JSON.parse(JSON.stringify(settings || {}))
    var map = copy.monthlyUsd
    if (!map || typeof map !== "object" || Array.isArray(map)) {
      map = {}
      copy.monthlyUsd = map
    }
    if (trimmed === "") {
      delete map[id]
    } else {
      var n = Number(trimmed)
      if (!isFinite(n) || n < 0) return
      map[id] = Math.round(n * 100) / 100
    }
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName || "sd.agents", copy)
  }

  // A day under 10M is idle. It stays out of the chart and out of the average.
  readonly property real activeDayFloor: 10000000

  function activeDays(p) {
    var days = p ? (p.recentDays || []) : []
    var out = []
    for (var i = 0; i < days.length; i++) {
      if (Number(days[i] && days[i].messageCount || 0) >= root.activeDayFloor) out.push(days[i])
    }
    return out
  }

  function dayAverage(days) {
    if (!days || days.length === 0) return 0
    var sum = 0
    for (var i = 0; i < days.length; i++) sum += Number(days[i].messageCount || 0)
    return sum / days.length
  }

  function monthSpan(p) {
    return activeDays(p).length > 7
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    // A week fits weekday names. A billing month repeats them, so show M/D.
    if (monthSpan(root.provider)) {
      var parsed = new Date(String(date || "") + "T00:00:00")
      if (isNaN(parsed.getTime())) return String(date || "")
      return (parsed.getMonth() + 1) + "/" + parsed.getDate()
    }
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(days) {
    var peak = 0
    var list = days || []
    for (var i = 0; i < list.length; i++) peak = Math.max(peak, Number(list[i].messageCount || 0))
    return peak
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    var cap = p && p.providerId === "overall" ? 8 : 4
    return rows.slice(0, cap)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p || p.providerId === "overall") return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.selectProvider(root.providerIndex + 1)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // Taller than the control panels on purpose: this one is a dashboard, and
    // the whole point is reading limits and history without scrolling.
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
      }
      blocked: priceField.activeFocus

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: provider mark · name · plan ----------
          PanelHero {
            id: hero
            visible: !!root.provider
            width: parent.width
            title: root.provider ? root.provider.providerName : ""
            meta: root.heroMeta(root.provider)
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                id: heroMark
                readonly property bool grok: !!root.provider && root.provider.providerId === "grok"
                readonly property bool overall: !!root.provider && root.provider.providerId === "overall"
                readonly property real markSize: Style.font.display * (grok ? 1.4 : 1)
                property var candidates: root.iconCandidatesForProvider(root.provider, root.surface)
                property string candidatesKey: candidates.join("\n")
                property int candidateIndex: 0
                onCandidatesKeyChanged: candidateIndex = 0

                implicitWidth: markSize
                implicitHeight: markSize
                width: implicitWidth
                height: implicitHeight

                Text {
                  visible: heroMark.overall
                  anchors.centerIn: parent
                  text: "Σ"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: heroMark.markSize
                }

                Image {
                  id: heroMarkImage
                  visible: !heroMark.overall
                  anchors.fill: parent
                  source: !heroMark.overall && heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
                  sourceSize.width: heroMark.markSize * 2
                  sourceSize.height: heroMark.markSize * 2
                  fillMode: Image.PreserveAspectFit
                  onStatusChanged: if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
                    Qt.callLater(function() { heroMark.candidateIndex++ })
                }

                Text {
                  anchors.centerIn: parent
                  visible: !heroMark.overall && heroMarkImage.status !== Image.Ready
                  text: button.text
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: heroMark.markSize
                }
              }
            }
          }

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Provider switch ----------
          Row {
            id: providerSwitch
            visible: root.providers.length > 1
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: root.providers.length > 0
              ? (width - spacing * (root.providers.length - 1)) / root.providers.length
              : 0

            Repeater {
              model: root.providers

              Button {
                required property var modelData
                required property int index

                width: providerSwitch.cellWidth
                text: modelData.providerName
                selected: index === root.providerIndex
                hasCursor: root.cursorActive && index === root.providerIndex
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.cursorActive = true
                  root.selectProvider(index)
                }
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          // ---------- Status ----------
          BorderSurface {
            visible: !!root.provider && String(root.provider.usageStatusText || "") !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider ? String(root.provider.authHelpText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Balance / limits ----------
          PanelSeparator {
            visible: balanceSection.visible || limitsSection.visible
            foreground: root.foreground
          }

          Column {
            id: balanceSection
            visible: !!root.balance
            width: parent.width
            spacing: Style.space(10)

            // The meter shows what is left, not what is used: a prepaid
            // account drains toward empty rather than filling toward a cap.
            readonly property real ratio: root.balance && root.balance.funded > 0
              ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
              : -1

            PanelSectionHeader {
              width: parent.width
              text: "BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                text: "Prepaid credits"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                color: root.balanceAlarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              visible: balanceSection.ratio >= 0
              width: parent.width
              value: balanceSection.ratio
              alarming: root.balanceAlarming
            }

            Text {
              visible: text !== ""
              width: parent.width
              text: root.balanceDetailText(root.balance)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: limitsSection
            visible: root.limits.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LIMITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.limits

              LimitRow {
                required property var modelData
                width: limitsSection.width
                window: modelData
              }
            }
          }

          // ---------- Usage ----------
          PanelSeparator {
            visible: usageSection.visible
            foreground: root.foreground
          }

          Column {
            id: usageSection
            visible: usageSection.days.length > 0 || usageSection.weekTotal > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property var days: root.activeDays(root.provider)
            readonly property real average: root.dayAverage(days)
            readonly property real peak: Math.max(1, root.weekPeak(days))
            readonly property real weekTotal: root.weekTokenTotal(root.provider)

            Item {
              visible: usageSection.days.length > 0
              width: parent.width
              implicitHeight: Math.max(dayHeader.implicitHeight, dayAvg.implicitHeight)

              PanelSectionHeader {
                id: dayHeader
                text: "TOKENS BY DAY"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.right: dayAvg.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
              }

              Text {
                id: dayAvg
                text: "avg " + usage.formatTokenCount(usageSection.average)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Repeater {
              model: usageSection.days

              DayRow {
                required property var modelData
                required property int index

                width: usageSection.width
                day: modelData
                ratio: Number(modelData.messageCount || 0) / usageSection.peak
                // By date, not by position: the Claude stats-cache fallback can
                // hand us a window that stops short of today.
                today: String(modelData.date || "") === root.todayDate()
              }
            }

            Item {
              id: weekTotalRow
              visible: usageSection.weekTotal > 0 || usageSection.days.length > 0
              width: parent.width
              implicitHeight: Math.max(weekLabel.implicitHeight, weekValue.implicitHeight) + Style.spacing.sm

              Text {
                id: weekLabel
                text: "Weekly Total"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
                anchors.left: parent.left
                anchors.right: weekValue.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: weekValue
                text: usage.formatTokenCount(usageSection.weekTotal)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                horizontalAlignment: Text.AlignRight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }

              MouseArea {
                id: weekHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }

              PanelToolTip {
                visible: weekHover.containsMouse
                text: "Whole days from Saturday through Friday"
                fontFamily: root.fontFamily
              }
            }

            Column {
              id: costBlock
              visible: costBlock.summary.editable || costBlock.summary.show
              width: parent.width
              spacing: Style.space(4)

              readonly property var summary: root.costSummary(root.provider)

              Item {
                width: parent.width
                implicitHeight: Math.max(costLabel.implicitHeight, priceEntry.implicitHeight, plansValue.implicitHeight)

                Text {
                  id: costLabel
                  text: costBlock.summary.editable ? "Monthly" : "Plans"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                  anchors.left: parent.left
                  anchors.right: priceEntry.visible ? priceEntry.left : plansValue.left
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                  id: priceEntry
                  visible: costBlock.summary.editable
                  spacing: Style.space(4)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: "$"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  TextField {
                    id: priceField
                    width: Style.space(76)
                    placeholderText: "0"
                    horizontalAlignment: TextInput.AlignRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    foreground: root.foreground
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(6)
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    anchors.verticalCenter: parent.verticalCenter

                    property string priceEcho: {
                      var id = root.provider ? root.provider.providerId : ""
                      var price = root.monthlyPrice(id)
                      return id + "\n" + (isFinite(price) ? root.formatPriceInput(price) : "")
                    }

                    function applyEcho() {
                      var cut = priceEcho.indexOf("\n")
                      text = cut < 0 ? "" : priceEcho.slice(cut + 1)
                    }

                    onPriceEchoChanged: if (!activeFocus) applyEcho()
                    onActiveFocusChanged: if (!activeFocus) applyEcho()
                    Component.onCompleted: applyEcho()

                    onEditingFinished: root.saveMonthlyPrice(root.provider ? root.provider.providerId : "", text)
                    onAccepted: {
                      root.saveMonthlyPrice(root.provider ? root.provider.providerId : "", text)
                      keyCatcher.forceActiveFocus()
                    }
                    Keys.onEscapePressed: function(event) {
                      applyEcho()
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }

                  Text {
                    text: "/mo"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  id: plansValue
                  visible: !costBlock.summary.editable && isFinite(costBlock.summary.monthly)
                  text: isFinite(costBlock.summary.monthly) ? root.formatMoney(costBlock.summary.monthly) + " /mo" : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Text {
                visible: isFinite(costBlock.summary.monthly)
                width: parent.width
                text: root.rateText(costBlock.summary.monthly, costBlock.summary.tokens)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
              }
            }
          }

          // ---------- Models ----------
          PanelSeparator {
            visible: modelSection.visible
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: root.models.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY MODEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.models

              ModelRow {
                required property var modelData
                width: modelSection.width
                row: modelData
                // Scaled to the heaviest model, so the top row is always full —
                // the same scale-to-peak the weekly chart uses for its busiest day.
                share: modelData.total / Math.max(1, root.models[0].total)
              }
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        // A model-scoped window is titled after its model, and those names run
        // long enough to reach the percentage, so the title gives way first.
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        text: limitRow.window && limitRow.window.percent >= 0
          ? Math.round(limitRow.window.percent * 100) + "%"
          : "—"
        color: limitRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      alarming: limitRow.alarming
    }

    Text {
      id: resetText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        var reset = remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
        var estimate = limitRow.window ? String(limitRow.window.estimate || "") : ""
        if (reset !== "" && estimate !== "") return reset + " · " + estimate
        return reset !== "" ? reset : estimate
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

  }

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the week reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a table: the share bar fills the row behind the label
  // instead of stacking under it, which keeps the whole dashboard on one screen.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }
}
