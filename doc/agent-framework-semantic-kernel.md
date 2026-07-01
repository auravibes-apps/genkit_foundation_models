# Semantic Kernel Tool Invocation Notes

Research timestamp: 2026-06-30T12:16:07Z.

Upstream checked:

- `microsoft/semantic-kernel`, cloned to
  `/var/folders/pt/yhlb769j4j1frcvj3mk_fy240000gp/T/opencode/agent-frameworks/semantic-kernel`.
- Microsoft Learn planner page, updated 2026-05-26, original article date
  2023-07-12.

## Short Version

Semantic Kernel no longer treats prompt-rendered tool calls as the main path.
Current SK uses provider-native function/tool calling where available, then runs
a guarded host loop that executes `FunctionCallContent` and appends
`FunctionResultContent` back into chat history.

When native function calling is unavailable or disabled, SK does not provide a
modern generic prompt-parser fallback. The old Stepwise and Handlebars planners
that asked the model to choose functions through prompts are deprecated and
removed from current .NET, Python, and Java packages. The remaining planner
helpers can render function manuals, including JSON-schema-like manuals, but
they are internal/legacy support rather than the recommended execution path.

For this package, do not copy SK's old prompt planners. Prefer FoundationModels
native tool capture. If a text fallback is unavoidable, keep it explicit,
off-by-default, and smaller than SK's old planner surface.

## Prompt Structure

SK's current function-calling path does not put tool schema text in the chat
prompt. It attaches tools through connector request fields:

- Python `kernel_function_metadata_to_function_call_format` renders each kernel
  function as `{ type: "function", function: { name, description, parameters } }`.
- The `parameters` object is JSON Schema shaped: `{ type: "object", properties,
  required }`.
- Function names use SK's fully qualified function name, usually
  `PluginName-FunctionName` or connector-specific equivalent.
- .NET connectors convert `KernelFunctionMetadata` to connector-native function
  shapes, preserving parameter schema and descriptions.

Legacy planner support rendered a function manual instead:

- `GetFunctionsManualAsync` returns a text manual built from function metadata.
- `GetJsonSchemaFunctionsManualAsync` returns serialized JSON schema function
  views.
- Function selection can be narrowed by excluded plugins/functions, included
  functions, or semantic memory search.

That manual path is not a robust replacement for native tool calls because the
model must emit parseable text and the host must trust a text protocol.

## Tool Schema Rendering

Current SK schema rules worth copying:

- Include only parameters marked for function choice exposure.
- Preserve each parameter's schema, not only its type name.
- Include `required` names separately from `properties`.
- Add default values to parameter descriptions where the connector supports it.
- Keep tool names stable and reversible to plugin/function names.

Avoid copying:

- Planner manuals as the primary tool schema format.
- XML/text protocols that ask the assistant to print tool calls.
- Large planner prompt templates. They are removed from current SK packages.

## Execution Loop

The modern SK loop is simple:

1. Build request with chat history and tool schemas.
2. Ask model.
3. If response has no tool calls, return assistant response.
4. Add assistant tool-call message to chat history.
5. For every tool call, validate name and arguments.
6. Invoke the kernel function.
7. Add one tool-result message per tool call.
8. Repeat until the model stops calling tools or attempt limit is reached.

.NET connector examples use a high cap of 128 auto-invoke attempts, plus some
connector-specific in-flight protection. Python defaults to 5 auto-invoke
attempts. Both exist to prevent runaway loops.

SK also supports manual mode:

- `autoInvoke: false` exposes `FunctionCallContent` to the caller.
- The caller can inspect, approve, execute, or reject the call.
- This is the closest match to Genkit's tool loop and to a Flutter/Dart adapter
boundary.

## Function Result Injection

SK injects tool results as structured chat content, not assistant prose:

- Assistant tool calls are represented as `FunctionCallContent` items.
- Tool results are represented as `FunctionResultContent` with the original call
  id, function name, plugin name, and result.
- Python serializes tool-result chat messages with role `tool`, `tool_call_id`,
  and string content for OpenAI-style connectors.
- .NET connectors add a response for every requested tool call because providers
  reject incomplete tool-call/result pairs.

Important behavior: function results are appended back into chat history before
the next model request. The next model request can then produce either another
tool call or final text.

