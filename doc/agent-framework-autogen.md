# Microsoft AutoGen Agent/Tool Handling Notes

## Scope

Reviewed Microsoft AutoGen source and docs cloned to:

```text
/var/folders/pt/yhlb769j4j1frcvj3mk_fy240000gp/T/opencode/agent-frameworks/autogen
```

Focus: prompt/agent protocol, tool execution loop, message roles, error handling,
retry/termination rules, and what this means for a FoundationModels/Genkit
adapter.

## Key Takeaway

AutoGen's current Python AgentChat path is structured-tool first. It does not ask
the model to print tool-call markup for normal tools. The model client returns
typed `FunctionCall` objects, the agent executes them, appends typed
`FunctionExecutionResultMessage` entries to context, then either returns a tool
summary or does one final reflection call with tools disabled.

AutoGen still has text/protocol execution patterns, but they are scoped to code
execution: extract fenced markdown code blocks, run them, feed stdout/stderr back
as a normal user message, and optionally retry. That pattern is useful for
FoundationModels only as a fallback. It is less robust than native tool capture.

## Source Evidence

- Python `AssistantAgent` tool behavior docs:
  `python/packages/autogen-agentchat/src/autogen_agentchat/agents/_assistant_agent.py`
  lines 137-146.
- Python `AssistantAgent` main flow:
  `_assistant_agent.py` lines 932-1011.
- Python tool loop:
  `_assistant_agent.py` lines 1149-1325.
- Python tool execution/error conversion:
  `_assistant_agent.py` lines 1536-1624.
- Python standalone `ToolAgent`:
  `python/packages/autogen-core/src/autogen_core/tool_agent/_tool_agent.py`
  lines 40-96.
- Python code-block/text protocol executor:
  `python/packages/autogen-agentchat/src/autogen_agentchat/agents/_code_executor_agent.py`
  lines 100-153 and 520-727.
- Python termination conditions:
  `python/packages/autogen-agentchat/src/autogen_agentchat/conditions/_terminations.py`
  lines 23-155.
- .NET built-in message taxonomy:
  `dotnet/website/articles/Built-in-messages.md` lines 13-18.
- .NET middleware/function-call docs:
  `dotnet/website/articles/Use-function-call.md` lines 3-9 and
  `dotnet/website/articles/Middleware-overview.md` lines 1-25.
- .NET `FunctionCallMiddleware` source:
  `dotnet/src/AutoGen.Core/Middleware/FunctionCallMiddleware.cs` lines 15-31
  and 63-189.

## Prompt/Agent Protocol

Python `AssistantAgent` default system message is direct and termination-oriented:

```text
You are a helpful AI assistant. Solve tasks using your tools. Reply with TERMINATE when the task has been completed.
```

The prompt does not encode a text tool protocol. Tool availability is passed to
the model client as structured tools via `model_client.create(..., tools=tools)`.
The agent keeps system messages separate and prepends them at inference time.

Important protocol separation:

- User/handoff messages are added to model context first.
- Memory may inject extra context before inference.
- Model output is stored as `AssistantMessage` whether text or `FunctionCall`
  list.
- Tool results are stored as `FunctionExecutionResultMessage`, not prose.
- Handoff calls are modeled as tools but become `HandoffMessage` responses.

## Message Roles And Shapes

AutoGen keeps internal messages typed, then provider connectors translate them
to vendor roles.

Core Python shapes:

- `TextMessage`: final assistant/user text.
- `ToolCallRequestEvent`: emitted when model returns `FunctionCall` objects.
- `ToolCallExecutionEvent`: emitted after tool calls finish.
- `ToolCallSummaryMessage`: final response when `reflect_on_tool_use=False`.
- `FunctionExecutionResultMessage`: model-context entry containing tool results.
- `HandoffMessage`: agent-transfer message with optional tool-call context.
- `ThoughtEvent`: separate event for hidden model thoughts when available.

.NET uses parallel concepts:

- `TextMessage` for text.
- `ToolCallMessage` for function-call requests.
- `ToolCallResultMessage` for function-call results.
- `ToolCallAggregateMessage` for request+result pairs returned by
  `FunctionCallMiddleware`.

For Genkit, map these to structured `model`, `tool`, and event parts. Do not
collapse tool calls/results into assistant text unless a provider lacks any
structured path.

## Tool Execution Loop

Python `AssistantAgent` loop, simplified:

1. Add incoming messages to model context.
2. Call LLM with tools and optional structured output type.
3. If model returns text, return `TextMessage`/`StructuredMessage` immediately.
4. If model returns `FunctionCall[]`, emit `ToolCallRequestEvent`.
5. Execute all requested tools concurrently with `asyncio.gather`.
6. Emit `ToolCallExecutionEvent` and append `FunctionExecutionResultMessage`.
7. If a handoff tool was called, return first handoff.
8. If `max_tool_iterations` remains, call the LLM again with updated context.
9. After loop, either summarize tool results or reflect with tools disabled.

Defaults matter:

- `max_tool_iterations=1`.
- `reflect_on_tool_use=False` unless structured output is requested.
- Multiple tool calls execute concurrently unless the model client disables
  parallel tool calls.
- Reflection call uses `tool_choice="none"`, preventing recursive tool calls in
  the final answer.

## Error Handling

Python `AssistantAgent` converts normal tool-call failures into structured tool
results, not thrown agent errors:

- Invalid JSON arguments become `FunctionExecutionResult(is_error=True,
  content="Error: ...")`.
- Unknown tool becomes `FunctionExecutionResult(is_error=True,
  content="Error: tool 'x' not found in any workbench")`.
- Workbench tool errors are represented by `ToolResult.is_error` and converted
  to `FunctionExecutionResult.is_error`.

