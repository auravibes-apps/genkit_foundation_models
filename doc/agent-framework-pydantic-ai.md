# PydanticAI Agent/Tool Handling

Research date: 2026-06-30T07:16:54-0500  
Source: upstream `pydantic/pydantic-ai` cloned to `/var/folders/pt/yhlb769j4j1frcvj3mk_fy240000gp/T/opencode/agent-frameworks/pydantic-ai`, commit `abd3e6e` (`2026-06-30T08:47:39+02:00`). Docs show V2 stable as of `v2.0.0` on 2026-06-23.

## Executive Summary

PydanticAI is a strong reference for schema-first agents. Its core loop is simple: build a `ModelRequest`, attach instructions, function tools, native tools, and output tools, call the model, append `ModelResponse`, then either execute tool calls or end on validated output.

Best ideas to copy for this package:

- Keep provider-neutral message parts: `ModelRequest`, `ModelResponse`, `UserPromptPart`, `SystemPromptPart`, `InstructionPart`, `ToolCallPart`, `ToolReturnPart`, and `RetryPromptPart`.
- Treat structured final output as tools by default. This works across most tool-capable models and gives one validation/retry path for normal tools and final answers.
- Support three output modes: tool output, native JSON schema output, and prompted JSON output. Prompted output is fallback for models without native tool calling or native structured output.
- Convert validation failures into explicit retry messages in history, not hidden internal retries.
- Track retry budgets separately for tool calls and output validation. Fail with a clear exception when budgets are exhausted.
- Make termination explicit with `end_strategy` for mixed output-tool/function-tool responses.

## Prompt And Message Structure

PydanticAI models a run as a message history of typed request/response objects. A request contains parts plus an optional joined `instructions` string. A response contains typed parts: text, thinking, tool calls, files, and other provider-normalized parts.

Relevant source:

- `docs/tools.md:72-157` shows a complete message trace: user request, tool call response, tool return request, second tool call, second tool return, final text response.
- `docs/message-history.md:13-14` exposes `all_messages()` and `new_messages()`.
- `docs/message-history.md:147-153` says non-empty `message_history` suppresses new system prompt generation; `ReinjectSystemPrompt` can restore missing system prompts.
- `pydantic_ai_slim/pydantic_ai/_agent_graph.py:372-379` builds the first request from system prompt parts plus user prompt.
- `pydantic_ai_slim/pydantic_ai/_agent_graph.py:905-910` resolves instruction parts each request and stores joined instructions on `ModelRequest.instructions`.
- `pydantic_ai_slim/pydantic_ai/models/__init__.py:393-418` provider-normalizes messages before wire mapping, including wrapping non-leading system prompts as `<system>...</system>` user parts when the provider cannot handle inline system messages.

Important distinction:

- `system_prompt` becomes `SystemPromptPart`s in the first request. Dynamic system prompt parts can be reevaluated later by `dynamic_ref`.
- `instructions` are recomputed per request and stored as `ModelRequest.instructions`. Provider adapters can map this as top-level system/developer instructions.
- `prompted_output_instructions` are appended to `instruction_parts` during model request preparation when output mode is `prompted` or native mode needs schema instructions.

Recommendation:

- Do not flatten everything to provider message strings too early. Keep a typed, provider-neutral internal transcript and adapter-specific rendering at the edge.
- Preserve run IDs and conversation IDs on every request/response. PydanticAI resolves conversation IDs from explicit input, prior history, or new UUID (`_agent_graph.py:110-134`).

## Tool Definitions

Function tools are Python callables. PydanticAI inspects signatures, removes `RunContext`, builds JSON schema for remaining params, extracts docstring and parameter descriptions, and exposes a `ToolDefinition` to models.

Relevant source:

- `docs/tools.md:9-15` lists registration routes: `@agent.tool`, `@agent.tool_plain`, `tools=[...]`, and `toolsets=[...]`.
- `docs/tools.md:256-314` describes schema extraction from function signatures and docstrings.
- `pydantic_ai_slim/pydantic_ai/tools.py:438-580` defines `Tool`, including retries, name, description, prepare hook, arg validator, strict mode, sequential barrier, approval, timeout, and return schema.
- `pydantic_ai_slim/pydantic_ai/tools.py:686-890` defines `ToolDefinition`, shared by function tools and output tools.
- `pydantic_ai_slim/pydantic_ai/_agent_graph.py:489-553` splits tool definitions into `function_tools` and `output_tools`, resolves native tools, and builds `ModelRequestParameters`.

