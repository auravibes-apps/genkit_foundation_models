# Genkit Foundation Models Tooling Plan

## Goal

Use Apple Foundation Models as a structured model adapter for Genkit, not as a
text protocol that asks the model to print tool calls.

Success looks like this:

- Genkit tools become Apple native `Tool`s or captured native tool calls.
- Apple tool calls become Genkit `ToolRequestPart`s with stable refs.
- Genkit tool results become Apple transcript `toolOutput` entries.
- Assistant text never contains tool protocol markup.
- Streaming treats Apple output as cumulative snapshots, not token deltas.

## Best Pattern

Build a typed adapter boundary:

```text
Genkit request
  -> FoundationModels transcript + native tools
  -> Apple LanguageModelSession
  -> transcript/tool-call events
  -> Genkit ModelResponse / ModelResponseChunk
```

The provider should translate between two structured protocols. It should not
invent a third protocol in prompt text.

## Evidence

Projects and docs reviewed point to the same design:

- Apple Foundation Models exposes `Tool`, `Transcript.ToolCalls`,
  `Transcript.ToolOutput`, and `Transcript.Reasoning` as structured concepts.
- Apple's Python Foundation Models SDK keeps transcript/tools structured and
  streams cumulative text snapshots.
- `FoundationModel` examples use native `Tool` and inspect `session.transcript`;
  no text parsing.
- `AppleFoundationMCPTool` converts dynamic JSON schemas into native
  `GenerationSchema` and receives arguments as `GeneratedContent`.
- `react-native-apple-llm` bridges native tool calls across a JS boundary using
  events and continuations, not markup.
- `AnyLanguageModel` uses FoundationModels-shaped transcript/tool abstractions
  as the public adapter shape.
- Rudrank's OpenAI-compatible bridge captures native FoundationModels tool
  calls and returns them to the outer orchestrator.
- `SwiftAgent` keeps typed transcript entries for prompt, response, tool calls,
  tool results, and reasoning.

## Target Architecture

### 1. Request Mapping

Map Genkit messages into FoundationModels transcript entries:

| Genkit part | FoundationModels shape |
| --- | --- |
| System/developer text | `instructions` |
| User text/media | `prompt` |
| Model text | `response` |
| Model tool request | `toolCalls` |
| Tool response | `toolOutput` |

Do not serialize tool calls or tool outputs into assistant prose.

### 2. Tool Call Capture

Prefer capture tools over prompt tags.

For each Genkit tool, create a native Swift `Tool` wrapper:

- `name`: Genkit tool name.
- `description`: Genkit tool description.
- `parameters`: converted JSON schema when available.
- `Arguments`: `GeneratedContent` for dynamic schemas.
- `call(arguments:)`: record `toolName`, generated `ref`, and JSON arguments,
  then stop generation with a private sentinel error.

The Swift layer sends captured calls back to Dart as structured native parts.
Dart maps them to `ToolRequestPart`. Genkit remains the tool executor.

This avoids blocking Swift on Dart callbacks and matches Genkit's existing tool
loop.

### 3. Tool Result Injection

On the next Genkit request, map prior `ToolResponsePart`s into native
`toolOutput` transcript entries:

- preserve `ref` / call id;
- preserve `name`;
- preserve structured JSON when possible;
- stringify only at the Apple boundary if the native API requires text output.

Do not block another call to the same tool name. Only reject exact repeated
completed refs.

### 4. Streaming

Apple streams cumulative snapshots. Genkit expects chunks.

Use prefix-delta conversion:

```text
snapshot: "hel"   -> chunk "hel"
snapshot: "hello" -> chunk "lo"
```

When tools are enabled, default to one of these safe modes:

1. Capture tool calls and do not stream provisional text until tool-call outcome
   is known.
2. Stream text only when no tools were captured.

Do not parse streamed assistant text for tool calls. If native APIs cannot expose
streamed tool calls, return them in the final response.

### 5. Response Mapping

Map Apple result/transcript entries back to Genkit:

- `response` text -> `TextPart`.
- `toolCalls` -> `ToolRequestPart`.
- `toolOutput` only appears in history, not model output.
- `reasoning` -> metadata/custom field only if Genkit has a stable consumer.

Assistant-visible text should contain only assistant prose.

### 6. Prompting

Keep prompts semantic, not protocol-heavy.

Good:

```text
Use the provided tools when they help answer the user. If prior tool results are
present, use them to continue or answer normally.
```

Bad:

```text
Print a strict JSON tool request and nothing else.
```

Prompt-format tool calls can remain as a compatibility fallback, but they should
not be the primary path.

## Migration Plan

### Phase 1: Stabilize Current Adapter

- Keep existing text parser only as leak prevention.
- Document it as best-effort compatibility, not native tool calling.
- Keep cumulative snapshot-to-delta handling.
- Keep tests for malformed/fenced JSON so protocol text is not exposed.

### Phase 2: Add Native Capture Tools

- Extend Pigeon/native model request with structured tool declarations:
  `name`, `description`, JSON schema.
- Add Swift dynamic `Tool` wrappers.
- Capture `GeneratedContent.jsonString` arguments.
- Return captured calls as native structured tool-request parts.
- Add tests proving no prompt tags are needed.

### Phase 3: Add Transcript Mapping

- Map Genkit history into native transcript entries.
- Preserve tool refs and names across turns.
- Inject prior tool outputs structurally.
- Remove prompt text that describes fake tool protocol.

### Phase 4: Improve Structured Data

- Convert Genkit JSON schema to `GenerationSchema`.
- Preserve JSON tool outputs where possible.
- Stringify only when the Apple API requires `PromptRepresentable` text.

### Phase 5: Reasoning Metadata

- Expose reasoning only when available in FoundationModels runtime.
- Keep it outside `response.text`.
- Prefer metadata/custom fields until Genkit has a first-class reasoning type.

## Tests To Add

- Native captured tool call maps to one `ToolRequestPart`.
- Multiple captured tool calls preserve order and refs.
- Same tool name can be called again with a different ref.
- Repeated completed ref is rejected.
- Tool response history maps to native `toolOutput`, not prompt text.
- Streaming snapshots produce deltas.
- Tool-enabled streaming does not leak provisional protocol text.
- JSON fallback strips leaked tool-call JSON if model emits it.

## What To Delete Later

After native capture tools and transcript mapping are working:

- tool-call XML prompt rules;
- fenced JSON tool-call fallback as primary behavior;
- app-side parsing/stripping workarounds;
- Swift prompt logic that explains tool protocol formatting.

Keep only a small defensive parser if real Apple output can still contain leaked
legacy protocol text from old app sessions.

## Decision

Use the Rudrank/AFM bridge pattern:

> Native FoundationModels tools capture tool calls; Genkit executes tools;
> provider maps structured transcript entries both directions.

This is the smallest architecture that stops visible protocol leaks while still
letting Genkit own orchestration.
