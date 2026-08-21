#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

GROK_HOME="$TEST_HOME/.grok"
mkdir -p "$GROK_HOME/sessions/%2Fhome%2Fdev%2Fone/session-a" \
  "$GROK_HOME/sessions/%2Fhome%2Fdev%2Ftwo/session-b" \
  "$GROK_HOME/logs"

now=$(date +%s)

usage_line() {
  local prompt_id="$1" models="$2"
  jq -cn --argjson ts "$now" --arg id "$prompt_id" --argjson models "$models" \
    '{timestamp: $ts, method: "_x.ai/session/update", params: {update: {
      sessionUpdate: "turn_completed", prompt_id: $id, stop_reason: "end_turn",
      usage: {modelUsage: $models}}}}'
}

# Grok reports each completed turn on its own, with cache reads folded into
# inputTokens. The same prompt_id appears twice to stand in for a resumed
# transcript. A cancelled turn has no usage and is not a prompt.
{
  usage_line p1 '{"grok-4.5-build":{"inputTokens":100,"cachedReadTokens":60,"outputTokens":20,"reasoningTokens":5,"totalTokens":120}}'
  usage_line p1 '{"grok-4.5-build":{"inputTokens":100,"cachedReadTokens":60,"outputTokens":20,"reasoningTokens":5,"totalTokens":120}}'
  usage_line p2 '{"grok-4.5-build":{"inputTokens":80,"cachedReadTokens":50,"cacheCreationTokens":10,"outputTokens":10,"totalTokens":90}}'
  echo '{"timestamp":'"$now"',"method":"_x.ai/session/update","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"cancelled","stop_reason":"cancelled"}}}'
} >"$GROK_HOME/sessions/%2Fhome%2Fdev%2Fone/session-a/updates.jsonl"

# One turn answered by two models, plus a line the prefilter must skip.
{
  echo '{"timestamp":0,"method":"session/update","params":{"update":{"sessionUpdate":"agent_message_chunk","content":"noise"}}}'
  usage_line p3 '{"grok-4.5-build":{"inputTokens":200,"cachedReadTokens":150,"outputTokens":40,"totalTokens":240},"grok-4.5":{"inputTokens":100,"cachedReadTokens":0,"outputTokens":10,"totalTokens":110}}'
} >"$GROK_HOME/sessions/%2Fhome%2Fdev%2Ftwo/session-b/updates.jsonl"

credits_record() {
  local percent="$1" start="$2" end="$3" tier="${4:-SuperGrok Heavy}"
  jq -cn --argjson percent "$percent" --arg start "$start" --arg end "$end" --arg tier "$tier" \
    '{ts: "2026-01-01T00:00:00Z", src: "shell", lvl: "info",
      msg: "billing: fetched credits config",
      ctx: {config: ({currentPeriod: {type: "USAGE_PERIOD_TYPE_WEEKLY", start: $start, end: $end}}
                     + (if $percent < 0 then {} else {creditUsagePercent: $percent} end)),
            subscriptionTier: $tier}}'
}

write_credits_log() {
  credits_record "$@" >"$GROK_HOME/logs/unified.jsonl"
}

open_period_start=$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%S+00:00)
open_period_end=$(date -u -d '5 days' +%Y-%m-%dT%H:%M:%S+00:00)

# Port 9 is the discard port: the live credits call reaches nothing there,
# standing in for an xAI outage. Every run below needs a base URL of its own,
# or the collector would call the real endpoint.
run_collector() {
  HOME="$TEST_HOME" GROK_HOME="$GROK_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" \
    GROK_CLI_CHAT_PROXY_BASE_URL="${STUB_BASE:-http://127.0.0.1:9/v1}" \
    "$ROOT/bin/omarchy-agent-usage-grok" "$@"
}

cat >"$GROK_HOME/auth.json" <<EOF
{"https://auth.x.ai::test": {"key": "test-token", "expires_at": "$(date -u -d '5 hours' +%Y-%m-%dT%H:%M:%SZ)"}}
EOF

cat >"$TEST_HOME/stub.py" <<'EOF'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

body = sys.argv[1].encode()
port_file = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
  def do_GET(self):
    with open(port_file + ".path", "w") as handle:
      handle.write(self.path)
    self.send_response(200)
    self.send_header("Content-Type", "application/json")
    self.send_header("Content-Length", str(len(body)))
    self.end_headers()
    self.wfile.write(body)

  def log_message(self, *args):
    pass


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as handle:
  handle.write(str(server.server_port))
server.serve_forever()
EOF

