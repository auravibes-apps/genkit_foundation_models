# genkit_foundation_models

[![pub package](https://img.shields.io/pub/v/genkit_foundation_models.svg)](https://pub.dev/packages/genkit_foundation_models)
[![CI](https://github.com/auravibes-apps/genkit_foundation_models/actions/workflows/ci.yml/badge.svg)](https://github.com/auravibes-apps/genkit_foundation_models/actions/workflows/ci.yml)
[![Publish](https://github.com/auravibes-apps/genkit_foundation_models/actions/workflows/publish.yml/badge.svg)](https://github.com/auravibes-apps/genkit_foundation_models/actions/workflows/publish.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/github-auravibes--apps%2Fgenkit__foundation__models-24292f.svg)](https://github.com/auravibes-apps/genkit_foundation_models)

`genkit_foundation_models` is a Genkit Dart provider for Apple's on-device
Foundation Models framework.

It is designed for Flutter apps that want local-first text generation on iOS and
macOS through the system Apple Intelligence model, with Genkit model refs,
streaming responses, multi-turn conversations, and Genkit-owned tool loops.

## Features

- Genkit `Model` provider: `foundationModels/system-language-model`
- on-device text generation through Apple's `FoundationModels` framework
- iOS and macOS shared Darwin plugin implementation
- streaming text responses through Pigeon event channels
- multi-turn Genkit conversations
- Genkit tool request emission through native Foundation Models `Tool` capture
- structured native reasoning/debug metadata when the runtime exposes it
- typed availability and generation errors for app-friendly UI
- example Flutter chat app for macOS/iOS

## Requirements

- Flutter app target, not a pure Dart CLI app
- Dart SDK `^3.11.0`
- Flutter `>=3.41.0` for Swift Package Manager plugin support
- `genkit: ^0.14.1`
- Xcode 26.5 SDK or newer with `FoundationModels.framework`
- iOS 13.0 or macOS 10.15 minimum deployment target for app compatibility
- iOS 26.0 or macOS 26.0 at runtime for Foundation Models generation
- device or Mac eligible for Apple Intelligence
- Apple Intelligence enabled and model assets ready on the device

If the system model is not available, `FoundationModels.isAvailable()` returns
`false` or generation throws `FoundationModelsException` with a typed
`FoundationModelsErrorCode`.

## Install

Add the package to a Flutter app:

```yaml
dependencies:
  genkit: ^0.14.1
  genkit_foundation_models:
    git:
      url: https://github.com/auravibes-apps/genkit_foundation_models.git
```

For local development in this repository, the example uses a path dependency.

## Platform Setup

The plugin can be included in apps with lower deployment targets, but Apple's
Foundation Models APIs only run on iOS 26.0 and macOS 26.0 or newer. On older OS
versions, `isAvailable()` returns `false` and generation throws a typed
`FoundationModelsException`.

The native Swift code is guarded with `#available(iOS 26.0, macOS 26.0, *)`, so
apps can compile for older deployment targets while runtime generation stays
gated.

### Swift Package Manager

Flutter is migrating iOS and macOS native dependencies to Swift Package Manager.
This plugin includes a SwiftPM package at
`darwin/genkit_foundation_models/Package.swift`.

Enable Flutter SwiftPM integration with:

```bash
flutter config --enable-swift-package-manager
```

Swift Package Manager support is still being adopted across Flutter projects, so
the CocoaPods podspec remains available as a fallback.

### CocoaPods Fallback

The package still ships `darwin/genkit_foundation_models.podspec` for Flutter
projects that have not migrated to Swift Package Manager. For macOS CocoaPods
builds, set the app Podfile and Xcode deployment target to at least 10.15:

```ruby
platform :osx, '10.15'
```

For iOS CocoaPods builds, use at least 13.0:

```ruby
platform :ios, '13.0'
```

The plugin uses a shared Darwin source layout and registers the same Swift code
for iOS and macOS.

## Quickstart

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_foundation_models/genkit_foundation_models.dart';

Future<void> main() async {
  final ai = Genkit(
    plugins: [foundationModels],
    model: modelRef(FoundationModelsPlugin.defaultModelName),
  );

  try {
    final response = await ai.generate(
      prompt: 'Say hello in one sentence.',
      config: {
        'temperature': 0.2,
        'maxOutputTokens': 128,
      },
    );

    print(response.text);
  } finally {
    await ai.shutdown();
  }
}
```

## Availability Check

Use the public availability facade before showing generation UI:

```dart
final available = await FoundationModels.isAvailable();
```

Generation errors are mapped to typed Dart exceptions:

```dart
try {
  final response = await ai.generate(prompt: 'Hello');
  print(response.text);
} on FoundationModelsException catch (error) {
  print(error.userMessage);
}
```

Common codes include:

- `appleIntelligenceDisabled`
- `deviceNotEligible`
- `modelNotReady`
- `unavailable`
- `blocked`
- `ignoredToolRequest`

## Streaming

```dart
final stream = ai.generateStream(
  model: modelRef(FoundationModelsPlugin.defaultModelName),
  prompt: 'Count from 1 to 5.',
  config: {'maxOutputTokens': 128},
);

await for (final chunk in stream) {
  if (chunk.text.isNotEmpty) {
    print(chunk.text);
  }
}

final response = await stream.onResult;
print('Final: ${response.text}');
```

When tools are active, the provider uses a conservative final-response stream
path so provisional native output does not leak tool protocol text into visible
chunks.

## Tool Calling

The provider maps Genkit tools into native Foundation Models `Tool` wrappers.
Swift captures the native tool call arguments and returns them to Dart as Genkit
`ToolRequestPart`s. Genkit still owns tool execution; Swift does not run app
tools directly.

Fenced JSON tool-call output is parsed only as a defensive fallback. Native
Foundation Models tools are the supported path; prompt-printed tool calls are
not part of Apple Foundation Models.

## Reasoning And Debug Metadata

Assistant prose stays in `response.text`. Reasoning is never appended to visible
text and the package does not prompt the model to print `Thought:` blocks.

The private native bridge can carry structured reasoning/debug data as Genkit
`ReasoningPart`s, part `metadata`/`custom`, response `custom`/`raw`, and stream
chunk `custom` when the Foundation Models runtime exposes those values. Apps
that want to display this should render it in a debug view, separate from the
assistant answer.

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_foundation_models/genkit_foundation_models.dart';

Future<void> main() async {
  final ai = Genkit(
    plugins: [foundationModels],
    model: modelRef(FoundationModelsPlugin.defaultModelName),
  );

  final currentTime = Tool<Map<String, dynamic>?, Map<String, String>>(
    name: 'current_time',
    description: 'Returns the current local date and time.',
    fn: (_, _) async {
      final now = DateTime.now();
      return {
        'currentTime': now.toIso8601String(),
        'timeZone': now.timeZoneName,
      };
    },
  );

  try {
    final response = await ai.generate(
      prompt: 'Use the current_time tool, then answer normally.',
      tools: [currentTime],
      maxTurns: 4,
    );

    print(response.text);
  } finally {
    await ai.shutdown();
  }
}
```

Safety behavior:

- undeclared tool names are rejected before Genkit executes them
- repeated requests for an already completed tool ref are ignored
- tool-call protocol text is stripped from visible assistant text
- fallback JSON shapes such as `{"toolRequests":[...]}` are supported only for
  compatibility and leak prevention

Tool-loop behavior:

- by default, tools are omitted immediately after a tool response so the model
  produces final prose from the tool output
- set `config: {'foundationModelsToolLoopMode': 'chained'}` to keep tools
  available after tool responses for multi-step agent exploration
- after a native generation failure on a tool-response turn, the provider retries
  once without tools so the model can answer from the tool output

For agent use, set an explicit `maxTurns` and expose the smallest useful tool
set. Side-effect tools should still enforce app-level approval or confirmation.

## Multi-turn Conversations

Preserve `response.messages` and append the next user message:

```dart
var messages = <Message>[];

final first = await ai.generate(
  messages: [
    Message(role: Role.user, content: [TextPart(text: 'My name is Aura.')]),
  ],
);

messages = first.messages;

final second = await ai.generate(
  messages: [
    ...messages,
    Message(role: Role.user, content: [TextPart(text: 'What is my name?')]),
  ],
);

print(second.text);
```

## Supported Config

The provider currently maps these Genkit config keys to
`FoundationModels.GenerationOptions`:

- `temperature` -> `GenerationOptions.temperature`
- `maxOutputTokens` -> `GenerationOptions.maximumResponseTokens`
- `topK` -> `GenerationOptions.SamplingMode.random(top:)`
- `topP` -> `GenerationOptions.SamplingMode.random(probabilityThreshold:)`

Unsupported config values are ignored unless they conflict with a currently
unsupported Genkit feature.

## Unsupported Features

These Genkit features are not supported yet:

- media input
- document context (`docs`)
- structured/constrained output
- `toolChoice`
- embeddings
- native Swift execution of Dart tool functions

Structured output is a likely future feature because Foundation Models includes
native structured generation APIs, but mapping arbitrary Dart/Genkit schemas to
Swift generation schemas still needs a dedicated bridge.

## Example App

Run the included Flutter chat example:

```bash
cd example
flutter run -d macos
```

The checked-in example uses Flutter Swift Package Manager integration instead of
CocoaPods. If Flutter asks to migrate the example, run with SwiftPM enabled:

```bash
flutter config --enable-swift-package-manager
```

If the example directory has not been generated for platforms yet:

```bash
cd example
flutter create . --platforms=ios,macos
flutter run -d macos
```

The example shows:

- chat-style conversation UI
- availability checking
- streaming responses
- tool call timeline entries
- exposed-tool and turn debug entries
- optional `singlePhase` tool-loop toggle
- typed error messages for Apple Intelligence availability states

## Development

Regenerate Pigeon bindings after editing `pigeons/foundation_models_api.dart`:

```bash
dart run pigeon --input pigeons/foundation_models_api.dart
```

Run checks:

```bash
flutter analyze
flutter test
(cd example && flutter test)
(cd example && flutter build macos --debug)
```

Native Swift changes require a full rebuild/relaunch of the app. Hot reload does
not reload plugin Swift code.

## Repository

https://github.com/auravibes-apps/genkit_foundation_models
