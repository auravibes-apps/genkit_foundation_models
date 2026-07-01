#!/usr/bin/env bash
set -euo pipefail

xcrun swiftc \
  -parse-as-library \
  tool/ci/foundation_models_typecheck_stubs.swift \
  darwin/genkit_foundation_models/Sources/genkit_foundation_models/FoundationModelsStreamHandler.swift \
  darwin/genkit_foundation_models/Sources/genkit_foundation_models/NativeErrorMapper.swift \
  darwin/genkit_foundation_models/Sources/genkit_foundation_models/NativeGenerationOptionsMapper.swift \
  darwin/genkit_foundation_models/Sources/genkit_foundation_models/NativeJSONSchemaConverter.swift \
  darwin/genkit_foundation_models/Sources/genkit_foundation_models/NativeToolRuntime.swift \
  darwin/genkit_foundation_models/Sources/genkit_foundation_models/NativeTranscriptMapper.swift \
  darwin/genkit_foundation_models/Sources/genkit_foundation_models/NativeGenerationRunner.swift \
  darwin/genkit_foundation_models/Sources/genkit_foundation_models/FoundationModelsHostApiImpl.swift \
  tool/ci/test_native_tool_capture.swift \
  -o /tmp/genkit_foundation_models_native_tool_capture_test

/tmp/genkit_foundation_models_native_tool_capture_test