## Error Handling

SK reports recoverable tool problems back to the model as tool results:

- Unknown function: add tool result saying the requested tool name is not part of
  supplied tools.
- Malformed arguments: add tool result saying arguments must be JSON.
- Missing or unexpected arguments: add tool result naming the mismatch.
- Tool invocation exception: add tool result like `Error: Exception while
  invoking function. ...` or Python's equivalent error string.

SK throws early for host configuration errors:

- Auto-invoke requested without a kernel.
- Explicit allowed function missing from the kernel when auto-invoke is enabled.

This split is useful: model-correctable errors become tool results; developer
misconfiguration fails before the model sees fake tools.

## Termination

SK terminates when any of these happens:

- Model response has no tool calls.
- Auto-invoke is disabled, so tool calls are returned to caller.
- Maximum auto-invoke attempts is reached.
- A function invocation filter sets terminate.
- Cancellation or connector error throws.

On filter termination, SK returns the latest tool result rather than continuing
the model loop. It also has helpers to merge multiple function results into one
tool message for terminated streaming paths.

## Planner Status

Microsoft's planner docs now say function calling replaced prompt-based planners
as the primary planning path. The Learn page explicitly says Stepwise and
Handlebars planners are deprecated and removed from .NET, Python, and Java, and
recommends function calling for new agents.

Source matches that guidance:

- Current repo has only internal planner metadata/manual helpers in .NET core.
- `docs/PLANNERS.md` is a stub pointing to Microsoft Learn.
- No current Python planner package was found in the cloned source.

## Recommendations For This Package

Use this shape:

```text
Genkit tools
  -> FoundationModels native Tool wrappers
  -> capture structured tool calls
  -> return Genkit ToolRequestPart
  -> Genkit executes tools
  -> inject prior ToolResponsePart as native toolOutput
  -> continue model session
```

Concrete rules:

- Keep native FoundationModels tools as the default and preferred path.
- Use a manual/capture mode, not Swift-side auto execution. Genkit should remain
  the tool executor.
- Preserve call ids/refs across tool call and tool output.
- Return one tool output per tool call, including error outputs.
- Treat malformed arguments, unknown tool names, and thrown tool exceptions as
  structured tool results when the model can correct them.
- Fail early for adapter misconfiguration, such as tool capture requested without
  tool definitions.
- Add a small loop cap if this package ever owns a loop. Prefer Python's smaller
  default style, not .NET's 128, unless Genkit already caps retries upstream.
- Do not implement Stepwise/Handlebars-style planners.
- Do not ask the assistant to print JSON/XML tool calls unless native tools are
  impossible and the feature is explicitly labeled best-effort.

If text fallback is required, use the smallest possible protocol:

```text
Available tools are JSON schemas below.
Return either final text or exactly one JSON object:
{"tool":"name","arguments":{...}}
```

Then require strict JSON parsing, allowlisted tool names, schema validation,
one-call-at-a-time execution, and a low attempt cap. This is worse than native
tool capture, but bounded.

## Source Pointers

- Python schema rendering:
  `python/semantic_kernel/connectors/ai/function_calling_utils.py`.
- Python auto invoke and error injection:
  `python/semantic_kernel/kernel.py`.
- Python result serialization:
  `python/semantic_kernel/contents/function_result_content.py` and
  `python/semantic_kernel/contents/chat_message_content.py`.
- Python default max attempts:
  `python/semantic_kernel/connectors/ai/function_choice_behavior.py`.
- .NET function choice behavior:
  `dotnet/src/SemanticKernel.Abstractions/AI/FunctionChoiceBehaviors/FunctionChoiceBehavior.cs`.
- .NET tool-call content:
  `dotnet/src/SemanticKernel.Abstractions/Contents/FunctionCallContent.cs`.
- .NET Mistral loop/error behavior:
  `dotnet/src/Connectors/Connectors.MistralAI/Client/MistralClient.cs`.
- .NET planner manual helpers:
  `dotnet/src/InternalUtilities/planning/Extensions/ReadOnlyFunctionCollectionPlannerExtensions.cs`.
- Planner guidance:
  `https://learn.microsoft.com/en-us/semantic-kernel/concepts/planning`.