STUB_PID=""
STUB_BASE=""
start_stub() {
  local port_file="$TEST_HOME/stub.port"
  rm -f "$port_file" "$port_file.path"
  python3 "$TEST_HOME/stub.py" "$1" "$port_file" &
  STUB_PID=$!
  for _ in $(seq 1 60); do
    [[ -s $port_file ]] && break
    sleep 0.1
  done
  [[ -s $port_file ]] || fail "Grok collector test could not start its stub credits endpoint" ""
  STUB_BASE="http://127.0.0.1:$(cat "$port_file")/v1"
}

stop_stub() {
  [[ -n $STUB_PID ]] && kill "$STUB_PID" 2>/dev/null
  wait "$STUB_PID" 2>/dev/null
  STUB_PID=""
  STUB_BASE=""
}

trap 'stop_stub; rm -rf "$TEST_HOME"' EXIT

write_credits_log 22.0 "$open_period_start" "$open_period_end"
result=$(run_collector --force)

# 120 + 90 from session-a, 350 from the two-model turn in session-b.
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "560" ]] ||
  fail "Grok collector sums each turn once" "$result"
pass "Grok collector sums each turn once"

[[ $(jq -r '.totalPrompts' <<<"$result") == "3" ]] ||
  fail "Grok collector counts one prompt per turn and ignores repeated prompt ids" "$result"
pass "Grok collector counts one prompt per turn and ignores repeated prompt ids"

[[ $(jq -r '.totalSessions' <<<"$result") == "2" ]] ||
  fail "Grok collector counts sessions by transcript" "$result"
pass "Grok collector counts sessions by transcript"

[[ $(jq -c '.modelUsage["grok-4.5-build"]' <<<"$result") == '{"inputTokens":110,"outputTokens":70,"cacheReadInputTokens":260,"cacheCreationInputTokens":10}' ]] ||
  fail "Grok collector does not double-count cache or reasoning tokens" "$result"
pass "Grok collector does not double-count cache or reasoning tokens"

[[ $(jq -c '.modelUsage["grok-4.5"]' <<<"$result") == '{"inputTokens":100,"outputTokens":10,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}' ]] ||
  fail "Grok collector splits a turn across the models that served it" "$result"
pass "Grok collector splits a turn across the models that served it"

contract='{"schemaVersion":1,"id":"grok","name":"Grok","ready":true,"hasLocalStats":true,"recentDays":7,"usageStatusText":""}'
[[ $(jq -c '{schemaVersion, id, name, ready, hasLocalStats, recentDays: (.recentDays | length), usageStatusText}' <<<"$result") == "$contract" ]] ||
  fail "Grok collector prints the display-ready record contract" "$result"
pass "Grok collector prints the display-ready record contract"

[[ $(jq -c '.limits' <<<"$result") == '[{"label":"Weekly (7-day)","percent":0.22,"resetsAt":"'"$open_period_end"'"}]' ]] &&
  [[ $(jq -r '.tierLabel' <<<"$result") == "SuperGrok Heavy" ]] ||
  fail "Grok collector reads the weekly credit allowance from the CLI log" "$result"
pass "Grok collector reads the weekly credit allowance from the CLI log"

# A cached percentage belongs to the period it was fetched in. Once that period
# has ended the figure is the wrong week's, so the meter has to disappear.
write_credits_log 22.0 "$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%S+00:00)" \
  "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S+00:00)"
expired=$(run_collector --force)

[[ $(jq -r '.limits | length' <<<"$expired") == "0" ]] ||
  fail "Grok collector drops a credit reading from a period that has ended" "$expired"
pass "Grok collector drops a credit reading from a period that has ended"

# Grok logs a config on every startup and not all of them carry a percentage,
# so the meter must come from the newest reading that has one.
{
  credits_record 20.0 "$open_period_start" "$open_period_end"
  credits_record -1 "$open_period_start" "$open_period_end"
} >"$GROK_HOME/logs/unified.jsonl"
walked_back=$(run_collector --force)

[[ $(jq -r '.limits[0].percent' <<<"$walked_back") == "0.2" ]] ||
  fail "Grok collector walks back to the newest usable credit reading" "$walked_back"
pass "Grok collector walks back to the newest usable credit reading"

# The live call must degrade to the log rather than lose the meter.
write_credits_log 22.0 "$open_period_start" "$open_period_end"
offline=$(run_collector --force)

[[ $(jq -r '.limits[0].percent' <<<"$offline") == "0.22" ]] &&
  [[ $(jq -r '.tierLabel' <<<"$offline") == "SuperGrok Heavy" ]] ||
  fail "Grok collector falls back to the log when the live credits call fails" "$offline"
pass "Grok collector falls back to the log when the live credits call fails"

# A 200 is not the same as an answer. A window with no percentage has to yield
# to the log rather than blank the meter.
start_stub "{\"config\":{\"currentPeriod\":{\"type\":\"USAGE_PERIOD_TYPE_WEEKLY\",\"start\":\"$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S+00:00)\",\"end\":\"$(date -u -d '6 days' +%Y-%m-%dT%H:%M:%S+00:00)\"},\"prepaidBalance\":{\"val\":0},\"onDemandCap\":{\"val\":0},\"onDemandUsed\":{\"val\":0},\"isUnifiedBillingUser\":true}}"
unusable=$(run_collector --force)
stop_stub