ToolDefinition fields worth copying:

- `name`
- `description`
- `parameters_json_schema`
- `strict`
- `sequential`
- `kind`: `function`, `output`, `external`, `unapproved`
- `metadata` not sent to model
- `timeout`
- `return_schema` and `include_return_schema`

Dynamic availability:

- Per-tool `prepare(ctx, tool_def)` may modify or omit a tool for a step (`docs/tools-advanced.md:154-166`).
- Agent-wide `prepare_tools` can filter/modify all tools each step (`docs/tools-advanced.md:252-343`).
- Return `[]` to expose no tools; V2 treats `None` from prepare callbacks as an error (`docs/changelog.md:53-58`).

Recommendation:

- Implement a single `ToolDefinition` type for both callable tools and final-output tools.
- Keep `metadata` internal. Never leak routing/permission metadata to the model unless explicitly wanted.
- Use a prepare hook only if tool availability actually changes per turn. Static tool lists need no abstraction.

## Tool Argument Validation And Retries

PydanticAI validates tool args before execution. Validation uses the generated Pydantic schema and optional custom `args_validator`. Failures become `RetryPromptPart` messages, which are appended to history and sent back to the model.

Relevant source:

- `pydantic_ai_slim/pydantic_ai/tool_manager.py:210-245` validates raw JSON/string or dict args with Pydantic, using `validation_context`, then runs custom arg validators.
- `pydantic_ai_slim/pydantic_ai/tool_manager.py:178-186` wraps `ValidationError` or `ModelRetry` into a `RetryPromptPart`.
- `pydantic_ai_slim/pydantic_ai/tool_manager.py:172-177` enforces max retries per tool.
- `pydantic_ai_slim/pydantic_ai/tool_manager.py:414-460` validates a tool call before execution and records validation failure without executing.
- `docs/agent.md:1203-1295` shows failed tool retry history and `UnexpectedModelBehavior` after retry exhaustion.

Retry prompt content:

- For Pydantic `ValidationError`, content is `error.errors(include_url=False, include_context=False)`.
- For `ModelRetry`, content is the human-authored retry message.
- The retry prompt carries `tool_name` and `tool_call_id` when tied to a tool call.

Execution behavior:

- Unknown tool names are retryable: `Unknown tool name: ... Available tools: ...` (`tool_manager.py:351-365`).
- Tool timeout returns a retry prompt to the model (`tools.py:547-549`).
- Per-tool retries default to `1`, configurable per agent/run/tool (`tool_manager.py:91`, `docs/agent.md:1100-1145`).

Recommendation:

- Validate before executing side effects.
- Put validation errors in transcript as first-class model feedback.
- Keep retry prompts concise and machine-actionable; include allowed tool names for unknown tool calls.

## Structured Output Modes

PydanticAI has three output modes:

1. Tool output: default. Each output type/function is exposed as an output tool. The tool call ends the run.
2. Native output: provider-native JSON schema response format.
3. Prompted output: inject JSON schema into instructions and parse the text response.

Relevant source:

- `docs/output.md:313-320` lists the three modes.
- `docs/output.md:321-329` describes default output tools and per-output-tool retry limits.
- `docs/output.md:394-399` describes native output.
- `docs/output.md:422-430` describes prompted output as fallback for models without tool calling or structured output.
- `pydantic_ai_slim/pydantic_ai/profiles/__init__.py:25-34` defines the default prompted-output instruction template: “Always respond with a JSON object that's compatible with this schema...”
- `pydantic_ai_slim/pydantic_ai/models/__init__.py:349-383` applies model default output mode, injects prompted schema instructions, and errors when requested mode is unsupported.

Prompted output details:

- It can use provider JSON-object mode when available, but schema compliance is still model-dependent (`docs/output.md:428-430`).
- PydanticAI validates the parsed data and asks the model to retry on validation failure.
- It is the only built-in structured-output path for models without native tool calling and without native structured output.

Recommendation:

- Use tool output by default when model supports tools.
- Use native output when provider supports JSON schema and no conflicting tool limitations exist.
- Use prompted output only as fallback. It is less reliable because schema adherence is prompt-based.

## Output Validation And Result Validators

PydanticAI validates final output with Pydantic and optional output validators. Output validators can do IO and can raise `ModelRetry` to ask the model to produce another result.

