#!/usr/bin/env python3
import json
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "bin" / "omarchy-agent-usage-grok"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def load_collector():
  return SourceFileLoader("omarchy_agent_usage_grok", str(COLLECTOR)).load_module()


grok = load_collector()


class ParseTuiTest(unittest.TestCase):
  def test_minimal_usage_pane(self):
    parsed = grok.parse_tui_dump((FIXTURES / "usage-pane-minimal.txt").read_text())
    self.assertIsNotNone(parsed)
    self.assertEqual(parsed["tierLabel"], "SuperGrok Heavy")
    self.assertEqual(len(parsed["limits"]), 1)
    limit = parsed["limits"][0]
    self.assertEqual(limit["title"], "Weekly")
    self.assertEqual(limit["percent"], 0.4)
    self.assertIn("2026-08-20T12:20:00", limit["resetsAt"])

  def test_captured_tmux_pane(self):
    parsed = grok.parse_tui_dump((FIXTURES / "usage-pane.txt").read_text())
    self.assertIsNotNone(parsed)
    self.assertEqual(parsed["tierLabel"], "SuperGrok Heavy")
    self.assertEqual(parsed["limits"][0]["percent"], 0.4)

  def test_unrelated_text_is_ignored(self):
    self.assertIsNone(grok.parse_tui_dump("no meters here"))


class UsageMathTest(unittest.TestCase):
  def test_cached_reads_are_split_out_of_input(self):
    split = grok.usage_from_turn({
      "inputTokens": 110,
      "outputTokens": 20,
      "cachedReadTokens": 10,
    })
    self.assertEqual(split, (100, 20, 10, 0))


class SessionScanTest(unittest.TestCase):
  def test_turn_completed_lines_are_counted(self):
    stats = grok.empty_stats()
    recent = {row["date"]: row for row in stats["recentDays"]}
    grok.scan_updates_file(
      FIXTURES / "session-home" / "sessions" / "demo" / "updates.jsonl",
      stats,
      today="2026-08-15",
      recent=recent,
      sessions=set(),
      today_sessions=set(),
      active_days=set(),
    )
    self.assertEqual(stats["totalPrompts"], 1)
    self.assertEqual(stats["todayTotalTokens"], 130)
    self.assertEqual(stats["todayTokensByModel"]["grok-4.6-build"], 130)


class RecordContractTest(unittest.TestCase):
  def test_record_uses_the_agents_panel_ids(self):
    record = grok.build_record(grok.empty_stats(), signed_in=True)
    self.assertEqual(record["id"], "grok")
    self.assertEqual(record["name"], "Grok")
    self.assertTrue(record["ready"])
    json.dumps(record)


if __name__ == "__main__":
  unittest.main()