[[ $(jq -r '.limits[0].percent' <<<"$unusable") == "0.22" ]] ||
  fail "Grok collector falls back to the log when the live body carries no percentage" "$unusable"
pass "Grok collector falls back to the log when the live body carries no percentage"

# A live body that is usable has to win over the log's older number.
start_stub "{\"config\":{\"creditUsagePercent\":44.0,\"currentPeriod\":{\"type\":\"USAGE_PERIOD_TYPE_WEEKLY\",\"start\":\"$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S+00:00)\",\"end\":\"$(date -u -d '6 days' +%Y-%m-%dT%H:%M:%S+00:00)\"}}}"
live=$(run_collector --force)
live_path=$(cat "$TEST_HOME/stub.port.path")
stop_stub

[[ $(jq -r '.limits[0].percent' <<<"$live") == "0.44" ]] &&
  [[ $(jq -r '.tierLabel' <<<"$live") == "SuperGrok Heavy" ]] &&
  [[ $live_path == "/v1/billing?format=credits" ]] ||
  fail "Grok collector prefers a usable live reading over the log" "$live ($live_path)"
pass "Grok collector prefers a usable live reading over the log"

rm -f "$GROK_HOME/logs/unified.jsonl"
missing=$(run_collector --force)

[[ $(jq -r '.limits | length' <<<"$missing") == "0" ]] &&
  [[ $(jq -r '.totalPrompts' <<<"$missing") == "3" ]] &&
  [[ $(jq -r '.usageStatusText' <<<"$missing") == "Grok limits unavailable" ]] ||
  fail "Grok collector still reports tokens with no log to read limits from" "$missing"
pass "Grok collector still reports tokens with no log to read limits from"

# A turn from yesterday must not inflate today. local_day is easy to get
# wrong around UTC midnight — this machine's sessions stamp unix seconds.
mkdir -p "$GROK_HOME/sessions/%2Fhome%2Fdev%2Fthree/session-c"
yesterday=$(date -d 'yesterday 15:00:00' +%s)
yesterday_date=$(date -d 'yesterday 15:00:00' +%Y-%m-%d)
jq -cn --argjson ts "$yesterday" \
  '{timestamp: $ts, method: "_x.ai/session/update", params: {update: {
    sessionUpdate: "turn_completed", prompt_id: "old", stop_reason: "end_turn",
    usage: {modelUsage: {"grok-4.5-build":{"inputTokens":30,"outputTokens":10,"totalTokens":40}}}}}}' \
  >"$GROK_HOME/sessions/%2Fhome%2Fdev%2Fthree/session-c/updates.jsonl"
dated=$(run_collector --force)

[[ $(jq -r '.todayPrompts' <<<"$dated") == "3" ]] &&
  [[ $(jq -r '.todayTotalTokens' <<<"$dated") == "560" ]] &&
  [[ $(jq -r --arg day "$yesterday_date" '.recentDays[] | select(.date == $day) | .messageCount' <<<"$dated") == "40" ]] ||
  fail "Grok collector files a turn on the local day it happened" "$dated"
pass "Grok collector files a turn on the local day it happened"

# Interrupting a prompt and running it again reuses the prompt id. The
# cancelled record carries no usage key, so only the completed retry counts.
mkdir -p "$GROK_HOME/sessions/%2Fhome%2Fdev%2Ffour/session-d"
{
  echo '{"timestamp":'"$now"',"method":"_x.ai/session/update","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"p4","stop_reason":"cancelled"}}}'
  usage_line p4 '{"grok-4.5-build":{"inputTokens":30,"cachedReadTokens":0,"outputTokens":10,"totalTokens":40}}'
} >"$GROK_HOME/sessions/%2Fhome%2Fdev%2Ffour/session-d/updates.jsonl"
retried=$(run_collector --force)

[[ $(jq -r '.todayTotalTokens' <<<"$retried") == "600" ]] &&
  [[ $(jq -r '.todayPrompts' <<<"$retried") == "4" ]] ||
  fail "Grok collector counts a retried turn whose cancelled attempt shared its id" "$retried"
pass "Grok collector counts a retried turn whose cancelled attempt shared its id"

# Parent turn_completed already includes subagent spend, so a forked
# session must not add another copy.
child_dir="$GROK_HOME/sessions/%2Fhome%2Fdev%2Fone/session-fork"
mkdir -p "$child_dir"
jq -n --arg today "$(date +%Y-%m-%d)" \
  '{info:{id:"session-fork"}, session_kind:"subagent_fork", parent_session_id:"session-a", created_at:($today+"T12:00:00Z")}' \
  >"$child_dir/summary.json"