Relevant source:

- `docs/output.md:41-43` says structured outputs use Pydantic JSON schema generation and validation.
- `docs/output.md:560-568` describes `@agent.output_validator` and output retry budget.
- `pydantic_ai_slim/pydantic_ai/_output.py:121-129` converts output validation errors into `RetryPromptPart`.
- `pydantic_ai_slim/pydantic_ai/_output.py:306-363` runs output validate/process hooks and validators.
- `pydantic_ai_slim/pydantic_ai/_output.py:407-437` defines `OutputValidator` execution.
- `pydantic_ai_slim/pydantic_ai/_agent_graph.py:178-195` tracks global output retry budget and raises `UnexpectedModelBehavior` when exceeded.

Validation context:

- `validation_context` is passed to both tool arg validation and structured output validation (`docs/output.md:504-515`).
- It is not sent to the LLM.
- It can be static or derived from `RunContext`.

Output functions:

- Output functions are like final tools: model provides args, Pydantic validates args, function runs, and run ends (`docs/output.md:118-126`).
- They are better than a generic output validator when each output type needs separate logic (`docs/output.md:566-567`).

Recommendation:

- Separate schema validation from business validation.
- Let business validators raise model-facing retry messages for recoverable errors.
- Keep output retry budget separate from tool retry budget.

## Termination

A run ends when the model returns a valid output type. If no output type is specified, or `str` is allowed, plain text can end the run. It can also end on `None` if optional output allows empty response.

Relevant source:

- `docs/output.md:7` defines termination by matching output type or usage limits.
- `docs/output.md:694-730` explains optional `None` output and empty response handling.
- `pydantic_ai_slim/pydantic_ai/_agent_graph.py:1076-1140` starts response handling: empty/thinking-only responses are non-actionable unless `None` is allowed.
- `docs/output.md:363-388` documents `end_strategy` for responses containing both output tools and function tools.
- `pydantic_ai_slim/pydantic_ai/_agent_graph.py:67-89` defines `end_strategy`: `early`, `graceful`, `exhaustive`.
- `pydantic_ai_slim/pydantic_ai/_tool_execution.py:100-143` implements strategy-specific tool processing.

End strategies:

- `graceful` default: run tools in emission order; first successful output wins; later outputs skipped; function tool retry suppresses final output so model can correct.
- `early`: first successful output ends run and skips function tools.
- `exhaustive`: run all tools; first valid output by emission order wins.

Streaming caveat:

- `run_stream()` commits first matching output immediately. Later tool calls may not run. Use `run_stream_events()` or `iter()` to run full graph while streaming (`docs/agent.md:131-137`, `docs/output.md:732-744`).

Recommendation:

- Default to `graceful` equivalent. It avoids dropping side effects when output and tools appear together.
- Offer `early` only as performance option for agents with side-effect-free tools.
- Document streaming semantics loudly. First-output-wins is surprising.

## Native Tool Calling Unavailable

PydanticAI separates model capabilities from agent logic through `ModelProfile`.

Relevant source:

- `pydantic_ai_slim/pydantic_ai/profiles/__init__.py:48-70` has `supports_tools`, `supports_json_schema_output`, and `supports_json_object_output`.
- `pydantic_ai_slim/pydantic_ai/profiles/__init__.py:83-90` has default structured output mode and prompted output template.
- `pydantic_ai_slim/pydantic_ai/models/__init__.py:379-383` errors if native output or tool output is requested but unsupported.
- `docs/output.md:422-430` says prompted output is fallback for models without tool calling or structured output.
- `pydantic_ai_slim/pydantic_ai/models/__init__.py:420-504` swaps/drops native tools and local function fallbacks based on provider support.

What happens without native tool calling:

- Tool output mode requires tool support. If `supports_tools=False`, it raises `UserError`.
- Structured output should use `PromptedOutput` if no tool or native JSON schema support exists.
- Prompted output injects a schema into instructions, parses text, validates locally, and retries via `RetryPromptPart` on invalid output.
- Function tools themselves cannot be natively called without tool support unless this package adds a custom text-to-tool parser. PydanticAI does not appear to provide a generic ReAct-style textual function-call parser in this path; it fails unsupported tool mode instead.

Recommendation:

- For this package, do not fake function-tool calling on models without tool APIs unless explicitly required. Prompted output fallback is enough for final structured results.
- If text-based tool calling is later needed, implement it as separate compatibility mode with strict delimiters and same validation/retry path. Do not mix it with native tool mode.

