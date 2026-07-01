#!/usr/bin/env bash
set -euo pipefail

source tool/ci/foundation_models_sources.sh

output="$(mktemp "${TMPDIR:-/tmp}/genkit_foundation_models_native_tool_capture_test.XXXXXX")"
trap 'rm -f "$output"' EXIT

xcrun swiftc \
  -parse-as-library \
  "${foundation_models_sources[@]}" \
  tool/ci/test_native_tool_capture.swift \
  -o "$output"

"$output"
