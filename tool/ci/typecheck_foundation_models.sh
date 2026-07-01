#!/usr/bin/env bash
set -euo pipefail

source tool/ci/foundation_models_sources.sh

platform="${1:-}"

case "$platform" in
  macos)
    sdk="macosx"
    target="arm64-apple-macos10.15"
    ;;
  ios)
    sdk="iphoneos"
    target="arm64-apple-ios13.0"
    ;;
  *)
    echo "Usage: $0 macos|ios" >&2
    exit 64
    ;;
esac

sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
foundation_models="$sdk_path/System/Library/Frameworks/FoundationModels.framework"

if [ ! -d "$foundation_models" ]; then
  echo "FoundationModels.framework not available in $sdk SDK; skipping native SDK typecheck."
  exit 0
fi

xcrun swiftc -typecheck \
  -sdk "$sdk_path" \
  -target "$target" \
  -parse-as-library \
  "${foundation_models_sources[@]}"
