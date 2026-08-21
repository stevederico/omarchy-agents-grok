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


class UsageMathTest(unittest.TestCase):
  def test_cached_reads_are_split_out_of_input(self):
    split = grok.split_tokens({
      "inputTokens": 110,
      "outputTokens": 20,
      "cachedReadTokens": 10,
    })
    self.assertEqual(split, (100, 20, 10, 0))


class SessionScanTest(unittest.TestCase):
  def test_turn_completed_lines_are_counted(self):
    usage = grok.SessionUsage(today="2026-08-15")
    grok.scan_updates_file(
      FIXTURES / "session-home" / "sessions" / "demo" / "updates.jsonl",
      usage,
    )
    stats = usage.stats()
    self.assertEqual(stats["totalPrompts"], 1)
    self.assertEqual(stats["todayTotalTokens"], 130)
    self.assertEqual(stats["todayTokensByModel"]["grok-4.6-build"], 130)


class RecordContractTest(unittest.TestCase):
  def test_record_uses_the_agents_panel_ids(self):
    empty = grok.build_record(
      grok.empty_stats(),
      {"tierLabel": "", "limits": []},
      signed_in=True,
    )
    self.assertEqual(empty["id"], "grok")
    self.assertEqual(empty["name"], "Grok")
    self.assertFalse(empty["ready"])
    json.dumps(empty)

    stats = grok.empty_stats()
    stats["totalPrompts"] = 1
    record = grok.build_record(
      stats,
      {"tierLabel": "SuperGrok Heavy", "limits": [{"label": "Weekly (7-day)", "percent": 0.2}]},
      signed_in=True,
    )
    self.assertTrue(record["ready"])
    self.assertEqual(record["tierLabel"], "SuperGrok Heavy")


if __name__ == "__main__":
  unittest.main()