usage_line child1 '{"grok-4.5-build":{"inputTokens":5000,"outputTokens":500,"totalTokens":5500}}' \
  >"$child_dir/updates.jsonl"
forked=$(run_collector --force)

[[ $(jq -r '.todayTotalTokens' <<<"$forked") == "600" ]] ||
  fail "Grok collector ignores subagent_fork sessions" "$forked"
pass "Grok collector ignores subagent_fork sessions"

# --limits-only reuses a seconds-old scan; --force rereads the files.
write_credits_log 22.0 "$open_period_start" "$open_period_end"
rm -rf "$TEST_HOME/.cache"
baseline=$(run_collector --force)
[[ $(jq -r '.todayPrompts' <<<"$baseline") == "4" ]] ||
  fail "Grok collector --force sees the fixture turns" "$baseline"

usage_line p5 '{"grok-4.5-build":{"inputTokens":20,"outputTokens":2,"totalTokens":22}}' \
  >>"$GROK_HOME/sessions/%2Fhome%2Fdev%2Fone/session-a/updates.jsonl"

cached=$(run_collector --limits-only)
[[ $(jq -r '.todayPrompts' <<<"$cached") == "4" ]] ||
  fail "Grok collector --limits-only reuses a fresh scan cache" "$cached"
pass "Grok collector --limits-only reuses a fresh scan cache"

forced=$(run_collector --force)
[[ $(jq -r '.todayPrompts' <<<"$forced") == "5" ]] ||
  fail "Grok collector --force rescans past the cache" "$forced"
pass "Grok collector --force rescans past the cache"

# An unwritable cache must not take the record down.
UNWRITABLE_HOME=$(mktemp -d)
trap 'stop_stub; rm -rf "$TEST_HOME" "$UNWRITABLE_HOME"' EXIT
mkdir -p "$UNWRITABLE_HOME/.grok/sessions/%2Ftmp%2Fproj/session-e"
cp "$GROK_HOME/sessions/%2Fhome%2Fdev%2Ftwo/session-b/updates.jsonl" \
  "$UNWRITABLE_HOME/.grok/sessions/%2Ftmp%2Fproj/session-e/updates.jsonl"
touch "$UNWRITABLE_HOME/not-a-dir"
unwritable=$(HOME="$UNWRITABLE_HOME" GROK_HOME="$UNWRITABLE_HOME/.grok" \
  XDG_CACHE_HOME="$UNWRITABLE_HOME/not-a-dir" \
  GROK_CLI_CHAT_PROXY_BASE_URL="http://127.0.0.1:9/v1" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -r '.todayTotalTokens' <<<"$unwritable") == "350" ]] ||
  fail "Grok collector still prints a record when the cache is unwritable" "$unwritable"
pass "Grok collector still prints a record when the cache is unwritable"

# GROK_HOME wins over ~/.grok under HOME.
OTHER_HOME=$(mktemp -d)
trap 'stop_stub; rm -rf "$TEST_HOME" "$UNWRITABLE_HOME" "$OTHER_HOME"' EXIT
other_dir="$OTHER_HOME/sessions/%2Ftmp%2Fother/session-other"
mkdir -p "$other_dir"
usage_line other1 '{"grok-4.20":{"inputTokens":10,"outputTokens":4,"totalTokens":14}}' \
  >"$other_dir/updates.jsonl"
other=$(HOME="$TEST_HOME" GROK_HOME="$OTHER_HOME" XDG_CACHE_HOME="$OTHER_HOME/.cache" \
  GROK_CLI_CHAT_PROXY_BASE_URL="http://127.0.0.1:9/v1" \
  "$ROOT/bin/omarchy-agent-usage-grok" --force)
[[ $(jq -c '.modelUsage["grok-4.20"]' <<<"$other") == '{"inputTokens":10,"outputTokens":4,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}' ]] ||
  fail "Grok collector honors GROK_HOME" "$other"
[[ $(jq -r '.usageStatusText' <<<"$other") == "Waiting for auth" ]] ||
  fail "Grok collector reports a missing login" "$other"
pass "Grok collector honors GROK_HOME and reports a missing login"

# No sessions and no log is a machine that has never signed in: a full record
# the update runner can write, with nothing in it for the panel to show.
empty=$(GROK_HOME="$TEST_HOME/.grok-empty" HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache-empty" \
  GROK_CLI_CHAT_PROXY_BASE_URL="http://127.0.0.1:9/v1" "$ROOT/bin/omarchy-agent-usage-grok")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.totalPrompts | tostring)' <<<"$empty") == "grok:false:0" ]] ||
  fail "Grok collector prints a valid record with nothing installed" "$empty"
pass "Grok collector prints a valid record with nothing installed"