Standalone Python `ToolAgent` is stricter: it raises `ToolNotFoundException`,
`InvalidToolArgumentsException`, or `ToolExecutionException`. AgentChat's
assistant path is more adapter-friendly because the model can see recoverable
tool errors as context.

.NET `FunctionCallMiddleware` behavior differs:

- If the last inbound message is `ToolCallMessage`, middleware invokes tools and
  short-circuits the inner agent.
- If the agent reply is `ToolCallMessage`, middleware invokes known tools and
  returns `ToolCallAggregateMessage`.
- Missing function map before invoking the agent throws.
- Missing tool after invoking the agent leaves the original `ToolCallMessage`
  unchanged unless a map exists and no calls match.
- Streaming middleware merges `ToolCallMessageUpdate` chunks before execution.

## Retry Rules

Normal AutoGen tool use has bounded iteration, not automatic retry:

- Bad tool args or tool errors are sent back as tool results.
- Another LLM call happens only if `max_tool_iterations > 1` or reflection is on.
- No special retry policy fixes malformed arguments by default.

Text/protocol code execution has explicit retry:

- `CodeExecutorAgent` extracts fenced `python`/`sh` markdown blocks.
- It executes blocks, appends execution output as a `UserMessage`, then reflects.
- On non-zero exit, it asks the model for a structured `RetryDecision`.
- Retries stop when `retry=false`, success exit code, or `max_retries_on_error`
  is reached.
- This retry path requires structured output when `model_client` is used.

## Termination Rules

AutoGen uses explicit termination conditions around teams/conversations:

- `StopMessageTermination`: stop on `StopMessage`.
- `MaxMessageTermination`: stop after a configured message count.
- `TextMentionTermination`: stop when configured text appears, commonly
  `TERMINATE` or `APPROVE`.
- `FunctionalTermination`: user-provided predicate.
- Token usage termination exists for prompt/completion/total token ceilings.

Conditions are stateful. Calling a condition after it has terminated raises
`TerminatedException` until reset.

.NET two-agent docs also use a termination keyword, but recommend post-process
middleware for weaker models because programmatic termination is more robust
than relying only on a prompt keyword.

## Text/Protocol-Based Execution Lessons

AutoGen's clearest non-native protocol is code block execution, not arbitrary
JSON tool markup:

- Protocol surface is tiny: fenced markdown blocks with allowed languages.
- Parser is intentionally narrow: regex only accepts configured languages.
- Execution has an approval hook before running code.
- Empty output and non-zero exits are normalized into model-readable text.
- Retry is bounded and asks for an explicit structured retry decision.

If FoundationModels cannot expose a native tool call for some path, use the same
shape: one narrow grammar, strict parser, explicit approval/safety gate,
structured execution result, bounded retry. Do not build a broad natural-language
tool parser.

## Recommendations For FoundationModels/Genkit Adapter

1. Prefer native FoundationModels tools and transcript tool entries.

   AutoGen's stable path is structured message/tool state. FoundationModels
   should capture native tool calls and translate them to Genkit
   `ToolRequestPart`s. Avoid prompt tags for normal tools.

2. Keep tool calls and tool results out of assistant prose.

   Preserve a typed internal event stream: tool request, tool result, final text.
   Text summaries are a presentation option, not the source of truth.

3. Default to one tool iteration.

   Match AutoGen's `max_tool_iterations=1`. Add a small configurable ceiling
   only when multi-step tool use is required. This prevents accidental loops.

4. Add optional reflection with tools disabled.

   After tool results, either return raw tool summary or make one final model
   call with tools unavailable. This avoids infinite tool recursion and mirrors
   AutoGen's `tool_choice="none"` reflection behavior.

5. Convert adapter/tool failures into tool-result parts when recoverable.

   Invalid JSON, unknown tool, schema mismatch, and tool exception should become
   structured error tool results with `isError=true`-equivalent metadata. Reserve
   thrown errors for adapter bugs, cancellation, or unsafe execution denial.

6. Preserve stable tool-call IDs.

   AutoGen carries `FunctionCall.id` into `FunctionExecutionResult.call_id`.
   Genkit refs should do the same so tool results can be paired without parsing
   text.

7. Disable parallel calls unless FoundationModels/Genkit can safely correlate
   them.

   AutoGen allows concurrent tool execution but warns around multiple handoffs.
   FoundationModels adapter should start serial or explicitly ordered. Parallel
   execution can come later if IDs and result ordering are proven.

8. Use programmatic termination before prompt keywords.

   `TERMINATE` is useful for demos, but adapter loops should stop on structured
   conditions: no tool call, max iterations reached, cancellation, token budget,
   or explicit stop signal.

9. If text fallback is unavoidable, keep grammar tiny.

   Use one fenced block form, for example:

   ````text
    ```json
    {"toolRequest":{"name":"toolName","arguments":{}}}
   ```
   ````

   Parse only exact fenced blocks, validate against registered tool names/schema,
   return parse errors as tool results, and cap retries. Do not infer tool calls
   from ordinary prose.

10. Stream as events, not token-only text.

    AutoGen streams chunks but final typed messages still drive state. Genkit
    chunks should carry text deltas/snapshots separately from tool request/result
    events.

## Minimal Adapter Loop

```text
messages -> FoundationModels transcript
tools -> native FoundationModels Tool wrappers

for iteration in 1...maxToolIterations:
  run model
  if text only: return model text
  if tool calls:
    emit Genkit tool requests with stable refs
    execute matching Genkit tools
    append tool outputs to transcript

if reflect:
  run model with tools disabled
  return final text

return tool result summary or structured tool result response
```

Skipped: broad ReAct-style `Thought/Action/Observation` parser. Add only if
native FoundationModels tools cannot represent required Genkit tool behavior.
