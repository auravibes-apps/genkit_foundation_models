# LlamaIndex Agent Tool Calling Notes

Research date: 2026-06-30T07:16:17-0500.

Sources read:

- LlamaIndex Python docs via Context7, target `run-llama/llama_index` v0.14.6.
- LlamaIndex source cloned to `/var/folders/pt/yhlb769j4j1frcvj3mk_fy240000gp/T/opencode/agent-frameworks/llamaindex`.
- Key source files:
  - `llama-index-core/llama_index/core/agent/react/templates/system_header_template.md`
  - `llama-index-core/llama_index/core/agent/react/formatter.py`
  - `llama-index-core/llama_index/core/agent/react/output_parser.py`
  - `llama-index-core/llama_index/core/agent/workflow/react_agent.py`
  - `llama-index-core/llama_index/core/agent/workflow/base_agent.py`

## Summary

When provider-native tool calling is not used, LlamaIndex ReAct agents use a
plain-text protocol. The model is prompted to emit `Thought`, `Action`, and
`Action Input` blocks. LlamaIndex parses those blocks into a tool call, executes
the tool outside the model, appends an `Observation` to an in-memory scratchpad,
and asks the model again until it emits `Answer` or hits max iterations.

This is useful fallback behavior, but it is explicitly weaker than native tool
calling. It depends on prompt compliance, parser recovery, and loop guards.

## Prompt Structure

LlamaIndex's default ReAct system header has these sections:

- Generic role instruction.
- `## Tools` section.
- Tool inventory inserted as `{tool_desc}`.
- Optional context inserted as `{context}`.
- `## Output Format` section.
- Current conversation marker.

Tool descriptions are generated in `get_react_tool_descriptions`:

```text
> Tool Name: {name}
Tool Description: {description}
Tool Args: {json_schema_string}
```

The ReAct output format is strict:

```text
Thought: The current language of the user is: (user's language). I need to use a tool to help me answer the question.
Action: tool name (one of {tool_names}) if using a tool.
Action Input: the input to the tool, in a JSON format representing the kwargs (e.g. {"input": "hello world"})
```

Final answer format:

```text
Thought: I can answer without using any more tools. I'll use the user's language to answer
Answer: [your answer here]
```

Important prompt rules:

- Always start with `Thought`.
- Never wrap the response in markdown code fences.
- `Action Input` must be valid JSON.
- If `Action:` exists, `Action Input:` must also exist, even when `{}`.
- Tool responses are shown back to the model as `Observation: tool response`.

## Action / Observation Loop

LlamaIndex stores current ReAct reasoning in `current_reasoning`. Each loop:

1. Build LLM input from system header, chat history, and scratchpad.
2. Call the LLM.
3. Parse output.
4. If parsed as `Answer`, finalize.
5. If parsed as `Action`, convert to `ToolSelection` with generated UUID.
6. Execute tool.
7. Append `ObservationReasoningStep` with tool output.
8. Repeat.

The scratchpad is not persisted as separate structured tool messages by default.
`ReActChatFormatter` appends reasoning steps to the next prompt as chat messages:

- action/thought steps use assistant role;
- observations use user role by default;
- observation role can be switched to tool role when the LLM supports native tool
  messages.

## Output Parser

`ReActOutputParser` checks for `Thought:`, `Action:`, and `Answer:`. If none are
present, it treats the whole model output as a direct final answer.

Action parsing uses regex roughly shaped as:

```text
Thought: ...
Action: <no-space-tool-name>
Action Input: { ... }
```

The parser accepts useful deviations:

- missing `Thought:` if plain text appears before `Action:`;
- extra blank lines;
- `Action: add (description)` while extracting only `add`;
- multiline JSON;
- non-ASCII tool names;
- wrapper text like `QueryEngineTool({ ... })` because it extracts the JSON;
- dirty JSON with comments/single quotes via `dirtyjson` fallback;
- final answers containing the word `Action:` after `Answer:`.

Parser limitations:

- It still needs a JSON object for action input.
- It does not validate tool names in the parser.
- It prioritizes an `Action` before an `Answer` when the action marker appears
  first.