## Concurrency And Deferred Tools

PydanticAI validates calls, emits call events, then executes tools. Function tools can run in parallel, with per-tool `sequential=True` as a barrier. Whole-run execution can also be forced sequential.

Relevant source:

- `pydantic_ai_slim/pydantic_ai/tool_manager.py:94-109` defines run-scoped parallel execution mode.
- `pydantic_ai_slim/pydantic_ai/tool_manager.py:156-164` checks per-tool sequential barrier.
- `pydantic_ai_slim/pydantic_ai/_tool_execution.py:78-97` segments tool calls around barriers.
- `docs/toolsets.md:649-655` describes external toolsets and deferred results.
- `pydantic_ai_slim/pydantic_ai/tools.py:254-324` defines `DeferredToolRequests`.
- `pydantic_ai_slim/pydantic_ai/tools.py:376-419` defines `DeferredToolResults`.

Deferred tools:

- External/unapproved tool calls can end the run with `DeferredToolRequests`.
- Caller executes/approves elsewhere, then resumes with `DeferredToolResults` and original message history.
- Deferred results can be normal return values, `ToolReturn`, `ModelRetry`, or `RetryPromptPart`.

Recommendation:

- Skip deferred tools for initial package scope unless human approval or frontend-executed tools are required.
- If added later, use tool call IDs as the only join key. Validate supplied result IDs against pending calls.

## Error Handling And Observability

PydanticAI treats model misbehavior as normal control flow until retry budgets are exhausted. Then it raises `UnexpectedModelBehavior` and preserves messages for diagnosis.

Relevant source:

- `docs/agent.md:1203-1207` documents `UnexpectedModelBehavior` and `capture_run_messages`.
- `docs/agent.md:1223-1288` shows captured history after retries are exhausted.
- `docs/agent.md:1298-1300` says interrupted request/response messages are captured with `state='interrupted'`.
- `docs/agent.md:1147-1177` recommends tracing messages, tool args/returns, usage, latency, and errors.

Recommendation:

- Persist traceable message history for every failed agent run.
- Redact tool args/returns at observability boundary if sensitive.
- Do not swallow retry exhaustion. Raise a typed error with cause and captured transcript.

## Package Recommendations

Minimum implementation for this repo/package:

1. Typed transcript:
   `ModelRequest`, `ModelResponse`, `SystemPromptPart`, `UserPromptPart`, `ToolCallPart`, `ToolReturnPart`, `RetryPromptPart`, `TextPart`.

2. Tool registry:
   Build `ToolDefinition` from callables using type hints and docstrings. Store `name`, `description`, JSON schema, `kind`, `strict`, `sequential`, retry limit, and internal metadata.

3. Validation path:
   Validate tool args before execution. Convert `ValidationError` and explicit retry exceptions into retry prompt parts with tool name and call ID.

4. Structured output path:
   Implement tool-output mode first. Add native JSON schema mode where provider supports it. Add prompted JSON fallback for models without tool/native structured output.

5. Retry budgets:
   Per-tool retry counter and global/per-output retry counter. Exhaustion raises typed exception with captured messages.

6. Termination:
   End on valid output. Default mixed tool/output strategy should be graceful: run preceding/sibling function tools unless a retry invalidates the output.

7. Provider capability profile:
   Track `supports_tools`, `supports_json_schema_output`, `supports_json_object_output`, and default structured output mode per model/provider.

What to skip for now:

- Deferred tools and approval flows unless product needs frontend or human-in-the-loop execution.
- Tool return schemas unless a provider used here supports them or model quality needs them.
- Dynamic tool search/capability loading. Useful, but too much framework for first pass.
- Generic text-based function-tool parsing for non-tool models. Use prompted output only; add textual tool calls only if a target model forces it.

Smallest safe architecture:

```text
Agent.run()
  build ModelRequest(parts, instructions)
  build ModelRequestParameters(function_tools, output_mode, output_tools, output_schema)
  provider.request(messages, params)
  append ModelResponse
  if output: validate/process/end
  if tool calls: validate args -> execute -> ToolReturnPart or RetryPromptPart -> next ModelRequest
  if retry budget exhausted: raise UnexpectedModelBehavior(transcript)
```

Main design constraint: keep all validation/retry feedback in the transcript. Hidden retry state makes agent failures impossible to debug.
