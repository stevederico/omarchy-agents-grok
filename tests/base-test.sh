#!/bin/bash

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source tests/base-test.sh from a shell test; do not run it directly" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  local description="$1"
  local detail="${2:-}"

  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

require_command() {
  local command="$1"

  command -v "$command" >/dev/null || fail "required command is available: $command"
}