- It is regex-based text parsing, not a structured protocol.

## Parser Recovery

Current workflow recovery is simple and effective:

- Empty model output returns `retry_messages` containing the bad assistant
  message plus a user correction that restates the required format.
- Parser `ValueError` returns `retry_messages` containing the bad assistant
  message plus a user correction with both valid formats.
- The workflow retries through the same agent loop.

This is cheaper than failing immediately and avoids adding separate parser repair
models.

## Stop Conditions

The agent stops when:

- a parsed `ResponseReasoningStep` is produced from `Answer:`;
- a successful `return_direct` tool result is produced;
- max iterations are reached.

Default max-iteration handling lives in `BaseWorkflowAgent`:

- `force`: raise a workflow runtime error;
- `generate`: append a system prompt saying max iterations were reached and ask
  for a final response without more tools.

The early-stop prompt says not to use more tools and to summarize gathered
information.

## Invalid Tool Calls

Invalid tool names are handled at execution time, not parse time. The base agent
returns a tool output marked `is_error`:

```text
Tool {name} not found. Please select a tool that is available.
```

Tool exceptions are also converted into `ToolOutput(is_error: true)` with the
exception text as content. The ReAct agent appends that error content as an
`Observation`, then loops. The model gets a chance to choose a valid tool or
answer without one.

## Repeated Tool Calls

LlamaIndex does not appear to have a special repeated-tool-call guard in ReAct.
Repeated calls are bounded by max iterations. If a tool has `return_direct`, a
successful result stops the loop. Otherwise, repeated same-name/same-args calls
can continue until max iterations.

For text-protocol agents this is acceptable as a generic framework default, but
provider adapters can do better when tool refs exist.

## Fit For This Package

This package already follows the better path: native captured tool calls first,
JSON parsing only as compatibility fallback. That should stay.

Recommendations:

1. Keep native Foundation Models tool capture as the primary path. LlamaIndex
   ReAct is evidence that text protocols need retries and loop guards; it is not
   evidence to prefer text protocols.
2. Keep JSON fallback parsing as leak prevention and compatibility only. Do not
   expand it into full `Thought/Action/Observation` unless native tool capture
   becomes impossible.
3. If fallback prompting is needed, use a compact LlamaIndex-style format:

   ```text
   Tools:
   > Tool Name: name
   Tool Description: description
   Tool Args: JSON schema

   To call tools, output exactly:
   {"toolRequests":[{"name":"tool_name","arguments":{}}]}

   Otherwise answer normally.
   ```

   This keeps fallback syntax JSON-only and avoids adding a scratchpad protocol.
4. Keep allowed-tool-name validation. LlamaIndex validates at execution time;
   this provider validates while mapping model output. Earlier rejection is safer
   for a provider boundary.
5. Keep repeated completed-ref rejection. LlamaIndex relies on max iterations;
   this package has refs, so rejecting exact completed refs is the smaller and
   safer guard.
6. Do not reject repeated tool names by themselves. Agents often call the same
   tool with different args. Reject only exact completed refs or malformed calls.
7. For parser recovery, prefer one retry without tools after a tool-response turn
   over adding a general parser-repair loop. Current `_shouldRetryWithoutTools`
   is enough for the package's native-first design.
8. If malformed fallback tool JSON leaks in text, treat it as text. Silent
   repair creates surprising calls. Native calls already cover the reliable path.
9. Keep streaming conservative. Native tool-enabled streams should prefer final
   structured events over provisional text protocol parsing.
10. Document `foundationModelsToolLoopMode: singlePhase` as a compatibility knob,
    not default agent architecture. Multi-turn Genkit orchestration should remain
    the normal loop owner.

## Minimal Changes Worth Considering

- Add one doc note in README later: native tool calls are preferred; JSON tool
  fallback is cleanup only.
- Add one test if missing later: malformed fallback JSON stays text or fails
  predictably without executing any tool.

No larger ReAct scratchpad implementation recommended. Genkit already owns the
agent loop, and Apple Foundation Models can expose structured tool calls.
