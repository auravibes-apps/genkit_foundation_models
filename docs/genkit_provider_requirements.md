# Genkit Provider Requirements

Checked against Genkit docs on 2026-05-28.

This package should expose Apple Foundation Models to Genkit as a model provider plugin. The provider is the adapter layer between Genkit's standard model API and Apple's native `FoundationModels` Swift API.

## Provider responsibilities

A Genkit provider needs to:

- Register a unique provider name, for example `foundationModels` or `appleFoundationModels`.
- List available model actions for discovery in Genkit tools and dev UI.
- Resolve model actions lazily by action type and model name.
- Declare each model's metadata, including label, supported features, versions, and config schema.
- Convert Genkit requests into native provider requests.
- Call the native model API.
- Convert native responses back into Genkit `ModelResponse` values.
- Convert native errors into actionable Genkit/Dart errors.

## Dart plugin shape

Genkit Dart plugin authoring uses a `GenkitPlugin` subclass:

```dart
import 'package:genkit/genkit.dart';

class FoundationModelsPlugin extends GenkitPlugin {
  @override
  String get name => 'foundationModels';

  @override
  Future<List<ActionMetadata>> list() async {
    return [
      ActionMetadata(
        type: ActionType.model,
        name: 'foundationModels/system-language-model',
        opt: FoundationModelOptions.$schema,
      ),
    ];
  }

  @override
  Action? resolve(String type, String name) {
    if (type != ActionType.model.name) return null;
    if (name != 'foundationModels/system-language-model') return null;

    return Model(
      name: name,
      fn: (request, context) async {
        // 1. Convert Genkit ModelRequest to native request DTO.
        // 2. Call Pigeon HostApi implemented in Swift.
        // 3. Convert native response DTO to ModelResponse.
        return ModelResponse(
          message: Message(
            role: Role.model,
            content: [TextPart(text: '')],
          ),
        );
      },
    );
  }
}
```

## Model metadata

The Apple model action should advertise only capabilities the native integration supports.

Initial metadata target:

- `multiturn: true` if conversation history is mapped to a `LanguageModelSession` transcript or equivalent session flow.
- `systemRole: true` if Genkit system messages are mapped to Foundation Models instructions.
- `tools: true` once Genkit tool declarations can be mapped to Swift `Tool` implementations and tool results can be returned.
- `media: false` for initial text-only scope.
- `output: ['text']` for plain text generation, then add structured output only when Dart schemas are mapped to Swift `Generable` types or JSON output.

## Request mapping

Map Genkit request fields into a platform-neutral Pigeon DTO before crossing into Swift.

Genkit input to preserve:

- Model name, version, and provider options.
- `messages`: role plus ordered content parts.
- `system` messages or system instruction content.
- Text parts.
- Tool request and tool response parts.
- Common generation config such as temperature, top-p, max output tokens, stop sequences, and candidate count where supported.
- Streaming flag and stream callback behavior if the Genkit Dart API exposes streaming for the model action.

Unsupported input should fail early with a clear error. Do not silently drop media, schema, or unsupported config values.

## Response mapping

Native responses should map back to Genkit response parts:

- Plain generated text becomes `TextPart` in a model `Message`.
- Native tool calls become Genkit tool request parts.
- Native tool results become Genkit tool response parts when returning tool-side messages.
- Finish reason should map to Genkit stop, length, blocked, error, or unknown equivalents where available.
- Usage metrics should be included only if Foundation Models exposes reliable token/accounting data through the native API.

## Tool-calling loop

Genkit can orchestrate tool-calling with compatible models. The provider must support the model-level protocol pieces:

- Accept tool declarations from Genkit.
- Expose tool names, descriptions, and input schemas to the native model.
- Return model tool requests to Genkit without executing them inside Swift unless the design explicitly keeps execution native.
- Accept tool response messages from Genkit and continue generation.
- Preserve request IDs or stable tool-call identifiers if the native API provides them.

For this package, prefer Dart-side tool execution first. Swift should only run Apple Foundation Models and report tool requests. This keeps Genkit's existing tool loop in control and avoids duplicating tool registry logic in Swift.

## Streaming

If streaming is implemented, provider code needs two outputs:

- Incremental chunks sent through the Genkit stream callback.
- Final accumulated `ModelResponse` returned when the native stream completes.

Chunks can contain text deltas, tool requests, tool responses, or role/index changes. Genkit examples show tool request chunks as model content and tool response chunks as tool content.

## Error handling

Error handling should distinguish:

- Apple Intelligence or Foundation Models unavailable on this device or OS.
- User-disabled Apple Intelligence or missing language/model assets.
- Unsupported request features.
- Native generation failures.
- Tool argument decoding failures.
- Platform-channel/Pigeon transport failures.

Errors crossing Pigeon should use structured error codes and messages so Dart can surface useful diagnostics.

## Verification checklist

- `list()` returns the model action used by examples.
- `resolve()` returns a model only for the provider's model names.
- Text prompt generates a Genkit `ModelResponse` with `Role.model` and `TextPart`.
- Multi-turn input preserves message order and roles.
- Unsupported media input fails clearly.
- Tool declaration can produce a tool request part.
- Tool response can continue generation.
- Native unavailable states produce deterministic Dart exceptions.

## Sources

- Genkit Dart plugin authoring docs via Context7: `GenkitPlugin`, `list`, `resolve`, `Model`, `ActionMetadata`.
- Genkit Go/Python plugin authoring docs via Context7: provider metadata, model supports, request/response conversion responsibilities.
- Genkit tool-calling docs via Context7: `toolRequest` and `toolResponse` parts in generated streams.
