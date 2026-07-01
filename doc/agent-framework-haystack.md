# Haystack Agent/Tool Invocation Notes

## Scope

Reviewed deepset Haystack source at commit `715ffcb` in:

```text
/var/folders/pt/yhlb769j4j1frcvj3mk_fy240000gp/T/opencode/agent-frameworks/haystack
```

Focus: behavior when native provider tool calling is unavailable or not used.

## Main Finding

Haystack's current `Agent` is built around structured tool calls, not a general
ReAct-style prompt protocol. It requires a chat generator whose `run()` accepts a
`tools` argument when tools are configured. If the generator lacks that argument,
`Agent.__init__` raises `TypeError`.

The one built-in non-native-ish path found is `HuggingFaceLocalChatGenerator`:
it passes tool schemas into the Hugging Face tokenizer chat template and then
parses generated text for a tool-call shape. That fallback is generator-specific,
regex-based, and deprecated in core Haystack for Haystack 3.0.

## Prompt Structure

`Agent` prompt construction is minimal:

- `system_prompt` becomes a system `ChatMessage`, or is rendered through
  `ChatPromptBuilder` if it uses Jinja2 chat-template syntax.
- `user_prompt` is rendered through `ChatPromptBuilder` and must produce exactly
  one user message.
- Runtime `messages` remain typed `ChatMessage` objects.
- Tool schemas are not appended to the system prompt by `Agent`; they are passed
  separately to the chat generator as `tools`.

For local Hugging Face generation, prompt rendering happens inside
`tokenizer.apply_chat_template(...)` with:

```python
tools=[tc.tool_spec for tc in flat_tools] if flat_tools else None
```

So the actual prompt text depends on the model tokenizer's chat template, not on
a Haystack-owned prompt block.

## Tool Schema Rendering

Haystack `Tool` exposes `tool_spec`:

```python
{"name": self.name, "description": self.description, "parameters": self.parameters}
```

`parameters` is JSON Schema and is validated with `jsonschema.Draft202012Validator`
when the `Tool` is created. Tool descriptions and parameter descriptions matter
because Haystack delegates selection/argument generation to the model/provider.

Provider adapters translate this structured spec to provider-native tool formats.
For example, OpenAI message conversion serializes assistant tool calls as
OpenAI-style `tool_calls` with `function.name` and JSON string `function.arguments`.

## Execution Loop

`Agent.run()` loops until `max_agent_steps`:

1. Call the chat generator with current `messages` and selected `tools`.
2. Append returned assistant `ChatMessage` replies into agent `State.messages`.
3. If there is no tool invoker, or the last assistant message has text and no
   tool calls, stop for the default `exit_conditions=["text"]` case.
4. Apply optional human confirmation strategies to tool-call messages.
5. Call internal `ToolInvoker` with only the LLM messages that contain tool calls.
6. Append tool result messages into `State.messages`.
7. If a configured tool-name exit condition was met, stop; otherwise continue.

`ToolInvoker` executes multiple tool calls concurrently with a thread pool
(`max_workers`, default `4`). It injects state-derived arguments, optional live
`State`, and optionally a `streaming_callback` if the tool accepts it. Results are
returned as `ChatMessage.from_tool(...)` with a `ToolCallResult` referencing the
origin `ToolCall`.

## Observations

Tool observations are typed messages, not text markers:

```python
ChatMessage.from_tool(tool_result=..., origin=tool_call, error=False)
```

The observation payload is usually a string. `ToolInvoker` defaults to `str()` on
serializable tool output, or `json.dumps(..., ensure_ascii=False)` when
`convert_result_to_json_string=True`. Tools can customize output conversion via
`outputs_to_string`, and can write structured values into agent state via
`outputs_to_state`.

When `raise_on_tool_invocation_failure=False` on `Agent`, tool invocation errors
become tool messages with `error=True` and are sent back to the model so it can
recover. When true, failures raise.

## Parser And Retry Behavior

Core `Agent` has no general parser/retry loop for text-formatted tool calls. It
expects the generator to return `ChatMessage` objects containing structured
`ToolCall` parts.

Provider/parser behavior found:

- Streaming chunks are accumulated into a `ChatMessage`; malformed JSON tool-call
  arguments are logged and that tool call is skipped.
- OpenAI/OpenAI Responses adapters do the same skip-on-malformed-arguments
  behavior and recommend strict tool mode (`tools_strict`) where supported.
- `HuggingFaceLocalChatGenerator` has `default_tool_parser(text)`, which searches
  generated text with `DEFAULT_TOOL_PATTERN` for either `{ "name": ..., "arguments": ... }`
  or OpenAI-like `{ "function": { "name": ..., "arguments": ... } }`. It returns
  one `ToolCall` or `None`. JSON decode failure logs a warning and yields no tool
  call.

There is no automatic repair prompt, schema validation retry, or parser retry in
the agent loop. If parsing fails and the model output is plain assistant text,
the agent can terminate as a text response.

## Max Iterations And Termination

Defaults and controls:

- `max_agent_steps=100`.
- Default `exit_conditions=["text"]` stops when the model returns a non-empty
  assistant text message with no tool calls.
- `exit_conditions` can include tool names; the agent can stop after those tools
  execute.
- If `max_agent_steps` is reached, Haystack logs a warning and returns current
  state instead of raising.
- If no tools are configured, `Agent` behaves like a chat generator and returns
  one text response.

Important nuance: an invalid empty assistant message with no text and no tool
calls does not satisfy the text exit condition, so the loop can continue until
`max_agent_steps`.

## Streaming

Haystack supports structured streaming chunks with optional text, reasoning,
tool-call deltas, and tool-call results. `print_streaming_chunk` prints visible
sections like `[TOOL CALL]`, `[TOOL RESULT]`, and `[ASSISTANT]`, but those are
display formatting only.

`HuggingFaceLocalChatGenerator` rejects tools plus streaming at the same time.
`ToolInvoker` can emit full tool results through the streaming callback once a
tool result is ready; it does not stream tool output incrementally unless callback
passthrough is enabled and the tool itself supports that parameter.

## Recommendations For This Package

Do not copy Haystack's regex fallback as the primary design for Apple Foundation
Models. Haystack's main architecture supports the same conclusion as the existing
Genkit plan: keep tool calls and observations structured.

Recommended adapter shape:

- Expose Genkit tools to the native provider as structured tools whenever
  Foundation Models supports that path.
- Capture native tool calls into Genkit `ToolRequestPart`s; keep ids/refs stable.
- Return Genkit tool results as structured provider transcript/tool-output entries
  where possible.
- If a provider cannot expose native tool calls, prefer disabling tools for that
  model over adding a broad prompt parser.
- If a text fallback is unavoidable, make it explicitly opt-in, non-streaming,
  schema-narrow, and bounded by a small max-iteration limit. Treat malformed JSON
  as a failed tool call or final model error, not as silent assistant text.
- Keep `max_agent_steps` low for local text fallbacks. Haystack's default `100` is
  safe for a Python server loop but too high for mobile/on-device accidental
  parser failures.
- Store observations as typed conversation parts in the adapter boundary. Only
  stringify at the provider edge if the API requires text tool outputs.

Minimal implementation implication: no Haystack-style framework layer is needed
here. A small loop that alternates native model calls, captured tool requests,
Genkit tool execution, and structured tool-result injection covers the useful
parts without inheriting parser fragility.
